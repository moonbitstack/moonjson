// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How much a nested level is indented.
///
/// Two spaces: what Kubernetes manifests, Compose files and every configuration
/// example in the wild use, and what a reader's eye is trained on.
pub let indent : Int = 2

///|
/// Whether a string can be written without quotes.
///
/// It cannot if it is empty, if it would read back as something other than a
/// string, if it begins with a character YAML gives a meaning to, if it carries
/// a `: ` or a ` #` that would be read as structure or a comment, or if it has
/// space at either end where the reader would trim it.
fn plain(s : String) -> Bool {
  if s.length() == 0 {
    return false
  }
  if s == "true" || s == "false" || s == "null" || s == "~" {
    return false
  }
  if number(s) is Some(_) {
    return false
  }
  if is_space(s[0].to_int()) || is_space(s[s.length() - 1].to_int()) {
    return false
  }
  // The characters YAML reserves at the start of a scalar.
  for c in "-?:,[]{}#&*!|>'\"%@`" {
    if s[0].to_int() == c.to_int() {
      return false
    }
  }
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if c < 0x20 || c == 0x7f {
      return false
    }
    if c == ':'.to_int() && (i + 1 == s.length() || is_space(s[i + 1].to_int())) {
      return false
    }
    if c == '#'.to_int() && i > 0 && is_space(s[i - 1].to_int()) {
      return false
    }
  }
  true
}

///|
/// A string in double quotes, with the escapes YAML defines.
fn quoted(out : StringBuilder, s : String) -> Unit {
  out.write_char('"')
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    match c {
      0x22 => out.write_string("\\\"")
      0x5c => out.write_string("\\\\")
      0x0a => out.write_string("\\n")
      0x0d => out.write_string("\\r")
      0x09 => out.write_string("\\t")
      _ =>
        if c < 0x20 || c == 0x7f {
          out.write_string("\\x")
          hex(out, c)
        } else {
          out.write_char(s[i].unsafe_to_char())
        }
    }
  }
  out.write_char('"')
}

///|
/// A byte as two hex digits.
fn hex(out : StringBuilder, c : Int) -> Unit {
  let digits = "0123456789abcdef"
  out.write_char(digits[(c >> 4) & 0xf].unsafe_to_char())
  out.write_char(digits[c & 0xf].unsafe_to_char())
}

///|
/// A number as YAML writes it: a whole value without a fractional part, so a
/// port is `8080` rather than `8080.0`.
fn write_number(out : StringBuilder, n : Double) -> Unit {
  if n == n.floor() && n.abs() < 1.0e15 {
    out.write_string(n.to_int64().to_string())
  } else {
    out.write_string(n.to_string())
  }
}

///|
/// A scalar, quoted only when plain would read back as something else.
fn write_scalar(out : StringBuilder, value : Json) -> Unit {
  match value {
    Null => out.write_string("null")
    True => out.write_string("true")
    False => out.write_string("false")
    Number(n, ..) => write_number(out, n)
    String(s) => if plain(s) { out.write_string(s) } else { quoted(out, s) }
    _ => out.write_string("null")
  }
}

///|
/// Whether a value is written on the same line as the key or item that owns it.
fn inline(value : Json) -> Bool {
  match value {
    Array(items) => items.length() == 0
    Object(members) => members.length() == 0
    _ => true
  }
}

///|
/// A value that fits on one line: a scalar, or the flow form of an empty
/// collection — which is the only way block style can express one.
fn write_inline(out : StringBuilder, value : Json) -> Unit {
  match value {
    Array(_) => out.write_string("[]")
    Object(_) => out.write_string("{}")
    _ => write_scalar(out, value)
  }
}

///|
fn pad(out : StringBuilder, n : Int) -> Unit {
  for _ in 0..<n {
    out.write_char(' ')
  }
}

///|
/// A block at `column`, which is the number of spaces its own lines begin with.
fn block(
  out : StringBuilder,
  value : Json,
  column : Int,
  step : Int,
  sort : Bool,
) -> Unit {
  match value {
    Object(members) => {
      let names = members.keys().collect()
      if sort {
        names.sort()
      }
      let mut first = true
      for name in names {
        let held = members.get(name).unwrap()
        if !first || column > 0 {
          if !first {
            out.write_char('\n')
          }
        }
        if !first {
          pad(out, column)
        }
        first = false
        if plain(name) {
          out.write_string(name)
        } else {
          quoted(out, name)
        }
        out.write_char(':')
        if inline(held) {
          out.write_char(' ')
          write_inline(out, held)
        } else {
          out.write_char('\n')
          pad(out, column + step)
          block(out, held, column + step, step, sort)
        }
      }
    }
    Array(items) => {
      let mut first = true
      for item in items {
        if !first {
          out.write_char('\n')
          pad(out, column)
        }
        first = false
        out.write_string("- ")
        if inline(item) {
          write_inline(out, item)
        } else {
          // A nested block under a `-` begins on the same line, indented to
          // just past the dash, which is how every hand-written file does it.
          block(out, item, column + 2, step, sort)
        }
      }
    }
    _ => write_scalar(out, value)
  }
}

///|
/// Write a `Json` tree as a YAML document.
///
/// Block style, which is what a configuration file is written in and what a
/// person reads. A string is quoted only when plain would read back as
/// something else — a number, a boolean, a null, or not at all — so the output
/// looks like a file someone wrote rather than one a program emitted.
///
/// This is the reason to have a writer at all: a generator that builds YAML by
/// joining strings gets the escaping wrong the first time a value contains a
/// colon, and gets the indentation wrong the first time a value is a list.
pub fn dumps(
  value : Json,
  indent? : Int = indent,
  sort? : Bool = false,
) -> String {
  guard indent >= 1 else {
    abort("yaml: an indent of \{indent} would not nest anything")
  }
  let out = StringBuilder()
  match value {
    Object(members) =>
      if members.length() == 0 {
        out.write_string("{}")
      } else {
        block(out, value, 0, indent, sort)
      }
    Array(items) =>
      if items.length() == 0 {
        out.write_string("[]")
      } else {
        block(out, value, 0, indent, sort)
      }
    _ => write_scalar(out, value)
  }
  out.write_char('\n')
  out.to_string()
}

///|
/// The same, as UTF-8 bytes — the `s` on [`dumps`] is the one Python puts on
/// the form that answers a string.
pub fn dump(
  value : Json,
  indent? : Int = indent,
  sort? : Bool = false,
) -> Bytes {
  @utf8.encode(dumps(value, indent~, sort~)[:])
}

///|
/// A stream of documents, each opened by its own `---`.
///
/// The separator goes before each document rather than between them, which is
/// what `kubectl` emits and what makes appending one more a matter of adding
/// lines at the end.
pub fn dumps_all(
  values : ArrayView[Json],
  indent? : Int = indent,
  sort? : Bool = false,
) -> String {
  let out = StringBuilder()
  for value in values {
    out.write_string("---\n")
    out.write_string(dumps(value, indent~, sort~))
  }
  out.to_string()
}

///|
/// The same, as UTF-8 bytes.
pub fn dump_all(
  values : ArrayView[Json],
  indent? : Int = indent,
  sort? : Bool = false,
) -> Bytes {
  @utf8.encode(dumps_all(values, indent~, sort~)[:])
}
