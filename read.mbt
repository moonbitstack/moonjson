// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read one document in the given dialect.
///
/// The whole input must be one value: anything after it, other than whitespace
/// and — where the dialect allows them — comments, is [`Trailing`], not silently
/// ignored. A parser that stops at the first value turns a truncated file into a
/// plausible one.
pub fn read(input : StringView, flavor : Flavor) -> Json raise Malformed {
  let r = { src: input, flavor, i: 0, }
  r.space()
  let value = r.value(0)
  r.space()
  if r.i < r.src.length() {
    raise Trailing(r.spot(r.i))
  }
  value
}

///|
/// Read one document from bytes, which is how one arrives over a wire.
pub fn read_bytes(input : BytesView, flavor : Flavor) -> Json raise Malformed {
  let text = @utf8.decode(input) catch {
    _ => raise BadUtf8({ at: 0, line: 1, column: 1, })
  }
  read(text[:], flavor)
}

///|
priv struct Reader {
  src : StringView
  flavor : Flavor
  mut i : Int
}

///|
/// Line and column are counted only once something has gone wrong, so the
/// reader carries no bookkeeping through the common case.
fn Reader::spot(self : Reader, at : Int) -> At {
  let mut line = 1
  let mut column = 1
  for k in 0..<at {
    if self.src.at(k).to_int() == 0x0A {
      line += 1
      column = 1
    } else {
      column += 1
    }
  }
  { at, line, column, }
}

///|
/// The code unit at `k`, or -1 past the end.
fn Reader::peek(self : Reader, k : Int) -> Int {
  if k < self.src.length() {
    self.src.at(k).to_int()
  } else {
    -1
  }
}

///|
fn Reader::here(self : Reader) -> Int {
  self.peek(self.i)
}

///|
fn Reader::fail(self : Reader) -> Malformed {
  let c = self.here()
  if c < 0 {
    Truncated(self.spot(self.i))
  } else {
    Unexpected(self.spot(self.i), c.unsafe_to_char())
  }
}

///|
fn Reader::space(self : Reader) -> Unit raise Malformed {
  let mut going = true
  while going {
    let c = self.here()
    if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
      self.i += 1
    } else if self.flavor.extra_space && is_extra_space(c) {
      self.i += 1
    } else if self.flavor.comments && c == 0x2F && self.peek(self.i + 1) == 0x2F {
      self.i += 2
      while self.here() >= 0 && !ends_line(self.here()) {
        self.i += 1
      }
    } else if self.flavor.comments && c == 0x2F && self.peek(self.i + 1) == 0x2A {
      let start = self.i
      self.i += 2
      let mut closed = false
      while !closed {
        if self.here() < 0 {
          raise Truncated(self.spot(start))
        } else if self.here() == 0x2A && self.peek(self.i + 1) == 0x2F {
          self.i += 2
          closed = true
        } else {
          self.i += 1
        }
      }
    } else {
      going = false
    }
  }
}

///|
fn ends_line(c : Int) -> Bool {
  c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029
}

///|
/// The whitespace ECMAScript 5 recognises (JSON5 §2): the four JSON allows, plus
/// vertical tab, form feed, no-break space, the byte-order mark, the line and
/// paragraph separators, and the Unicode space separators.
fn is_extra_space(c : Int) -> Bool {
  c == 0x0B ||
  c == 0x0C ||
  c == 0xA0 ||
  c == 0xFEFF ||
  c == 0x2028 ||
  c == 0x2029 ||
  c == 0x1680 ||
  (c >= 0x2000 && c <= 0x200A) ||
  c == 0x202F ||
  c == 0x205F ||
  c == 0x3000
}

///|
fn Reader::value(self : Reader, depth : Int) -> Json raise Malformed {
  if depth > depth_limit {
    raise TooDeep(self.spot(self.i))
  }
  match self.here() {
    0x7B => self.object(depth)
    0x5B => self.array(depth)
    0x22 => Json::string(self.text())
    0x27 =>
      if self.flavor.single_quotes {
        Json::string(self.text())
      } else {
        raise self.fail()
      }
    0x74 => {
      self.word("true")
      Json::boolean(true)
    }
    0x66 => {
      self.word("false")
      Json::boolean(false)
    }
    0x6E => {
      self.word("null")
      Json::null()
    }
    _ => self.number()
  }
}

///|
fn Reader::word(self : Reader, want : String) -> Unit raise Malformed {
  let start = self.i
  for k in 0..<want.length() {
    if self.peek(start + k) != want.at(k).to_int() {
      self.i = start + k
      raise self.fail()
    }
  }
  self.i = start + want.length()
}

///|
fn Reader::object(self : Reader, depth : Int) -> Json raise Malformed {
  let out : Map[String, Json] = Map([])
  self.i += 1
  self.space()
  if self.here() == 0x7D {
    self.i += 1
    return Json::object(out)
  }
  let mut open = true
  while open {
    self.space()
    let key = if self.here() == 0x22 ||
      (self.flavor.single_quotes && self.here() == 0x27) {
      self.text()
    } else if self.flavor.unquoted_keys {
      self.name()
    } else {
      raise self.fail()
    }
    self.space()
    if self.here() != 0x3A {
      raise self.fail()
    }
    self.i += 1
    self.space()
    out[key] = self.value(depth + 1)
    self.space()
    match self.here() {
      0x2C => {
        self.i += 1
        self.space()
        if self.here() == 0x7D {
          if !self.flavor.trailing_commas {
            raise self.fail()
          }
          self.i += 1
          open = false
        }
      }
      0x7D => {
        self.i += 1
        open = false
      }
      _ => raise self.fail()
    }
  }
  Json::object(out)
}

///|
fn Reader::array(self : Reader, depth : Int) -> Json raise Malformed {
  let out : Array[Json] = []
  self.i += 1
  self.space()
  if self.here() == 0x5D {
    self.i += 1
    return Json::array(out)
  }
  let mut open = true
  while open {
    self.space()
    out.push(self.value(depth + 1))
    self.space()
    match self.here() {
      0x2C => {
        self.i += 1
        self.space()
        if self.here() == 0x5D {
          if !self.flavor.trailing_commas {
            raise self.fail()
          }
          self.i += 1
          open = false
        }
      }
      0x5D => {
        self.i += 1
        open = false
      }
      _ => raise self.fail()
    }
  }
  Json::array(out)
}

///|
/// An unquoted member name (JSON5 §4): an ECMAScript identifier. `$` and `_`
/// start one, as does any letter; digits may follow.
fn Reader::name(self : Reader) -> String raise Malformed {
  let start = self.i
  while is_name_part(self.here(), self.i == start) {
    self.i += 1
  }
  if self.i == start {
    raise self.fail()
  }
  self.src[start:self.i].to_owned()
}

///|
fn is_name_part(c : Int, first : Bool) -> Bool {
  c == 0x24 ||
  c == 0x5F ||
  (c >= 0x41 && c <= 0x5A) ||
  (c >= 0x61 && c <= 0x7A) ||
  c > 0x7F ||
  (!first && c >= 0x30 && c <= 0x39)
}

///|
fn Reader::text(self : Reader) -> String raise Malformed {
  let quote = self.here()
  let open = self.i
  self.i += 1
  let out = StringBuilder()
  let mut run = self.i
  while self.here() >= 0 {
    let c = self.here()
    if c == quote {
      out.write_view(self.src[run:self.i])
      self.i += 1
      return out.to_string()
    }
    if c == 0x5C {
      out.write_view(self.src[run:self.i])
      self.escape(out)
      run = self.i
      continue
    }
    // RFC 8259 §7: a control character must be written as an escape. JSON5
    // keeps that rule for everything but the line terminators it allows after
    // a backslash, which `escape` handles.
    if c < 0x20 {
      raise self.fail()
    }
    self.i += 1
  }
  raise Truncated(self.spot(open))
}

///|
fn Reader::escape(self : Reader, out : StringBuilder) -> Unit raise Malformed {
  let start = self.i
  self.i += 1
  let c = self.here()
  self.i += 1
  match c {
    0x22 => out.write_char('"')
    0x5C => out.write_char('\\')
    0x2F => out.write_char('/')
    0x62 => out.write_char('\u{08}')
    0x66 => out.write_char('\u{0C}')
    0x6E => out.write_char('\n')
    0x72 => out.write_char('\r')
    0x74 => out.write_char('\t')
    0x75 => out.write_char(self.unicode(start))
    _ => self.loose_escape(out, c, start)
  }
}

///|
fn Reader::loose_escape(
  self : Reader,
  out : StringBuilder,
  c : Int,
  start : Int,
) -> Unit raise Malformed {
  if c < 0 {
    raise Truncated(self.spot(start))
  }
  if !self.flavor.extra_escapes {
    raise BadEscape(self.spot(start))
  }
  match c {
    // A backslash before a line terminator continues the string and adds
    // nothing (JSON5 §5); a CRLF pair counts once.
    0x0A | 0x2028 | 0x2029 => ()
    0x0D => if self.here() == 0x0A { self.i += 1 }
    0x76 => out.write_char('\u{0B}')
    0x78 => out.write_char(self.hex_byte(start))
    0x30 =>
      if self.here() >= 0x30 && self.here() <= 0x39 {
        raise BadEscape(self.spot(start))
      } else {
        out.write_char('\u{00}')
      }
    _ =>
      // A digit after a backslash is a legacy octal escape, which JSON5 does
      // not adopt.
      if c >= 0x31 && c <= 0x39 {
        raise BadEscape(self.spot(start))
      } else {
        out.write_char(c.unsafe_to_char())
      }
  }
}

///|
/// `\uXXXX`, joining a surrogate pair into the one character it stands for.
///
/// A lone half is refused. It is not a character, it cannot be written back
/// out, and every value that could be put in its place is a guess about what
/// the writer meant.
fn Reader::unicode(self : Reader, start : Int) -> Char raise Malformed {
  let hi = self.quad(start)
  if hi < 0xD800 || hi > 0xDFFF {
    return hi.unsafe_to_char()
  }
  if hi >= 0xDC00 {
    raise BadEscape(self.spot(start))
  }
  if self.here() != 0x5C || self.peek(self.i + 1) != 0x75 {
    raise BadEscape(self.spot(start))
  }
  let pair = self.i
  self.i += 2
  let lo = self.quad(pair)
  if lo < 0xDC00 || lo > 0xDFFF {
    raise BadEscape(self.spot(pair))
  }
  (0x10000 + (hi - 0xD800) * 0x400 + (lo - 0xDC00)).unsafe_to_char()
}

///|
fn Reader::quad(self : Reader, start : Int) -> Int raise Malformed {
  let mut v = 0
  for _ in 0..<4 {
    let d = nibble(self.here())
    if d < 0 {
      raise BadEscape(self.spot(start))
    }
    v = (v << 4) | d
    self.i += 1
  }
  v
}

///|
fn Reader::hex_byte(self : Reader, start : Int) -> Char raise Malformed {
  let hi = nibble(self.here())
  let lo = nibble(self.peek(self.i + 1))
  if hi < 0 || lo < 0 {
    raise BadEscape(self.spot(start))
  }
  self.i += 2
  ((hi << 4) | lo).unsafe_to_char()
}

///|
fn nibble(c : Int) -> Int {
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
/// A number, keeping the text it was written as when that text is also valid
/// RFC 8259 — so a twenty-digit integer comes back out unchanged instead of
/// through a double.
fn Reader::number(self : Reader) -> Json raise Malformed {
  let start = self.i
  let mut signed = false
  let mut plain = true
  if self.here() == 0x2D {
    signed = true
    self.i += 1
  } else if self.here() == 0x2B {
    if !self.flavor.extra_numbers {
      raise self.fail()
    }
    self.i += 1
    plain = false
  }
  if self.flavor.extra_numbers {
    if self.here() == 0x49 {
      self.word("Infinity")
      return Json::number(
        if signed {
          @double.neg_infinity
        } else {
          @double.infinity
        },
      )
    }
    if self.here() == 0x4E {
      self.word("NaN")
      return Json::number(@double.not_a_number)
    }
    if self.here() == 0x30 &&
      (self.peek(self.i + 1) == 0x78 || self.peek(self.i + 1) == 0x58) {
      return self.hex_number(start, signed)
    }
  }
  let int_start = self.i
  while self.here() >= 0x30 && self.here() <= 0x39 {
    self.i += 1
  }
  let digits = self.i - int_start
  if digits == 0 {
    // `.5` is a JSON5 number; a bare sign is not a number at all.
    if !(self.flavor.extra_numbers && self.here() == 0x2E) {
      raise self.fail()
    }
    plain = false
  } else if digits > 1 && self.src.at(int_start).to_int() == 0x30 {
    raise BadNumber(self.spot(start))
  }
  let mut fraction = 0
  if self.here() == 0x2E {
    self.i += 1
    let frac = self.i
    while self.here() >= 0x30 && self.here() <= 0x39 {
      self.i += 1
    }
    fraction = self.i - frac
    if fraction == 0 {
      // `5.` is a JSON5 number, and nothing else ends in a bare point.
      if !self.flavor.extra_numbers {
        raise BadNumber(self.spot(start))
      }
      plain = false
    }
  }
  // A lone point, or a sign with nothing after it, is not a number however
  // relaxed the dialect.
  if digits + fraction == 0 {
    raise BadNumber(self.spot(start))
  }
  if self.here() == 0x65 || self.here() == 0x45 {
    self.i += 1
    if self.here() == 0x2B || self.here() == 0x2D {
      self.i += 1
    }
    let exp = self.i
    while self.here() >= 0x30 && self.here() <= 0x39 {
      self.i += 1
    }
    if self.i == exp {
      raise BadNumber(self.spot(start))
    }
  }
  let text = self.src[start:self.i]
  let value = @string.parse_double(text) catch { _ => out_of_range(text) }
  if plain {
    Json::number(value, repr=text.to_owned())
  } else {
    Json::number(value)
  }
}

///|
/// A number the grammar admits but a double cannot hold.
///
/// RFC 8259 §6 sets no limit on a number's magnitude and expects an
/// implementation to say what it does at the edges. This one does what every
/// JavaScript engine does: too large becomes an infinity, too small becomes
/// zero. The text is kept either way, so writing the document back out loses
/// nothing.
fn out_of_range(text : StringView) -> Double {
  let negative = text.at(0).to_int() == 0x2D
  let mut huge = true
  for i in 0..<text.length() {
    let c = text.at(i).to_int()
    if c == 0x65 || c == 0x45 {
      huge = text.at(i + 1).to_int() != 0x2D
      break
    }
    if c == 0x2E {
      // No exponent and a fraction: only a number written as 0.000…1 can be
      // too small, and it is the one whose integer part is a single zero.
      huge = !(i == (if negative { 2 } else { 1 }) &&
        text.at(i - 1).to_int() == 0x30)
      break
    }
  }
  if !huge {
    if negative {
      -0.0
    } else {
      0.0
    }
  } else if negative {
    @double.neg_infinity
  } else {
    @double.infinity
  }
}

///|
/// `0xFF` (JSON5 §4). It carries no `repr`, because the text it was written as
/// is not valid JSON and must not be written back out.
fn Reader::hex_number(
  self : Reader,
  start : Int,
  signed : Bool,
) -> Json raise Malformed {
  self.i += 2
  let from = self.i
  let mut value = 0.0
  while nibble(self.here()) >= 0 {
    value = value * 16.0 + nibble(self.here()).to_double()
    self.i += 1
  }
  if self.i == from {
    raise BadNumber(self.spot(start))
  }
  Json::number(if signed { -value } else { value })
}
