// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A head byte and its argument, in the shortest form that holds the argument
/// (RFC 8949 §3). Every writer produces this form because it is what a reader
/// in the deterministic mode also produces; writing a length in eight bytes
/// would be valid CBOR and useless.
fn head(buf : Buffer, major : Int32, arg : UInt64) -> Unit {
  if arg < 24UL {
    buf.write_byte((major * 32 + arg.to_int()).to_byte())
  } else if arg <= 0xFFUL {
    buf.write_byte((major * 32 + 24).to_byte())
    buf.write_byte(arg.to_byte())
  } else if arg <= 0xFFFFUL {
    buf.write_byte((major * 32 + 25).to_byte())
    buf.write_uint16_be(arg.to_uint16())
  } else if arg <= 0xFFFF_FFFFUL {
    buf.write_byte((major * 32 + 26).to_byte())
    buf.write_uint_be(arg.to_uint())
  } else {
    buf.write_byte((major * 32 + 27).to_byte())
    buf.write_uint64_be(arg)
  }
}

///|
fn write(
  buf : Buffer,
  value : Json,
  policy : Policy,
) -> Unit raise @moonjson.Refused {
  match value {
    Null => buf.write_byte(0xF6)
    True => buf.write_byte(0xF5)
    False => buf.write_byte(0xF4)
    Number(n, repr~) => number(buf, n, repr, policy)
    String(s) => text(buf, s[:])
    Array(items) => {
      head(buf, 4, items.length().to_uint64())
      for item in items {
        write(buf, item, policy)
      }
    }
    Object(members) => object(buf, members, policy)
  }
}

///|
fn text(buf : Buffer, s : StringView) -> Unit {
  let bytes = @utf8.encode(s)
  head(buf, 3, bytes.length().to_uint64())
  buf.write_bytes(bytes[:])
}

///|
/// An object is either one of the markers `load` documents, or a map whose keys
/// are strings.
fn object(
  buf : Buffer,
  members : Map[String, Json],
  policy : Policy,
) -> Unit raise @moonjson.Refused {
  if members.length() == 1 {
    match members.get("$bytes") {
      Some(String(hex)) => {
        let bytes = @hex.decode(hex[:]) catch {
          _ => raise @moonjson.Unwritable(why="\"$bytes\" wants lowercase hex")
        }
        head(buf, 2, bytes.length().to_uint64())
        buf.write_bytes(bytes[:])
        return
      }
      _ => ()
    }
    match members.get("$undefined") {
      Some(True) => {
        buf.write_byte(0xF7)
        return
      }
      _ => ()
    }
    if members.get("$simple") is Some(Number(n, ..)) &&
      n == @double.trunc(n) &&
      n >= 0.0 &&
      n <= 255.0 {
      let simple = n.to_int()
      if simple < 24 {
        buf.write_byte((0xE0 + simple).to_byte())
      } else {
        buf.write_byte(0xF8)
        buf.write_byte(simple.to_byte())
      }
      return
    }
    if members.get("$map") is Some(Array(pairs)) {
      head(buf, 5, pairs.length().to_uint64())
      for pair in pairs {
        match pair {
          Array(entry) if entry.length() == 2 => {
            write(buf, entry[0], policy)
            write(buf, entry[1], policy)
          }
          _ =>
            raise @moonjson.Unwritable(
              why="\"$map\" is an array of [key, value] pairs",
            )
        }
      }
      return
    }
  }
  if members.length() == 2 {
    if members.get("$tag") is Some(Number(tag, ..)) &&
      members.get("value") is Some(held) &&
      tag == @double.trunc(tag) &&
      tag >= 0.0 {
      head(buf, 6, tag.to_uint64())
      write(buf, held, policy)
      return
    }
  }
  head(buf, 5, members.length().to_uint64())
  let names : Array[String] = []
  for name, _ in members {
    names.push(name)
  }
  if policy.deterministic {
    names.sort_by(fn(a, b) { compare_bytes(key_bytes(a), key_bytes(b)) })
  }
  for name in names {
    text(buf, name[:])
    write(buf, members.get(name).unwrap(), policy)
  }
}

///|
/// A key as it is written, which is what the deterministic order sorts.
fn key_bytes(name : String) -> Bytes {
  let buf = Buffer()
  text(buf, name[:])
  buf.to_bytes()
}

///|
/// Bytewise lexicographic order (RFC 8949 §4.2.3), unsigned.
fn compare_bytes(a : Bytes, b : Bytes) -> Int32 {
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
/// A number: an integer when the tree says it is one, a float when it says it is
/// one, and a bignum when the digits do not fit in 64 bits.
///
/// The tree keeps `repr`, the text the number was written as, and that text is
/// what decides: `1.0` is a float and `1` is an integer, though both hold the
/// same value. Without that, a CBOR document read and written again would come
/// back as different bytes, because CBOR is the one JSON-family format where a
/// float and an integer of the same value are different things.
fn number(buf : Buffer, n : Double, repr : String?, policy : Policy) -> Unit {
  match repr {
    Some(text) =>
      if is_integer_text(text) {
        if text.at(0).to_int() == 0x2D {
          // A negative integer stores one less than its magnitude, so the
          // argument is the decremented text: -2^64 is the smallest one that
          // fits in eight bytes, and its argument is 2^64 - 1.
          match integer_text(decrement(text[1:].to_owned())) {
            Some(argument) => head(buf, 1, argument)
            None => bignum(buf, text)
          }
        } else {
          match integer_text(text) {
            Some(magnitude) => head(buf, 0, magnitude)
            None => bignum(buf, text)
          }
        }
      } else {
        float(buf, n, policy)
      }
    None =>
      if !n.is_nan() && !n.is_inf() && n == @double.trunc(n) {
        if n >= 0.0 && n < 9223372036854775808.0 {
          head(buf, 0, n.to_uint64())
        } else if n < 0.0 && n >= -9223372036854775808.0 {
          head(buf, 1, (-1.0 - n).to_uint64())
        } else {
          float(buf, n, policy)
        }
      } else {
        float(buf, n, policy)
      }
  }
}

///|
/// The magnitude of an integer written as digits, when it fits in 64 bits.
fn integer_text(text : String) -> UInt64? {
  let mut i = 0
  let mut value = 0UL
  while i < text.length() {
    let digit = (text.at(i).to_int() - 0x30).to_uint64()
    if value > (0xFFFF_FFFF_FFFF_FFFFUL - digit) / 10UL {
      return None
    }
    value = value * 10UL + digit
    i += 1
  }
  Some(value)
}

///|
fn bignum(buf : Buffer, text : String) -> Unit {
  if text.at(0).to_int() == 0x2D {
    head(buf, 6, 3UL)
    let bytes = decimal_bytes(decrement(text[1:].to_owned())[:])
    head(buf, 2, bytes.length().to_uint64())
    buf.write_bytes(bytes[:])
  } else {
    head(buf, 6, 2UL)
    let bytes = decimal_bytes(text[:])
    head(buf, 2, bytes.length().to_uint64())
    buf.write_bytes(bytes[:])
  }
}

///|
fn float(buf : Buffer, n : Double, policy : Policy) -> Unit {
  let bits = n.reinterpret_as_uint64()
  if n.is_nan() {
    if policy.deterministic {
      buf.write_byte(0xF9)
      buf.write_uint16_be(0x7E00)
    } else {
      buf.write_byte(0xFB)
      buf.write_uint64_be(bits)
    }
    return
  }
  if policy.deterministic {
    let half = double_to_half(n)
    if half_to_double(half).reinterpret_as_uint64() == bits {
      buf.write_byte(0xF9)
      buf.write_uint16_be(half.to_uint16())
      return
    }
    let single = double_to_single(n)
    if single_to_double(single).reinterpret_as_uint64() == bits {
      buf.write_byte(0xFA)
      buf.write_uint_be(single)
      return
    }
  }
  buf.write_byte(0xFB)
  buf.write_uint64_be(bits)
}

///|
fn is_integer_text(text : String) -> Bool {
  if text.length() == 0 {
    return false
  }
  for i in 0..<text.length() {
    let c = text.at(i).to_int()
    if i == 0 && c == 0x2D && text.length() > 1 {
      continue
    }
    if c < 0x30 || c > 0x39 {
      return false
    }
  }
  true
}

///|
/// One less than a decimal, for the negative half of the bignum tag.
fn decrement(text : String) -> String {
  let mut i = text.length() - 1
  while i >= 0 && text.at(i).to_int() == 0x30 {
    i -= 1
  }
  let out = StringBuilder()
  out.write_view(text[:i])
  out.write_char((text.at(i).to_int() - 1).unsafe_to_char())
  for _ in 0..<(text.length() - i - 1) {
    out.write_char('9')
  }
  out.to_string()
}
