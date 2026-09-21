// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Write a tree as strict JSON, whatever dialect it was read from.
///
/// `indent` of zero, the default, writes the compact form with no space
/// anywhere; anything larger writes one line per member with that many spaces a
/// level, and a space after each colon.
///
/// A number that came in as text goes back out as that text, so a document read
/// and written again is unchanged. Only a number with no such text is formatted,
/// and a number that is not finite — which JSON5 can produce and JSON cannot
/// write — becomes `null`, as every JavaScript implementation does.
pub fn write(
  value : Json,
  indent? : Int = 0,
  ascii? : Bool = false,
  sort? : Bool = false,
) -> String {
  let out = StringBuilder()
  put(out, value, indent, 0, ascii, sort)
  out.to_string()
}

///|
/// The same, as UTF-8 bytes — the form a body goes onto a wire in.
pub fn write_bytes(
  value : Json,
  indent? : Int = 0,
  ascii? : Bool = false,
  sort? : Bool = false,
) -> Bytes {
  @utf8.encode(write(value, indent~, ascii~, sort~)[:])
}

///|
fn put(
  out : StringBuilder,
  value : Json,
  indent : Int,
  level : Int,
  ascii : Bool,
  sort : Bool,
) -> Unit {
  match value {
    Null => out.write_string("null")
    True => out.write_string("true")
    False => out.write_string("false")
    Number(n, repr~) =>
      match repr {
        Some(text) => out.write_string(text)
        None =>
          if n.is_nan() || n.is_inf() {
            out.write_string("null")
          } else {
            out.write_string(n.to_string())
          }
      }
    String(s) => quote(out, s[:], ascii)
    Array(items) => {
      if items.length() == 0 {
        out.write_string("[]")
        return
      }
      out.write_char('[')
      for k, item in items {
        if k > 0 {
          out.write_char(',')
        }
        newline(out, indent, level + 1)
        put(out, item, indent, level + 1, ascii, sort)
      }
      newline(out, indent, level)
      out.write_char(']')
    }
    Object(members) => {
      if members.length() == 0 {
        out.write_string("{}")
        return
      }
      out.write_char('{')
      let names : Array[String] = []
      for name, _ in members {
        names.push(name)
      }
      if sort {
        names.sort()
      }
      let mut first = true
      for name in names {
        if !first {
          out.write_char(',')
        }
        first = false
        newline(out, indent, level + 1)
        quote(out, name[:], ascii)
        out.write_char(':')
        if indent > 0 {
          out.write_char(' ')
        }
        put(out, members.get(name).unwrap(), indent, level + 1, ascii, sort)
      }
      newline(out, indent, level)
      out.write_char('}')
    }
  }
}

///|
fn newline(out : StringBuilder, indent : Int, level : Int) -> Unit {
  if indent > 0 {
    out.write_char('\n')
    for _ in 0..<(indent * level) {
      out.write_char(' ')
    }
  }
}

///|
/// A string as RFC 8259 §7 writes one.
///
/// Only what must be escaped is: the quote, the backslash, and the control
/// characters. The two-character forms are used where they exist because they
/// are shorter and what a reader expects to see; everything else below U+0020
/// goes out as `\u00XX`.
fn quote(out : StringBuilder, s : StringView, ascii : Bool) -> Unit {
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
      _ => if c < 0x20 || (ascii && c > 0x7E) { hex_escape(c) } else { "" }
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
fn hex_escape(c : Int) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  out.write_string("\\u")
  for shift in [12, 8, 4, 0] {
    out.write_char(digits.get_char((c >> shift) & 0xF).unwrap())
  }
  out.to_string()
}
