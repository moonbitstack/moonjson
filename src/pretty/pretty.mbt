// Pretty-printing JSON — configurable indentation, line endings, and a
// text-to-text entry point:
// https://docs.python.org/3/library/json.html#json.dumps  (indent, sort_keys)
// https://docs.rs/serde_json/latest/serde_json/ser/struct.PrettyFormatter.html
//
// The core writer already writes an indented form; this package adds the knobs
// a formatter wants — tabs instead of spaces, CRLF line endings — and the
// text-to-text entry point a command-line tool needs, which is what
// `python -m json.tool` does: read a document, write it back in the chosen
// shape. It is a package of its own because the core's `dumps` signature is
// depended on everywhere and must stay stable, and because a build that never
// imports this one never compiles it.
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How to lay a document out.
///
/// The defaults are the ones a formatter is usually asked for — two spaces a
/// level, LF line endings — and every field can be changed independently.
pub(all) struct Format {
  /// Spaces per level. Zero writes the whole document on one line.
  indent : Int32
  /// One tab per level instead of spaces; `indent` is then ignored.
  tabs : Bool
  /// A carriage return before each line feed, for a file Windows reads.
  crlf : Bool
  /// Sort members by name, code point by code point.
  sort : Bool
  /// Escape everything above U+007F so the output is plain ASCII.
  ascii : Bool
} derive(Eq, Debug)

///|
pub extend Format with Eq::{equal, not_equal}

///|
pub extend Format with Debug::{to_repr}

///|
/// The default: two spaces a level, LF line endings, the order the tree keeps.
pub let pretty : Format = {
  indent: 2,
  tabs: false,
  crlf: false,
  sort: false,
  ascii: false,
}

///|
/// Build a format by naming the parts that differ from the default.
pub fn Format::new(
  indent~ : Int32 = pretty.indent,
  tabs~ : Bool = pretty.tabs,
  crlf~ : Bool = pretty.crlf,
  sort~ : Bool = pretty.sort,
  ascii~ : Bool = pretty.ascii,
) -> Format {
  { indent, tabs, crlf, sort, ascii, }
}

///|
/// Write a tree in the chosen shape.
///
/// The core writer does the work; this only bends its output where the core's
/// signature cannot — a tab for each level, a carriage return before each line
/// feed. A JSON string never contains a raw line feed (it is escaped), so
/// rewriting line endings cannot touch a value.
pub fn format(value : Json, style~ : Format = pretty) -> String {
  if style.indent == 0 && !style.tabs {
    return @moonjson.dumps(value, sort=style.sort, ascii=style.ascii)
  }
  let width : Int32 = if style.tabs { 1 } else { style.indent }
  let base = @moonjson.dumps(
    value,
    indent=width,
    sort=style.sort,
    ascii=style.ascii,
  )
  let mut text = base
  if style.tabs {
    text = leading_spaces_to_tabs(text, width)
  }
  if style.crlf {
    text = lf_to_crlf(text)
  }
  text
}

///|
/// Read a document and write it back in the chosen shape — the text-to-text
/// entry point, what `python -m json.tool` does.
pub fn reformat(
  text : StringView,
  style~ : Format = pretty,
) -> String raise @moonjson.Refused {
  format(@json.loads(text), style~)
}

///|
/// The same, from the UTF-8 bytes of a document.
pub fn reformat_bytes(
  input : BytesView,
  style~ : Format = pretty,
) -> Bytes raise @moonjson.Refused {
  let text = @utf8.decode(input, ignore_bom=true) catch {
    _ => raise @moonjson.BadUtf8({ at: 0, line: 1, column: 1, })
  }
  @utf8.encode(reformat(text[:], style~)[:])
}

///|
/// Replace the run of spaces that starts each line with the same number of
/// levels written as tabs. Only the leading run is touched, so the spaces
/// inside a string are left alone.
fn leading_spaces_to_tabs(text : String, width : Int32) -> String {
  let view = text[:]
  let out = StringBuilder()
  let n = view.length()
  let mut i : Int32 = 0
  let mut at_line_start = true
  while i < n {
    let cp = view.at(i).to_int()
    if at_line_start && cp == 0x20 {
      let mut j = i
      while j < n && view.at(j).to_int() == 0x20 {
        j += 1
      }
      let count = j - i
      let tabs = count / width
      let mut k : Int32 = 0
      while k < tabs {
        out.write_char('\t')
        k += 1
      }
      let mut rest : Int32 = 0
      while rest < count % width {
        out.write_char(' ')
        rest += 1
      }
      i = j
      at_line_start = false
    } else {
      out.write_char(cp.unsafe_to_char())
      at_line_start = cp == 0x0A
      i += 1
    }
  }
  out.to_string()
}

///|
/// Put a carriage return before every line feed.
fn lf_to_crlf(text : String) -> String {
  let view = text[:]
  let out = StringBuilder()
  let n = view.length()
  let mut i : Int32 = 0
  while i < n {
    let cp = view.at(i).to_int()
    if cp == 0x0A {
      out.write_char('\r')
    }
    out.write_char(cp.unsafe_to_char())
    i += 1
  }
  out.to_string()
}
