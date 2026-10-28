// CSON — CoffeeScript Object Notation: https://github.com/bevry/cson
//
// The reader does real parsing: it folds the document into structural lines
// (respecting `'''`/`"""` block strings and `###` block comments, whose newlines
// are not structural), then descends recursively by indentation. The writer
// emits strict JSON by delegating to `@moonjson`.

///|
/// One structural line after comments and block strings have been folded away.
priv struct Line {
  /// The number of leading spaces on the line as it appeared in the source.
  indent : Int32
  /// The text after those spaces, with any `- ` bullet or `key:` prefix intact.
  content : StringView
  /// The one-based physical line the line began on, kept for error positions.
  line_no : Int32
}

///|
/// A CSON document in mid-parse.
priv struct CsonParser {
  lines : Array[Line]
  flavor : @moonjson.Flavor
}

///|
/// Read one CSON document.
///
/// The root is an object whose members sit at the first indentation level (or an
/// array, if the first line is a `- ` bullet). CSON is indentation-based, so the
/// document is first reduced to structural lines and then walked recursively;
/// what comes back is the same `Json` tree every dialect in this family reads
/// into.
pub fn loads(
  text : StringView,
  flavor~ : @moonjson.Flavor = @moonjson.relaxed,
) -> Json raise @moonjson.Refused {
  if starts_with_brace(text) {
    return @moonjson.loads(text, @moonjson.strict)
  }
  let lines = to_lines(text.to_owned())
  let parser : CsonParser = { lines, flavor, }
  if lines.length() == 0 {
    return Json::object(Map::from_array([]))
  }
  let (value, _) = parser.parse_block(0, -1)
  value
}

///|
/// Whether the document opens with `{` or `[`, which no CSON document does — a
/// CSON document is bare `key: value` lines. Such a document is JSON, so it is
/// read as JSON, which is what makes `dumps` (which writes strict JSON) read
/// back here.
fn starts_with_brace(text : StringView) -> Bool {
  let mut i : Int32 = 0
  while i < text.length() {
    let c = text.at(i).to_int()
    if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
      i += 1
    } else {
      return c == 0x7B || c == 0x5B
    }
  }
  false
}

///|
/// Read one CSON document from the UTF-8 bytes a body arrives as.
///
/// A leading byte-order mark is skipped by default. If the bytes are not valid
/// UTF-8 the document is refused rather than silently mangled.
pub fn load(
  input : BytesView,
  flavor~ : @moonjson.Flavor = @moonjson.relaxed,
  bom~ : Bool = true,
) -> Json raise @moonjson.Refused {
  let text = @utf8.decode(input, ignore_bom=bom) catch {
    _ => raise @moonjson.BadUtf8(@moonjson.At::{ at: 0, line: 1, column: 1, })
  }
  loads(text, flavor~)
}

///|
/// Write a tree as strict JSON.
///
/// CSON has no canonical text form — nothing the writer could print would be
/// CSON a reader recognises as the same document — so this delegates to
/// `@moonjson.dumps`, which already knows how to emit strict JSON for any `Json`.
pub fn dumps(
  value : Json,
  indent~ : Int32 = 0,
  ascii~ : Bool = false,
  sort~ : Bool = false,
) -> String {
  @moonjson.dumps(value, indent~, ascii~, sort~)
}

///|
/// The same, as the UTF-8 bytes a body goes out as.
///
/// Like `dumps`, the text produced is strict JSON written by `@moonjson`; CSON
/// itself has no faithful textual rendering.
pub fn dump(
  value : Json,
  indent~ : Int32 = 0,
  ascii~ : Bool = false,
  sort~ : Bool = false,
) -> Bytes {
  @moonjson.dump(value, indent~, ascii~, sort~)
}

// ---------------------------------------------------------------------------
// Folding the source into structural lines
// ---------------------------------------------------------------------------

///|
fn to_lines(text : String) -> Array[Line] raise @moonjson.Refused {
  let phys0 = split_newline(text)
  let phys : Array[StringView] = []
  for p in phys0 {
    phys.push(strip_cr(p))
  }
  let out : Array[Line] = []
  let n = phys.length()
  let mut i = 0
  while i < n {
    let (line, next) = scan_one(phys, i)
    match line {
      Some(l) => out.push(l)
      None => ()
    }
    i = next
  }
  split_array_elements(out)
}

///|
fn scan_one(
  phys : Array[StringView],
  i : Int32,
) -> (Line?, Int32) raise @moonjson.Refused {
  let n = phys.length()
  let first_line = phys[i]
  let indent = count_spaces(first_line)
  let rest = first_line[indent:]
  let (prefix, quote, bco) = scan_rest(rest)
  let content = StringBuilder()
  content.write_string(prefix)
  let mut idx = i + 1
  if quote != 0 {
    // A `'''`/`"""` block string opened on this line; gather its body across
    // following lines until the closing triple, keeping it inside `content`.
    let op_start = prefix.length()
    let opener = rest[op_start:op_start + 3]
    content.write_view(opener)
    let remainder = rest[op_start + 3:]
    let mut closed = false
    match remainder.find(opener) {
      Some(k) => {
        content.write_view(remainder[0:k])
        content.write_view(opener)
        closed = true
        idx = i + 1
      }
      None => {
        content.write_view(remainder)
        content.write_char(Int32::unsafe_to_char(0x0A))
        idx = i + 1
        while idx < n && !closed {
          let piece = phys[idx]
          match piece.find(opener) {
            Some(k2) => {
              content.write_view(piece[0:k2])
              content.write_view(opener)
              closed = true
              idx = idx + 1
            }
            None => {
              content.write_view(piece)
              content.write_char(Int32::unsafe_to_char(0x0A))
              idx = idx + 1
            }
          }
        }
      }
    }
    if !closed {
      raise @moonjson.Truncated(@moonjson.At::{ at: 0, line: 1, column: 1, })
    }
  } else if bco {
    // A `### ... ###` block comment opened; skip text until the closer.
    let piece = rest[prefix.length() + 3:]
    let mut closed = false
    match piece.find("###") {
      Some(k) => {
        let after = piece[k + 3:]
        let (mp, _, _) = scan_rest(after)
        content.write_string(mp)
        closed = true
        idx = i + 1
      }
      None => {
        idx = i + 1
        while idx < n && !closed {
          let pc = phys[idx]
          match pc.find("###") {
            Some(k2) => {
              let after = pc[k2 + 3:]
              let (mp, _, _) = scan_rest(after)
              content.write_string(mp)
              closed = true
              idx = idx + 1
            }
            None => idx = idx + 1
          }
        }
      }
    }
  } else {
    ()
  }
  let text = content.to_string()
  if text.length() == 0 {
    (None, idx)
  } else {
    (Some(Line::{ indent, content: text, line_no: i + 1, }), idx)
  }
}

///|
/// Walk `rest`, copying it verbatim into `prefix` until a block-string opener or
/// a `#`/`###` comment is met. Strings are tracked so a `#` inside quotes is not
/// mistaken for a comment. Returns `(prefix, block_quote, block_comment_open)`.
fn scan_rest(rest : StringView) -> (String, Int32, Bool) {
  let n = rest.length()
  let sb = StringBuilder()
  let mut j = 0
  let mut in_str = 0
  while j < n {
    let c = rest.at(j).to_int()
    if in_str != 0 {
      sb.write_char(Int32::unsafe_to_char(c))
      if c == 0x5C {
        j = j + 1
        if j < n {
          sb.write_char(Int32::unsafe_to_char(rest.at(j).to_int()))
          j = j + 1
        }
        continue
      }
      if c == in_str {
        in_str = 0
      }
      j = j + 1
      continue
    }
    if c == 0x22 || c == 0x27 {
      if c == 0x27 &&
        j + 2 < n &&
        rest.at(j + 1).to_int() == 0x27 &&
        rest.at(j + 2).to_int() == 0x27 {
        return (sb.to_string(), 0x27, false)
      }
      if c == 0x22 &&
        j + 2 < n &&
        rest.at(j + 1).to_int() == 0x22 &&
        rest.at(j + 2).to_int() == 0x22 {
        return (sb.to_string(), 0x22, false)
      }
      in_str = c
      sb.write_char(Int32::unsafe_to_char(c))
      j = j + 1
      continue
    }
    if c == 0x23 {
      if j + 2 < n &&
        rest.at(j + 1).to_int() == 0x23 &&
        rest.at(j + 2).to_int() == 0x23 {
        return (sb.to_string(), 0, true)
      }
      return (sb.to_string(), 0, false)
    }
    sb.write_char(Int32::unsafe_to_char(c))
    j = j + 1
  }
  (sb.to_string(), 0, false)
}

///|
/// CSON array bullets can themselves open an object (`- key: value`). Split such
/// a bullet into a bare `- ` marker followed by the member line so the recursive
/// descent treats it uniformly; every other `- ` line is left intact.
fn split_array_elements(lines : Array[Line]) -> Array[Line] {
  let out : Array[Line] = []
  for line in lines {
    if begins_with(line.content, "- ") {
      let raw = line.content[2:]
      let is_block = begins_with(raw, "'''") || begins_with(raw, "\"\"\"")
      if !is_block && has_top_level_colon(raw) {
        out.push(Line::{
          indent: line.indent,
          content: "- ",
          line_no: line.line_no,
        })
        out.push(Line::{
          indent: line.indent + 2,
          content: raw,
          line_no: line.line_no,
        })
      } else {
        out.push(line)
      }
    } else {
      out.push(line)
    }
  }
  out
}

// ---------------------------------------------------------------------------
// Recursive descent over the structural lines
// ---------------------------------------------------------------------------

///|
fn CsonParser::parse_block(
  self : CsonParser,
  idx : Int32,
  parent_indent : Int32,
) -> (Json, Int32) raise @moonjson.Refused {
  if idx >= self.lines.length() {
    return (Json::object(Map::from_array([])), idx)
  }
  let content = self.lines[idx].content
  if begins_with(content, "- ") {
    self.parse_array(idx, parent_indent)
  } else {
    self.parse_object(idx, parent_indent)
  }
}

///|
fn CsonParser::parse_object(
  self : CsonParser,
  idx : Int32,
  parent_indent : Int32,
) -> (Json, Int32) raise @moonjson.Refused {
  let members : Map[String, Json] = Map([], capacity=0)
  let mut i = idx
  while i < self.lines.length() {
    let line = self.lines[i]
    if line.indent <= parent_indent {
      break
    }
    let (key, raw_value) = parse_member_line(line.content)
    if raw_value.length() == 0 {
      if i + 1 < self.lines.length() && self.lines[i + 1].indent > line.indent {
        let (val, ni) = self.parse_block(i + 1, line.indent)
        members[key] = val
        i = ni
      } else {
        members[key] = Json::object(Map::from_array([]))
        i = i + 1
      }
    } else {
      let val = self.parse_inline_value(raw_value)
      members[key] = val
      i = i + 1
    }
  }
  (Json::object(members), i)
}

///|
fn CsonParser::parse_array(
  self : CsonParser,
  idx : Int32,
  parent_indent : Int32,
) -> (Json, Int32) raise @moonjson.Refused {
  let items : Array[Json] = []
  let mut i = idx
  while i < self.lines.length() {
    let line = self.lines[i]
    if line.indent <= parent_indent {
      break
    }
    let content = line.content
    if !begins_with(content, "- ") {
      raise @moonjson.Unexpected(
        @moonjson.At::{ at: 0, line: 1, column: 1, },
        Int32::unsafe_to_char(0x2D),
      )
    }
    let raw = content[2:]
    if raw.length() == 0 {
      if i + 1 < self.lines.length() && self.lines[i + 1].indent > line.indent {
        let (val, ni) = self.parse_block(i + 1, line.indent)
        items.push(val)
        i = ni
      } else {
        items.push(Json::object(Map::from_array([])))
        i = i + 1
      }
    } else {
      let val = self.parse_inline_value(raw)
      items.push(val)
      i = i + 1
    }
  }
  (Json::array(items), i)
}

///|
fn parse_member_line(
  content : StringView,
) -> (String, String) raise @moonjson.Refused {
  let n = content.length()
  let key_sb = StringBuilder()
  let mut in_str = 0
  let mut j = 0
  let mut colon_index = -1
  while j < n {
    let c = content.at(j).to_int()
    if in_str != 0 {
      if c == 0x5C {
        j = j + 1
        if j < n {
          j = j + 1
        } else {
          break
        }
        continue
      }
      if c == in_str {
        in_str = 0
      }
      key_sb.write_char(Int32::unsafe_to_char(c))
      j = j + 1
      continue
    }
    if c == 0x22 || c == 0x27 {
      in_str = c
      key_sb.write_char(Int32::unsafe_to_char(c))
      j = j + 1
      continue
    }
    if c == 0x3A {
      colon_index = j
      break
    }
    key_sb.write_char(Int32::unsafe_to_char(c))
    j = j + 1
  }
  if colon_index < 0 {
    raise @moonjson.Unexpected(
      @moonjson.At::{ at: 0, line: 1, column: 1, },
      Int32::unsafe_to_char(0x20),
    )
  }
  let raw_key = key_sb.to_string()
  let key = parse_key_string(raw_key)
  let raw_value = trim_leading_spaces(content[colon_index + 1:])
  (key, raw_value)
}

///|
fn parse_key_string(s : String) -> String raise @moonjson.Refused {
  let n = s.length()
  if n >= 2 {
    let a = s.at(0).to_int()
    let b = s.at(n - 1).to_int()
    if (a == 0x22 && b == 0x22) || (a == 0x27 && b == 0x27) {
      return parse_string_literal(s)
    }
  }
  rstrip(s)
}

///|
fn CsonParser::parse_inline_value(
  self : CsonParser,
  raw : StringView,
) -> Json raise @moonjson.Refused {
  let r = trim_trailing_spaces(raw)
  if r.length() == 0 {
    return Json::object(Map::from_array([]))
  }
  let first = r.at(0).to_int()
  if first == 0x27 && begins_with(r, "'''") {
    return Json::string(parse_block_string(r))
  }
  if first == 0x22 && begins_with(r, "\"\"\"") {
    return Json::string(parse_block_string(r))
  }
  if first == 0x22 {
    return Json::string(parse_string_literal(r))
  }
  if first == 0x27 {
    return Json::string(parse_string_literal(r))
  }
  if r == "true" {
    return Json::boolean(true)
  }
  if r == "false" {
    return Json::boolean(false)
  }
  if r == "null" {
    return Json::null()
  }
  match self.parse_number(r) {
    Some(d) => Json::number(d)
    None => Json::string(r)
  }
}

// ---------------------------------------------------------------------------
// Scalars: numbers, strings, block strings
// ---------------------------------------------------------------------------

///|
fn CsonParser::parse_number(self : CsonParser, t : StringView) -> Double? {
  let n = t.length()
  if n == 0 {
    return None
  }
  let c0 = t.at(0).to_int()
  let c1 = if n > 1 { t.at(1).to_int() } else { 0 }
  if c0 == 0x30 && (c1 == 0x78 || c1 == 0x58) {
    if self.flavor.extra_numbers {
      parse_hex(t)
    } else {
      None
    }
  } else {
    let d = @string.parse_double(t) catch { _ => return None }
    Some(d)
  }
}

///|
fn parse_hex(t : StringView) -> Double? {
  let n = t.length()
  let mut i = 2
  if i >= n {
    return None
  }
  let mut val = 0.0
  while i < n {
    let d = hex_value(t.at(i).to_int())
    if d < 0 {
      return None
    }
    val = val * 16.0 + d.to_double()
    i = i + 1
  }
  Some(val)
}

///|
fn parse_block_string(raw : StringView) -> String {
  let quote3 = raw[0:3].to_owned()
  let close = index_of_from(raw, quote3, 3)
  let inner = match close {
    Some(c) => raw[3:c]
    None => raw[3:]
  }
  let mut body = inner
  if begins_with(body, "\n") {
    body = body[1:]
  }
  let parts = split_on(body, 0x0A)
  let min = min_indent(parts)
  let dedented : Array[StringView] = []
  for p in parts {
    dedented.push(remove_leading(p, min))
  }
  let mut joined = join_str(dedented, "\n")
  if ends_with(joined, "\n") {
    joined = joined[0:joined.length() - 1].to_owned()
  }
  rstrip(joined)
}

///|
fn parse_string_literal(s : StringView) -> String raise @moonjson.Refused {
  let n = s.length()
  let sb = StringBuilder()
  let mut j = 1
  while j < n - 1 {
    let c = s.at(j).to_int()
    if c == 0x5C {
      j = j + 1
      if j >= n - 1 {
        break
      }
      let e = s.at(j).to_int()
      match e {
        0x22 => sb.write_char(Int32::unsafe_to_char(0x22))
        0x5C => sb.write_char(Int32::unsafe_to_char(0x5C))
        0x2F => sb.write_char(Int32::unsafe_to_char(0x2F))
        0x62 => sb.write_char(Int32::unsafe_to_char(0x08))
        0x66 => sb.write_char(Int32::unsafe_to_char(0x0C))
        0x6E => sb.write_char(Int32::unsafe_to_char(0x0A))
        0x72 => sb.write_char(Int32::unsafe_to_char(0x0D))
        0x74 => sb.write_char(Int32::unsafe_to_char(0x09))
        0x75 =>
          if j + 4 < n - 1 {
            let code = read_hex4(s, j + 1)
            sb.write_char(Int32::unsafe_to_char(code))
            j = j + 4
          } else {
            sb.write_char(Int32::unsafe_to_char(e))
          }
        _ => sb.write_char(Int32::unsafe_to_char(e))
      }
      j = j + 1
    } else {
      sb.write_char(Int32::unsafe_to_char(c))
      j = j + 1
    }
  }
  sb.to_string()
}

///|
fn read_hex4(s : StringView, start : Int32) -> Int32 raise @moonjson.Refused {
  let mut v = 0
  for k in 0..<=4 {
    let d = hex_value(s.at(start + k).to_int())
    if d < 0 {
      raise @moonjson.BadEscape(@moonjson.At::{ at: 0, line: 1, column: 1, })
    }
    v = v * 16 + d
  }
  v
}

// ---------------------------------------------------------------------------
// Small string helpers
// ---------------------------------------------------------------------------

///|
fn count_spaces(s : StringView) -> Int32 {
  let n = s.length()
  let mut k = 0
  while k < n && s.at(k).to_int() == 0x20 {
    k = k + 1
  }
  k
}

///|
fn strip_cr(s : StringView) -> StringView {
  let n = s.length()
  if n > 0 && s.at(n - 1).to_int() == 0x0D {
    s[0:n - 1]
  } else {
    s
  }
}

///|
fn split_newline(s : String) -> Array[StringView] {
  let res : Array[StringView] = []
  let n = s.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if s.at(i).to_int() == 0x0A {
      res.push(s[start:i])
      i = i + 1
      start = i
    } else {
      i = i + 1
    }
  }
  if start < n {
    res.push(s[start:n])
  }
  res
}

///|
fn has_top_level_colon(s : StringView) -> Bool {
  let n = s.length()
  let mut j = 0
  let mut in_str = 0
  while j < n {
    let c = s.at(j).to_int()
    if in_str != 0 {
      if c == 0x5C {
        j = j + 1
        if j < n {
          j = j + 1
        } else {
          break
        }
        continue
      }
      if c == in_str {
        in_str = 0
      }
      j = j + 1
      continue
    }
    if c == 0x22 || c == 0x27 {
      in_str = c
      j = j + 1
      continue
    }
    if c == 0x3A {
      return true
    }
    j = j + 1
  }
  false
}

///|
fn index_of_from(s : StringView, sub : String, start : Int32) -> Int32? {
  let n = s.length()
  let m = sub.length()
  if m == 0 {
    return Some(start)
  }
  let mut i = start
  while i + m <= n {
    let mut ok = true
    let mut k = 0
    while k < m {
      if s.at(i + k).to_int() != sub.at(k).to_int() {
        ok = false
        break
      }
      k = k + 1
    }
    if ok {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
fn split_on(s : StringView, ch : Int32) -> Array[StringView] {
  let res : Array[StringView] = []
  let n = s.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if s.at(i).to_int() == ch {
      res.push(s[start:i])
      i = i + 1
      start = i
    } else {
      i = i + 1
    }
  }
  res.push(s[start:n])
  res
}

///|
fn min_indent(parts : Array[StringView]) -> Int32 {
  let mut m = -1
  for p in parts {
    if p.length() == 0 {
      continue
    }
    let mut k = 0
    while k < p.length() && p.at(k).to_int() == 0x20 {
      k = k + 1
    }
    m = if m < 0 { k } else if k < m { k } else { m }
  }
  m
}

///|
fn remove_leading(p : StringView, k : Int32) -> StringView {
  let mut j = 0
  while j < k && j < p.length() && p.at(j).to_int() == 0x20 {
    j = j + 1
  }
  p[j:]
}

///|
fn join_str(arr : Array[StringView], sep : String) -> String {
  let sb = StringBuilder()
  let n = arr.length()
  for i in 0..<n {
    if i > 0 {
      sb.write_string(sep)
    }
    sb.write_view(arr[i])
  }
  sb.to_string()
}

///|
fn rstrip(s : StringView) -> String {
  let n = s.length()
  let mut end = n
  while end > 0 {
    let c = s.at(end - 1).to_int()
    if c == 0x20 || c == 0x09 {
      end = end - 1
    } else {
      break
    }
  }
  s[0:end].to_owned()
}

///|
fn trim_leading_spaces(s : StringView) -> String {
  let n = s.length()
  let mut j = 0
  while j < n && (s.at(j).to_int() == 0x20 || s.at(j).to_int() == 0x09) {
    j = j + 1
  }
  s[j:].to_owned()
}

///|
fn trim_trailing_spaces(s : StringView) -> String {
  rstrip(s)
}

///|
fn begins_with(s : StringView, p : String) -> Bool {
  let m = p.length()
  if s.length() < m {
    return false
  }
  let mut k = 0
  while k < m {
    if s.at(k).to_int() != p.at(k).to_int() {
      return false
    }
    k = k + 1
  }
  true
}

///|
fn ends_with(s : StringView, p : String) -> Bool {
  let m = p.length()
  let n = s.length()
  if n < m {
    return false
  }
  let mut k = 0
  while k < m {
    if s.at(n - m + k).to_int() != p.at(k).to_int() {
      return false
    }
    k = k + 1
  }
  true
}

///|
fn hex_value(c : Int32) -> Int32 {
  if c >= 0x30 && c <= 0x39 {
    c - 0x30
  } else if c >= 0x41 && c <= 0x46 {
    c - 0x41 + 10
  } else if c >= 0x61 && c <= 0x66 {
    c - 0x61 + 10
  } else {
    -1
  }
}
