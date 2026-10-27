// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The canonical form of a tree, as RFC 8785 writes it.
///
/// Members are ordered by their names compared as UTF-16 code units — not as
/// code points, which differ for anything above U+FFFF — numbers are written
/// the way ECMAScript writes them, and nothing is escaped that does not have
/// to be. Two trees that hold the same values therefore come out as the same
/// bytes, which is the whole point: a signature over these bytes is a
/// signature over the document.
///
/// A number that is not finite cannot be written, because the RFC's number
/// serialisation is ECMAScript's and ECMAScript has no syntax for it. It is
/// refused rather than replaced with `null` or `0`, either of which would sign
/// something the document does not say.
pub fn dumps(value : Json) -> String raise @moonjson.Refused {
  let out = StringBuilder()
  put(out, value)
  out.to_string()
}

///|
/// The same, as the UTF-8 bytes a signature is taken over.
pub fn dump(value : Json) -> Bytes raise @moonjson.Refused {
  @utf8.encode(dumps(value)[:])
}

///|
fn put(out : StringBuilder, value : Json) -> Unit raise @moonjson.Refused {
  match value {
    Null => out.write_string("null")
    True => out.write_string("true")
    False => out.write_string("false")
    // The text a number arrived as is deliberately ignored: `1e2`, `100` and
    // `1.0e2` are one number, and a canonical form that preserved the spelling
    // would not be canonical.
    Number(n, ..) => number(out, n)
    String(s) => quote(out, s[:])
    Array(items) => {
      out.write_char('[')
      for i, item in items {
        if i > 0 {
          out.write_char(',')
        }
        put(out, item)
      }
      out.write_char(']')
    }
    Object(members) => {
      out.write_char('{')
      let names : Array[String] = []
      for name, _ in members {
        names.push(name)
      }
      names.sort_by(compare_names)
      for i, name in names {
        if i > 0 {
          out.write_char(',')
        }
        quote(out, name[:])
        out.write_char(':')
        put(out, members.get(name).unwrap())
      }
      out.write_char('}')
    }
  }
}

///|
/// Names in UTF-16 code unit order (RFC 8785 §3.2.3). A surrogate pair stands
/// for one character above U+FFFF, and its units sort below U+E000, so
/// comparing code points would put `😀` after `◎` where the RFC puts it before.
fn compare_names(a : String, b : String) -> Int32 {
  let mut i = 0
  while i < a.length() && i < b.length() {
    let left = a.at(i).to_int()
    let right = b.at(i).to_int()
    if left != right {
      return left - right
    }
    i += 1
  }
  a.length() - b.length()
}

///|
/// A string as RFC 8785 §3.2.2.2 writes one: the two characters that must be
/// escaped, the five that have a short form, and everything else below U+0020
/// as lowercase `\u00xx`. Nothing above U+001F is escaped, which is what keeps
/// the output UTF-8 rather than ASCII.
fn quote(out : StringBuilder, s : StringView) -> Unit {
  out.write_char('"')
  let mut run = 0
  for i in 0..<s.length() {
    let c = s.at(i).to_int()
    let escape = match c {
      0x22 => "\\\""
      0x5C => "\\\\"
      0x08 => "\\b"
      0x0C => "\\f"
      0x0A => "\\n"
      0x0D => "\\r"
      0x09 => "\\t"
      _ => if c < 0x20 { hex_escape(c) } else { "" }
    }
    if escape != "" {
      out.write_view(s[run:i])
      out.write_string(escape)
      run = i + 1
    }
  }
  out.write_view(s[run:])
  out.write_char('"')
}

///|
fn hex_escape(c : Int32) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  out.write_string("\\u")
  for shift in [12, 8, 4, 0] {
    out.write_char(digits.get_char((c >> shift) & 0xF).unwrap())
  }
  out.to_string()
}

///|
/// A number as ECMAScript's `Number::toString` writes it (RFC 8785 §3.2.2.3).
///
/// MoonBit's formatter already produces the shortest text that reads back as
/// the same double, so the digits are taken from it and only the shape is
/// redone: ES6 puts the decimal point somewhere else than MoonBit does at some
/// magnitudes, and the RFC wants ES6's shape, not ours.
fn number(out : StringBuilder, n : Double) -> Unit raise @moonjson.Refused {
  if n.is_nan() || n.is_inf() {
    raise @moonjson.Unwritable(
      why="a number that is not finite has no canonical form",
    )
  }
  let text = n.to_string()
  // `-0` is written `0`: the RFC follows ECMAScript, where the sign of zero is
  // not part of the value's text.
  if n == 0.0 {
    out.write_char('0')
    return
  }
  let mut i = 0
  if text.at(0).to_int() == 0x2D {
    out.write_char('-')
    i = 1
  }
  let start = i
  let mut exponent = 0
  let mut point = -1
  while i < text.length() {
    let c = text.at(i)
    if c == 'e' || c == 'E' {
      exponent = @string.parse_int(text[i + 1:].to_owned()) catch { _ => 0 }
      break
    }
    if c == '.' {
      point = i - start
    }
    i += 1
  }
  let mantissa = text[start:i]
  let digits = StringBuilder()
  for k in 0..<mantissa.length() {
    let c = mantissa.at(k)
    if c != '.' {
      digits.write_char(c.unsafe_to_char())
    }
  }
  // `n` is where the decimal point falls in the digit string: the value is
  // digits × 10^(n − length).
  let fraction = if point < 0 { 0 } else { mantissa.length() - point - 1 }
  let mut places = digits.to_string()
  let mut n = places.length() + exponent - fraction
  // Leading zeros carry no information; dropping them moves the point left by
  // the same amount.
  let mut lead = 0
  while lead < places.length() - 1 && places.at(lead) == '0' {
    lead += 1
  }
  if lead > 0 {
    places = places[lead:].to_owned()
    n -= lead
  }
  let k = places.length()
  if k <= n && n <= 21 {
    out.write_string(places)
    for _ in 0..<(n - k) {
      out.write_char('0')
    }
  } else if 0 < n && n <= 21 {
    out.write_view(places[:n])
    out.write_char('.')
    out.write_view(places[n:])
  } else if -6 < n && n <= 0 {
    out.write_string("0.")
    for _ in 0..<-n {
      out.write_char('0')
    }
    out.write_string(places)
  } else {
    out.write_view(places[:1])
    if k > 1 {
      out.write_char('.')
      out.write_view(places[1:])
    }
    out.write_char('e')
    let power = n - 1
    if power >= 0 {
      out.write_char('+')
    }
    out.write_string(power.to_string())
  }
}
