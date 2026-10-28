// Hjson — a user interface for JSON: https://hjson.github.io/
//
// A lenient reader for Hjson, "a user interface for JSON". The reader accepts
// the syntax Hjson admits: comments of three kinds, braces that may be left
// off objects and brackets off arrays, keys that need not be quoted, members
// and elements separated by little more than newlines, quoteless values, and
// multiline strings. The writer is strict: a tree read here is put back as
// JSON by delegating to `@moonjson`, because Hjson has no canonical text form
// of its own.

///|
/// Turn a Hjson codepoint (an `Int32`) into a `Char`.
fn to_char(c : Int32) -> Char {
  c.unsafe_to_char()
}

///|
/// One hexadecimal digit, or `-1` when `c` is not one.
fn nibble(c : Int32) -> Int32 {
  if c >= 0x30 && c <= 0x39 {
    c - 0x30
  } else if c >= 0x61 && c <= 0x66 {
    c - 0x61 + 10
  } else if c >= 0x41 && c <= 0x46 {
    c - 0x41 + 10
  } else {
    -1
  }
}

///|
/// Is `c` whitespace Hjson ignores between tokens?
fn is_ws(c : Int32) -> Bool {
  c == 0x20 || c == 0x09 || c == 0x0D || c == 0x0A
}

///|
/// The scanner: the source text and a cursor into it.
priv struct Parser {
  src : StringView
  mut i : Int32
}

///|
/// The codepoint at byte offset `k`, or `-1` past the end.
fn Parser::peek(self : Parser, k : Int32) -> Int32 {
  if k < self.src.length() {
    self.src.at(k).to_int()
  } else {
    -1
  }
}

///|
/// The codepoint at the cursor, or `-1` past the end.
fn Parser::here(self : Parser) -> Int32 {
  self.peek(self.i)
}

///|
/// Build a `Bad` refusal positioned at the cursor.
fn Parser::error(self : Parser, why : String) -> @moonjson.Refused {
  @moonjson.Bad(at=self.i, why~)
}

///|
/// Skip whitespace and the three kinds of comment (`//`, `#`, `/* */`),
/// crossing newlines. Used before reading a value.
fn Parser::white(self : Parser) -> Unit raise @moonjson.Refused {
  while true {
    let c = self.here()
    if c < 0 {
      return
    } else if is_ws(c) {
      self.i += 1
    } else if c == 0x2F && self.peek(self.i + 1) == 0x2F {
      while self.here() >= 0 && self.here() != 0x0A {
        self.i += 1
      }
    } else if c == 0x23 {
      while self.here() >= 0 && self.here() != 0x0A {
        self.i += 1
      }
    } else if c == 0x2F && self.peek(self.i + 1) == 0x2A {
      self.i += 2
      while true {
        if self.here() < 0 {
          raise self.error("unterminated comment")
        } else if self.here() == 0x2A && self.peek(self.i + 1) == 0x2F {
          self.i += 2
          break
        } else {
          self.i += 1
        }
      }
    } else {
      return
    }
  }
}

///|
/// Skip spaces, tabs and carriage returns and the comments, but not a
/// newline: after a member name we may meet a `:` on the same line, and a
/// newline means the value is an indented block instead.
fn Parser::white_inline(self : Parser) -> Unit raise @moonjson.Refused {
  while true {
    let c = self.here()
    if c == 0x20 || c == 0x09 || c == 0x0D {
      self.i += 1
    } else if c == 0x2F && self.peek(self.i + 1) == 0x2F {
      while self.here() >= 0 && self.here() != 0x0A {
        self.i += 1
      }
    } else if c == 0x23 {
      while self.here() >= 0 && self.here() != 0x0A {
        self.i += 1
      }
    } else if c == 0x2F && self.peek(self.i + 1) == 0x2A {
      self.i += 2
      while true {
        if self.here() < 0 {
          raise self.error("unterminated comment")
        } else if self.here() == 0x2A && self.peek(self.i + 1) == 0x2F {
          self.i += 2
          break
        } else {
          self.i += 1
        }
      }
    } else {
      return
    }
  }
}

///|
/// The indentation (leading spaces and tabs) of the line the cursor is on.
fn Parser::line_indent(self : Parser) -> Int32 {
  let mut k = self.i
  while k > 0 {
    let c = self.src.at(k - 1).to_int()
    if c == 0x0A || c == 0x0D {
      break
    }
    k -= 1
  }
  let mut n = 0
  while k + n < self.i {
    let c = self.src.at(k + n).to_int()
    if c == 0x20 || c == 0x09 {
      n += 1
    } else {
      break
    }
  }
  n
}

///|
/// Skip to the next significant token. When the container is brace-delimited
/// any indentation is accepted; otherwise a line indented less than the
/// container's base stops the container. Returns `false` when the container is
/// finished.
fn Parser::ws_cont(
  self : Parser,
  brace_open : Bool,
  base : Int32,
) -> Bool raise @moonjson.Refused {
  let mut result = false
  let mut done = false
  while !done {
    let c = self.here()
    if c < 0 {
      result = false
      done = true
    } else if is_ws(c) {
      self.i += 1
    } else if c == 0x2F && self.peek(self.i + 1) == 0x2F {
      while self.here() >= 0 && self.here() != 0x0A {
        self.i += 1
      }
    } else if c == 0x23 {
      while self.here() >= 0 && self.here() != 0x0A {
        self.i += 1
      }
    } else if c == 0x2F && self.peek(self.i + 1) == 0x2A {
      self.i += 2
      let mut closed = false
      while !closed {
        if self.here() < 0 {
          raise self.error("unterminated comment")
        } else if self.here() == 0x2A && self.peek(self.i + 1) == 0x2F {
          self.i += 2
          closed = true
        } else {
          self.i += 1
        }
      }
    } else if brace_open {
      result = true
      done = true
    } else if c == 0x7D || c == 0x5D {
      result = false
      done = true
    } else if self.line_indent() < base {
      result = false
      done = true
    } else {
      result = true
      done = true
    }
  }
  result
}

///|
/// Skip only spaces, tabs and carriage returns (no newline, no comment).
fn Parser::skip_inline_space(self : Parser) -> Unit {
  while true {
    let c = self.here()
    if c == 0x20 || c == 0x09 || c == 0x0D {
      self.i += 1
    } else {
      return
    }
  }
}

///|
/// A member name: a quoted string or a bareword. Returns `None` when the
/// cursor is not at one.
fn Parser::try_keyname(self : Parser) -> String? raise @moonjson.Refused {
  let c = self.here()
  if c == 0x22 {
    return Some(self.read_string(0x22))
  }
  if c == 0x27 {
    if self.peek(self.i + 1) == 0x27 && self.peek(self.i + 2) == 0x27 {
      return None
    }
    return Some(self.read_string(0x27))
  }
  if c == 0x24 ||
    c == 0x5F ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) {
    let start = self.i
    while true {
      let d = self.here()
      if d == 0x24 ||
        d == 0x5F ||
        d == 0x2D ||
        d == 0x2E ||
        (d >= 0x41 && d <= 0x5A) ||
        (d >= 0x61 && d <= 0x7A) ||
        (d >= 0x30 && d <= 0x39) {
        self.i += 1
      } else {
        break
      }
    }
    return Some(self.src[start:self.i].to_owned())
  }
  None
}

///|
/// A member name, or a refusal.
fn Parser::read_keyname(self : Parser) -> String raise @moonjson.Refused {
  match self.try_keyname() {
    Some(k) => k
    None => raise self.error("expected a member name")
  }
}

///|
/// A quoted string (`"` or `'`), with the escapes Hjson allows.
fn Parser::read_string(
  self : Parser,
  q : Int32,
) -> String raise @moonjson.Refused {
  self.i += 1
  let sb = StringBuilder()
  let mut run = self.i
  let mut result = ""
  let mut done = false
  while !done {
    let c = self.here()
    if c < 0 {
      raise self.error("unterminated string")
    } else if c == q {
      sb.write_view(self.src[run:self.i])
      self.i += 1
      result = sb.to_string()
      done = true
    } else if c == 0x5C {
      sb.write_view(self.src[run:self.i])
      self.read_escape(sb)
      run = self.i
    } else if c < 0x20 {
      raise self.error("control character in string")
    } else {
      self.i += 1
    }
  }
  result
}

///|
/// One escape sequence, appending the character it stands for.
fn Parser::read_escape(
  self : Parser,
  sb : StringBuilder,
) -> Unit raise @moonjson.Refused {
  self.i += 1
  let c = self.here()
  self.i += 1
  match c {
    0x22 => sb.write_char(to_char(0x22))
    0x5C => sb.write_char(to_char(0x5C))
    0x2F => sb.write_char(to_char(0x2F))
    0x62 => sb.write_char(to_char(0x08))
    0x66 => sb.write_char(to_char(0x0C))
    0x6E => sb.write_char(to_char(0x0A))
    0x72 => sb.write_char(to_char(0x0D))
    0x74 => sb.write_char(to_char(0x09))
    0x75 => {
      let cp = self.read_hex4()
      sb.write_char(to_char(cp))
    }
    _ => raise self.error("invalid escape sequence")
  }
}

///|
/// Four hexadecimal digits as one codepoint.
fn Parser::read_hex4(self : Parser) -> Int32 raise @moonjson.Refused {
  let mut v = 0
  for _ in 0..<4 {
    let d = nibble(self.here())
    if d < 0 {
      raise self.error("bad \\u escape")
    }
    v = (v << 4) | d
    self.i += 1
  }
  v
}

///|
/// A multiline string: `''' … '''` or `""" … """`. The newline right after
/// the opening quotes is dropped, every line is dedented by the common leading
/// whitespace, and the trailing newline before the closing quotes is removed.
fn Parser::read_mlstring(
  self : Parser,
  q : Int32,
) -> String raise @moonjson.Refused {
  self.i += 3
  if self.here() == 0x0A {
    self.i += 1
  } else if self.here() == 0x0D {
    self.i += 1
    if self.here() == 0x0A {
      self.i += 1
    }
  }
  let start = self.i
  let mut closed = false
  while !closed {
    let c = self.here()
    if c < 0 {
      raise self.error("unterminated multiline string")
    } else if c == q && self.peek(self.i + 1) == q && self.peek(self.i + 2) == q {
      closed = true
    } else {
      self.i += 1
    }
  }
  let body = self.src[start:self.i].to_owned()
  self.i += 3
  let lines : Array[String] = []
  let mut j = 0
  let n = body.length()
  while j < n {
    let mut k = j
    while k < n && body[k] != '\n' {
      k += 1
    }
    let mut line = body[j:k].to_owned()
    let ll = line.length()
    if ll > 0 && line[ll - 1] == '\r' {
      line = line[0:ll - 1].to_owned()
    }
    lines.push(line)
    j = k + 1
  }
  let mut common = -1
  for line in lines {
    let mut m = 0
    let ll = line.length()
    while m < ll {
      let c = line[m].to_int()
      if c == 0x20 || c == 0x09 {
        m += 1
      } else {
        break
      }
    }
    if common < 0 || m < common {
      common = m
    }
  }
  if common < 0 {
    common = 0
  }
  let out = StringBuilder()
  let last = lines.length() - 1
  let mut idx = 0
  while idx < lines.length() {
    let mut line = lines[idx]
    if idx > 0 {
      out.write_char(to_char(0x0A))
    }
    line = line[common:line.length()].to_owned()
    if idx == last {
      let mut e = line.length()
      while e > 0 {
        let c = line[e - 1].to_int()
        if c == 0x20 || c == 0x09 {
          e -= 1
        } else {
          break
        }
      }
      line = line[0:e].to_owned()
    }
    out.write_string(line)
    idx += 1
  }
  let result = out.to_string()
  let rl = result.length()
  if rl > 0 && result[rl - 1] == '\n' {
    result[0:rl - 1].to_owned()
  } else {
    result
  }
}

///|
/// A run of quoteless characters: anything but whitespace, a structural
/// character, a comment start, a quote, or a control character.
fn Parser::read_quoteless(self : Parser) -> String raise @moonjson.Refused {
  let start = self.i
  while true {
    let c = self.here()
    if c < 0 {
      break
    } else if is_ws(c) {
      break
    } else if c == 0x7B ||
      c == 0x7D ||
      c == 0x5B ||
      c == 0x5D ||
      c == 0x2C ||
      c == 0x3A ||
      c == 0x23 ||
      c == 0x22 ||
      c == 0x27 {
      break
    } else if c < 0x20 {
      break
    } else if c == 0x2F &&
      (self.peek(self.i + 1) == 0x2F || self.peek(self.i + 1) == 0x2A) {
      break
    } else {
      self.i += 1
    }
  }
  if self.i == start {
    raise self.error("empty value")
  }
  self.src[start:self.i].to_owned()
}

///|
/// Does `token` read as a number?
fn is_number_string(token : String) -> Bool {
  let n = token.length()
  if n == 0 {
    return false
  }
  let mut k = 0
  if token[k] == '+' || token[k] == '-' {
    k += 1
  }
  if k < n &&
    token[k] == '0' &&
    k + 1 < n &&
    (token[k + 1] == 'x' || token[k + 1] == 'X') {
    if n <= k + 2 {
      return false
    }
    for j in (k + 2)..<n {
      if nibble(token[j].to_int()) < 0 {
        return false
      }
    }
    return true
  }
  let mut has_digit = false
  while k < n && token[k] >= '0' && token[k] <= '9' {
    k += 1
    has_digit = true
  }
  if k < n && token[k] == '.' {
    k += 1
    while k < n && token[k] >= '0' && token[k] <= '9' {
      k += 1
      has_digit = true
    }
  }
  if k < n && (token[k] == 'e' || token[k] == 'E') {
    k += 1
    if k < n && (token[k] == '+' || token[k] == '-') {
      k += 1
    }
    while k < n && token[k] >= '0' && token[k] <= '9' {
      k += 1
    }
  }
  has_digit && k == n
}

///|
/// Parse `token` (already known to be a number) into a `Json` number.
fn Parser::parse_number_string(
  self : Parser,
  token : String,
) -> Json raise @moonjson.Refused {
  if token.length() >= 3 &&
    token[0] == '0' &&
    (token[1] == 'x' || token[1] == 'X') {
    let mut value = 0.0
    for j in 2..<token.length() {
      value = value * 16.0 + nibble(token[j].to_int()).to_double()
    }
    return Json::number(value)
  }
  let d = @string.parse_double(token) catch {
    _ => raise self.error("not a number: " + token)
  }
  Json::number(d)
}

///|
/// One scalar: a quoted string, a multiline string, a number, one of the
/// words `true`/`false`/`null`, or a quoteless string.
fn Parser::scalar(self : Parser) -> Json raise @moonjson.Refused {
  let c = self.here()
  if c < 0 {
    raise self.error("unexpected end of input")
  } else if c == 0x22 {
    return Json::string(self.read_string(0x22))
  } else if c == 0x27 {
    if self.peek(self.i + 1) == 0x27 && self.peek(self.i + 2) == 0x27 {
      return Json::string(self.read_mlstring(0x27))
    }
    return Json::string(self.read_string(0x27))
  }
  let token = self.read_quoteless()
  if token == "true" {
    return Json::boolean(true)
  } else if token == "false" {
    return Json::boolean(false)
  } else if token == "null" {
    return Json::null()
  } else if is_number_string(token) {
    return self.parse_number_string(token)
  } else {
    return Json::string(token)
  }
}

///|
/// A bareword at a value position: an object when followed by `:`, otherwise a
/// scalar.
fn Parser::scalar_or_object(self : Parser) -> Json raise @moonjson.Refused {
  let saved = self.i
  match self.try_keyname() {
    Some(_) => {
      self.white_inline()
      if self.here() == 0x3A {
        self.i = saved
        return self.read_object(false)
      }
      self.i = saved
      return self.scalar()
    }
    None => self.scalar()
  }
}

///|
/// One value, after any leading whitespace.
fn Parser::value(self : Parser) -> Json raise @moonjson.Refused {
  self.white()
  let c = self.here()
  if c < 0 {
    raise self.error("unexpected end of input")
  } else if c == 0x7B {
    return self.read_object(true)
  } else if c == 0x5B {
    return self.read_array(true)
  } else if c == 0x22 {
    return Json::string(self.read_string(0x22))
  } else if c == 0x27 {
    if self.peek(self.i + 1) == 0x27 && self.peek(self.i + 2) == 0x27 {
      return Json::string(self.read_mlstring(0x27))
    }
    return Json::string(self.read_string(0x27))
  } else if c == 0x2D && is_ws(self.peek(self.i + 1)) {
    return self.read_array(false)
  } else {
    return self.scalar_or_object()
  }
}

///|
/// An object: brace-delimited, or a brace-less block whose members share an
/// indentation.
fn Parser::read_object(
  self : Parser,
  brace_open : Bool,
) -> Json raise @moonjson.Refused {
  if brace_open {
    self.i += 1
  }
  let members : Map[String, Json] = Map([])
  let base = self.line_indent()
  while true {
    if !self.ws_cont(brace_open, base) {
      break
    }
    let c = self.here()
    if brace_open && c == 0x7D {
      self.i += 1
      break
    }
    if !brace_open && (c == 0x7D || c == 0x5D) {
      break
    }
    if c == 0x2C {
      self.i += 1
      continue
    }
    let key = self.read_keyname()
    self.white_inline()
    if self.here() == 0x3A {
      self.i += 1
      members[key] = self.value()
    } else {
      members[key] = self.value()
    }
  }
  Json::object(members)
}

///|
/// An array: bracket-delimited, or a brace-less block whose elements start on
/// their own lines, each optionally led by `-`.
fn Parser::read_array(
  self : Parser,
  brace_open : Bool,
) -> Json raise @moonjson.Refused {
  if brace_open {
    self.i += 1
  }
  let items : Array[Json] = []
  let base = self.line_indent()
  while true {
    if !self.ws_cont(brace_open, base) {
      break
    }
    let c = self.here()
    if brace_open && c == 0x5D {
      self.i += 1
      break
    }
    if !brace_open && (c == 0x5D || c == 0x7D) {
      break
    }
    if c == 0x2C {
      self.i += 1
      continue
    }
    if c == 0x2D && is_ws(self.peek(self.i + 1)) {
      self.i += 1
      self.skip_inline_space()
    }
    items.push(self.value())
  }
  Json::array(items)
}

///|
/// The whole document: an object, an array, or a scalar.
fn Parser::parse(self : Parser) -> Json raise @moonjson.Refused {
  self.white()
  let c = self.here()
  if c < 0 {
    raise self.error("empty document")
  } else if c == 0x7B {
    return self.read_object(true)
  } else if c == 0x5B {
    return self.read_array(true)
  } else if c == 0x2D && is_ws(self.peek(self.i + 1)) {
    return self.read_array(false)
  }
  let saved = self.i
  match self.try_keyname() {
    Some(k) => {
      self.white_inline()
      if self.here() == 0x3A {
        self.i = saved
        self.read_object(false)
      } else if k == "true" || k == "false" || k == "null" {
        self.i = saved
        self.scalar()
      } else {
        self.i = saved
        self.scalar()
      }
    }
    None => self.scalar()
  }
}

///|
/// Read one Hjson document from text.
///
/// Hjson is a superset of JSON as far as the tree is concerned, so whatever
/// comes back here can be written out again as strict JSON with `dumps`. The
/// `flavor` argument is accepted for the family's common signature; Hjson is
/// always read leniently.
pub fn loads(
  text : StringView,
  flavor~ : @moonjson.Flavor = @moonjson.relaxed,
) -> Json raise @moonjson.Refused {
  let _ = flavor
  let p = Parser::{ src: text, i: 0, }
  let value = p.parse()
  p.white()
  if p.i < p.src.length() {
    raise @moonjson.Bad(at=p.i, why="trailing input after the document")
  }
  value
}

///|
/// Read one Hjson document from the UTF-8 bytes a body arrives as.
///
/// A leading byte-order mark is skipped by default. Decoding that fails is a
/// `Bad` refusal.
pub fn load(
  input : BytesView,
  flavor~ : @moonjson.Flavor = @moonjson.relaxed,
  bom~ : Bool = true,
) -> Json raise @moonjson.Refused {
  let text = @utf8.decode(input, ignore_bom=bom) catch {
    _ => raise @moonjson.Bad(at=0, why="utf8")
  }
  loads(text[:], flavor~)
}

///|
/// Write a tree as strict JSON, whatever dialect it was read from.
///
/// Hjson has no canonical text form of its own — the same tree can be written
/// many ways — so the writer emits strict JSON by delegating to `@moonjson`.
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
pub fn dump(
  value : Json,
  indent~ : Int32 = 0,
  ascii~ : Bool = false,
  sort~ : Bool = false,
) -> Bytes {
  @moonjson.dump(value, indent~, ascii~, sort~)
}
