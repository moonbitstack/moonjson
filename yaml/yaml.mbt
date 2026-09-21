// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One line that carries structure: its indentation, its content with the
/// indentation and any trailing comment removed, and where it began.
///
/// Blank and comment-only lines are dropped while tokenising, so every line here
/// is one the parser has to account for. The position is kept so an error names
/// the line in the file rather than the line among the ones that survived.
priv struct Line {
  indent : Int
  text : String
  at : @moonjson.At
}

///|
/// Whether `c` is an ASCII space or tab.
fn is_space(c : Int) -> Bool {
  c == ' '.to_int() || c == '\t'.to_int()
}

///|
/// Strip leading and trailing ASCII whitespace.
fn trim(s : String) -> String {
  let mut start = 0
  let mut end = s.length()
  while start < end && is_space(s[start].to_int()) {
    start = start + 1
  }
  while end > start && is_space(s[end - 1].to_int()) {
    end = end - 1
  }
  s[start:end].to_owned()
}

///|
/// Remove an unquoted trailing comment.
///
/// A `#` at the start of the content, or preceded by whitespace, begins one. A
/// `#` inside a quoted scalar or glued to a non-space character is part of the
/// value — `a#b` is the string `a#b`, which is what the specification says and
/// what a naive split on `#` gets wrong.
fn strip_comment(s : String) -> String {
  let mut quote = 0
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if quote != 0 {
      if c == quote {
        quote = 0
      }
    } else if c == '"'.to_int() || c == '\''.to_int() {
      quote = c
    } else if c == '#'.to_int() && (i == 0 || is_space(s[i - 1].to_int())) {
      return s[0:i].to_owned()
    }
  }
  s
}

///|
/// Split the source into the lines that carry structure, keeping each one's
/// position in the original.
fn tokenize(src : StringView) -> Array[Line] {
  let out : Array[Line] = []
  let sb = StringBuilder()
  let mut start = 0
  let mut line_no = 1
  let flush = fn(text : String, at : Int, no : Int) {
    let mut indent = 0
    while indent < text.length() && text[indent].to_int() == ' '.to_int() {
      indent = indent + 1
    }
    let content = trim(strip_comment(text[indent:].to_owned()))
    if content.length() > 0 {
      out.push({
        indent,
        text: content,
        at: { at: at + indent, line: no, column: indent + 1, },
      })
    }
  }
  for i = 0; i < src.length(); i = i + 1 {
    let c = src[i].to_int()
    if c == '\n'.to_int() {
      flush(sb.to_string(), start, line_no)
      sb.reset()
      start = i + 1
      line_no = line_no + 1
    } else if c != '\r'.to_int() {
      sb.write_char(src[i].unsafe_to_char())
    }
  }
  flush(sb.to_string(), start, line_no)
  out
}

///|
/// Whether a line begins a block sequence item — `-` alone, or `-` and a space.
fn is_item(s : String) -> Bool {
  s.length() > 0 &&
  s[0].to_int() == '-'.to_int() &&
  (s.length() == 1 || is_space(s[1].to_int()))
}

///|
/// The index of the `:` that separates a key from its value: the first one at
/// end of line or followed by whitespace, outside quotes. `None` when the line
/// is not a mapping entry.
fn key_sep(s : String) -> Int? {
  let mut quote = 0
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if quote != 0 {
      if c == quote {
        quote = 0
      }
    } else if c == '"'.to_int() || c == '\''.to_int() {
      quote = c
    } else if c == ':'.to_int() &&
      (i + 1 == s.length() || is_space(s[i + 1].to_int())) {
      return Some(i)
    }
  }
  None
}

///|
/// Strip the quotes around a key, if it has them.
fn unquote(s : String) -> String {
  if s.length() >= 2 {
    let q = s[0].to_int()
    if (q == '"'.to_int() || q == '\''.to_int()) &&
      s[s.length() - 1].to_int() == q {
      return s[1:s.length() - 1].to_owned()
    }
  }
  s
}

///|
/// The escapes a double-quoted scalar carries.
///
/// A single-quoted scalar has none — which is the whole reason to have both
/// forms, and the reason a Windows path is written in single quotes.
fn unescape(s : String) -> String {
  let out = StringBuilder()
  let mut i = 0
  while i < s.length() {
    let c = s[i].to_int()
    if c != 0x5c || i + 1 >= s.length() {
      out.write_char(s[i].unsafe_to_char())
      i = i + 1
      continue
    }
    let e = s[i + 1].to_int()
    i = i + 2
    match e {
      0x6e => out.write_char('\n')
      0x74 => out.write_char('\t')
      0x72 => out.write_char('\r')
      0x30 => out.write_char('\u{00}')
      0x5c => out.write_char('\\')
      0x22 => out.write_char('"')
      0x27 => out.write_char('\'')
      0x78 =>
        if i + 1 < s.length() {
          match (nibble(s[i].to_int()), nibble(s[i + 1].to_int())) {
            (Some(hi), Some(lo)) => {
              out.write_char(((hi << 4) | lo).unsafe_to_char())
              i = i + 2
            }
            _ => out.write_string("\\x")
          }
        } else {
          out.write_string("\\x")
        }
      _ => {
        out.write_char('\\')
        out.write_char(s[i - 1].unsafe_to_char())
      }
    }
  }
  out.to_string()
}

///|
/// A hexadecimal digit's value.
fn nibble(c : Int) -> Int? {
  if c >= 0x30 && c <= 0x39 {
    Some(c - 0x30)
  } else if c >= 0x61 && c <= 0x66 {
    Some(c - 0x61 + 10)
  } else if c >= 0x41 && c <= 0x46 {
    Some(c - 0x41 + 10)
  } else {
    None
  }
}

///|
/// A single-quoted scalar: the only thing it spells is a quote, doubled.
fn unsingle(s : String) -> String {
  let out = StringBuilder()
  let mut i = 0
  while i < s.length() {
    if s[i].to_int() == 0x27 && i + 1 < s.length() && s[i + 1].to_int() == 0x27 {
      out.write_char('\'')
      i = i + 2
    } else {
      out.write_char(s[i].unsafe_to_char())
      i = i + 1
    }
  }
  out.to_string()
}

///|
/// A scalar as the value it denotes.
///
/// Quoted stays a string, `~` and `null` and nothing are null, `true` and
/// `false` are booleans, a whole numeric literal is a number, and anything else
/// is the string it looks like — which is what makes `version: 1.0` a number and
/// `version: "1.0"` a string.
fn scalar(raw : String) -> Json {
  let s = trim(raw)
  if s.length() == 0 || s == "~" || s == "null" {
    return Json::null()
  }
  if s == "true" {
    return Json::boolean(true)
  }
  if s == "false" {
    return Json::boolean(false)
  }
  let first = s[0].to_int()
  if (first == '"'.to_int() || first == '\''.to_int()) &&
    s.length() >= 2 &&
    s[s.length() - 1].to_int() == first {
    let inner = s[1:s.length() - 1].to_owned()
    return Json::string(
      if first == '"'.to_int() {
        unescape(inner)
      } else {
        unsingle(inner)
      },
    )
  }
  match number(s) {
    Some(n) => Json::number(n)
    None => Json::string(s)
  }
}

///|
/// A decimal integer or float literal, or `None` for anything that is not wholly
/// numeric so the caller falls back to a string.
fn number(s : String) -> Double? {
  if s.length() == 0 {
    return None
  }
  let mut i = 0
  let mut neg = false
  if s[0].to_int() == '-'.to_int() {
    neg = true
    i = 1
  }
  if i >= s.length() {
    return None
  }
  let mut whole = 0.0
  let mut digits = false
  while i < s.length() &&
        s[i].to_int() >= '0'.to_int() &&
        s[i].to_int() <= '9'.to_int() {
    whole = whole * 10.0 + (s[i].to_int() - '0'.to_int()).to_double()
    digits = true
    i = i + 1
  }
  let mut value = whole
  if i < s.length() && s[i].to_int() == '.'.to_int() {
    i = i + 1
    let mut frac = 0.0
    let mut scale = 1.0
    while i < s.length() &&
          s[i].to_int() >= '0'.to_int() &&
          s[i].to_int() <= '9'.to_int() {
      frac = frac * 10.0 + (s[i].to_int() - '0'.to_int()).to_double()
      scale = scale * 10.0
      digits = true
      i = i + 1
    }
    value = value + frac / scale
  }
  if !digits || i != s.length() {
    return None
  }
  Some(if neg { -value } else { value })
}

///|
/// The reader's state: the lines, where it is, and the dialect it reads under.
priv struct Reader {
  lines : Array[Line]
  mut at : Int
  flavor : @moonjson.Flavor
}

///|
/// A mapping at indentation `ind`, consuming the consecutive entries at that
/// level. A key with no value on its line opens a nested block.
fn Reader::mapping(
  self : Reader,
  ind : Int,
  depth : Int,
) -> Json raise @moonjson.Malformed {
  guard depth <= self.flavor.depth else {
    raise @moonjson.TooDeep(self.lines[self.at].at)
  }
  let out : Map[String, Json] = Map([])
  while self.at < self.lines.length() &&
        self.lines[self.at].indent == ind &&
        !is_item(self.lines[self.at].text) {
    let line = self.lines[self.at]
    let sep = match key_sep(line.text) {
      Some(p) => p
      None => raise @moonjson.Unexpected(line.at, line.text[0].unsafe_to_char())
    }
    let key = unquote(trim(line.text[0:sep].to_owned()))
    let rest = trim(line.text[sep + 1:].to_owned())
    self.at = self.at + 1
    let value = if rest.length() == 0 {
      self.block(ind, depth + 1)
    } else {
      scalar(rest)
    }
    match (out.get(key), self.flavor.duplicates) {
      (Some(_), First) => ()
      (Some(_), Reject) => raise @moonjson.Repeated(line.at, key)
      _ => out[key] = value
    }
  }
  Json::object(out)
}

///|
/// A sequence at indentation `ind`. An item is a scalar, a nested block, or a
/// mapping that begins on the `-` line and continues on the lines aligned under
/// its first key.
fn Reader::sequence(
  self : Reader,
  ind : Int,
  depth : Int,
) -> Json raise @moonjson.Malformed {
  guard depth <= self.flavor.depth else {
    raise @moonjson.TooDeep(self.lines[self.at].at)
  }
  let out : Array[Json] = []
  while self.at < self.lines.length() &&
        self.lines[self.at].indent == ind &&
        is_item(self.lines[self.at].text) {
    let line = self.lines[self.at]
    let mut j = 1
    while j < line.text.length() && is_space(line.text[j].to_int()) {
      j = j + 1
    }
    let content = line.text[j:].to_owned()
    let column = ind + j
    if content.length() == 0 {
      self.at = self.at + 1
      out.push(self.block(ind, depth + 1))
    } else if key_sep(content) is Some(_) {
      // The `- key: value` line is the mapping's first entry, so it is read as
      // one, at the column its key starts in.
      self.lines[self.at] = { indent: column, text: content, at: line.at, }
      out.push(self.mapping(column, depth + 1))
    } else {
      self.at = self.at + 1
      out.push(scalar(content))
    }
  }
  Json::array(out)
}

///|
/// Whatever begins at the cursor, deeper than `parent`.
fn Reader::block(
  self : Reader,
  parent : Int,
  depth : Int,
) -> Json raise @moonjson.Malformed {
  if self.at >= self.lines.length() || self.lines[self.at].indent <= parent {
    return Json::null()
  }
  let ind = self.lines[self.at].indent
  if is_item(self.lines[self.at].text) {
    self.sequence(ind, depth)
  } else if key_sep(self.lines[self.at].text) is Some(_) {
    self.mapping(ind, depth)
  } else {
    let value = scalar(self.lines[self.at].text)
    self.at = self.at + 1
    value
  }
}

///|
/// One document's worth of lines.
fn one(
  lines : Array[Line],
  flavor : @moonjson.Flavor,
) -> Json raise @moonjson.Malformed {
  if lines.length() == 0 {
    return Json::object(Map([]))
  }
  let reader = Reader::{ lines, at: 0, flavor, }
  let root = lines[0].indent
  let doc = if is_item(lines[0].text) {
    reader.sequence(root, 1)
  } else if key_sep(lines[0].text) is Some(_) {
    reader.mapping(root, 1)
  } else {
    let value = scalar(lines[0].text)
    reader.at = 1
    value
  }
  if reader.at != lines.length() {
    raise @moonjson.Trailing(lines[reader.at].at)
  }
  doc
}

///|
/// Read a YAML document into the same `Json` tree every other reader here
/// produces.
///
/// **The profile.** Block style: mappings, sequences, nesting by indentation,
/// plain and quoted scalars, and `#` comments. This is the shape configuration
/// files are written in, and it is what `etc/service.yaml`, a Compose file and a
/// Kubernetes manifest are made of.
///
/// **Not yet**: anchors and aliases, tags, flow style (`{a: 1}`, `[1, 2]`),
/// block scalars (`|` and `>`), and multi-document streams. Those are the rest
/// of YAML 1.2 and they are tracked, with the official test suite as the gate;
/// until they land this reader refuses what it does not understand rather than
/// guessing at it.
///
/// Two of `flavor`'s settings reach here: `depth`, which bounds the nesting, and
/// `duplicates`, which decides what a key given twice means. The rest describe
/// JSON dialects and have nothing to say about YAML.
pub fn loads(
  src : StringView,
  flavor? : @moonjson.Flavor = @moonjson.strict,
) -> Json raise @moonjson.Malformed {
  one(tokenize(src), flavor)
}

///|
/// Every document in a stream, in the order they appear.
///
/// A `---` line opens a document and a `...` line closes one — the way one file
/// holds a Deployment and the Service in front of it. The answer is an array, so
/// the second document is index one.
///
/// A stream with no `---` in it is one document, which is why [`loads`] is this
/// same reader under the same rules: that is the common case and this is the
/// general one.
pub fn loads_all(
  src : StringView,
  flavor? : @moonjson.Flavor = @moonjson.strict,
) -> Array[Json] raise @moonjson.Malformed {
  let lines = tokenize(src)
  let out : Array[Json] = []
  let held : Array[Line] = []
  let mut opened = false
  for line in lines {
    if line.indent == 0 && (line.text == "---" || line.text == "...") {
      if held.length() > 0 {
        out.push(one(held, flavor))
        held.clear()
      }
      if line.text == "---" {
        opened = true
      }
    } else {
      held.push(line)
    }
  }
  if held.length() > 0 {
    out.push(one(held, flavor))
  }
  // A `---` with nothing under it is still a document, and an empty one.
  if out.length() == 0 && opened {
    out.push(Json::object(Map([])))
  }
  out
}

///|
/// One document, from bytes.
///
/// YAML is UTF-8; a byte-order mark is skipped by default because editors on
/// Windows write one and a document that begins with it is not malformed.
pub fn load(
  input : BytesView,
  flavor? : @moonjson.Flavor = @moonjson.strict,
  bom? : Bool = true,
) -> Json raise @moonjson.Malformed {
  let text = @utf8.decode(input, ignore_bom=bom) catch {
    _ => raise @moonjson.BadUtf8({ at: 0, line: 1, column: 1, })
  }
  loads(text[:], flavor~)
}

///|
/// Every document in a stream, from bytes.
pub fn load_all(
  input : BytesView,
  flavor? : @moonjson.Flavor = @moonjson.strict,
  bom? : Bool = true,
) -> Array[Json] raise @moonjson.Malformed {
  let text = @utf8.decode(input, ignore_bom=bom) catch {
    _ => raise @moonjson.BadUtf8({ at: 0, line: 1, column: 1, })
  }
  loads_all(text[:], flavor~)
}
