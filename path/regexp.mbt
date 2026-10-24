// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The I-Regexp dialect of RFC 9485, which is what JSONPath's `match` and
/// `search` take: a restricted ECMA-262 — no backreferences, no lookaround, no
/// flags — small enough to be matched by backtracking over code points.
///
/// The tree is parsed once per call. A query that matched with a regular
/// expression per node would parse the same pattern for every node in the
/// document, and a filter runs on all of them.
priv enum Node {
  Empty
  Char(Char)
  Any
  Class(Bool, Array[(Char, Char)])
  Begin
  End
  Then(Array[Node])
  Either(Array[Node])
  Repeat(Node, Int32, Int32)
}

///|
/// The largest number of repetitions a `{n,m}` may ask for. A pattern is a
/// document too, and `a{1000000}` in one is a denial of service.
let repeat_limit : Int32 = 1000

///|
fn pattern_of(pattern : StringView) -> Regexp raise @moonjson.Refused {
  let p : Parser = { src: pattern, i: 0, }
  let node = p.alternation()
  if p.i < pattern.length() {
    raise @moonjson.Syntax(path=pattern.to_owned(), at=p.i)
  }
  { node, }
}

///|
/// A compiled pattern; `matches` is the whole of the string and `finds` any
/// part of it, which is the difference RFC 9535 draws between `match` and
/// `search`.
priv struct Regexp {
  node : Node
}

///|
/// Whether the pattern matches the whole of the text.
pub fn matches(
  pattern : StringView,
  text : StringView,
) -> Bool raise @moonjson.Refused {
  let regexp = pattern_of(pattern)
  run(regexp.node, text, 0, fn(at) { at == text.length() })
}

///|
/// Whether the pattern matches any part of the text.
pub fn finds(
  pattern : StringView,
  text : StringView,
) -> Bool raise @moonjson.Refused {
  let regexp = pattern_of(pattern)
  let mut start = 0
  while start <= text.length() {
    if run(regexp.node, text, start, fn(_) { true }) {
      return true
    }
    start += 1
  }
  false
}

///|
/// Whether the pattern matches from `at` such that the continuation accepts
/// where it ends. Every node answers by trying the continuations it can reach,
/// which is what makes `a|ab` match `ab` when it has to.
fn run(
  node : Node,
  text : StringView,
  at : Int32,
  next : (Int32) -> Bool,
) -> Bool {
  match node {
    Empty => next(at)
    Char(c) =>
      at < text.length() && text.at(at).to_int() == c.to_int() && next(at + 1)
    Any =>
      at < text.length() && !ends_line(text.at(at).to_int()) && next(at + 1)
    Class(negated, ranges) => {
      if at >= text.length() {
        return false
      }
      let c = text.at(at).to_int()
      let mut inside = false
      for range in ranges {
        if c >= range.0.to_int() && c <= range.1.to_int() {
          inside = true
        }
      }
      inside != negated && next(at + 1)
    }
    Begin => at == 0 && next(at)
    End => at == text.length() && next(at)
    Then(nodes) => step(nodes, 0, text, at, next)
    Either(branches) => {
      let mut matched = false
      for branch in branches {
        if run(branch, text, at, next) {
          matched = true
        }
      }
      matched
    }
    Repeat(inner, least, most) => repeat(inner, least, most, 0, text, at, next)
  }
}

///|
fn step(
  nodes : Array[Node],
  index : Int32,
  text : StringView,
  at : Int32,
  next : (Int32) -> Bool,
) -> Bool {
  if index == nodes.length() {
    return next(at)
  }
  run(nodes[index], text, at, fn(end) {
    step(nodes, index + 1, text, end, next)
  })
}

///|
fn repeat(
  inner : Node,
  least : Int32,
  most : Int32,
  count : Int32,
  text : StringView,
  at : Int32,
  next : (Int32) -> Bool,
) -> Bool {
  if count < least {
    // An inner node that matched nothing would repeat forever, so a repeat of
    // an empty match counts as done.
    return run(inner, text, at, fn(end) {
      end != at && repeat(inner, least, most, count + 1, text, end, next)
    })
  }
  if count == most {
    return next(at)
  }
  run(inner, text, at, fn(end) {
    end != at && repeat(inner, least, most, count + 1, text, end, next)
  }) ||
  next(at)
}

///|
fn ends_line(c : Int32) -> Bool {
  c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029
}

///|
/// A cursor over a pattern. A separate struct from the JSONPath parser because
/// the two grammars share only the idea of a position.
priv struct Parser {
  src : StringView
  mut i : Int32
}

///|
fn Parser::here(self : Parser) -> Int32 {
  if self.i < self.src.length() {
    self.src.at(self.i).to_int()
  } else {
    -1
  }
}

///|
fn Parser::eat(self : Parser, c : Int32) -> Bool {
  if self.here() == c {
    self.i += 1
    true
  } else {
    false
  }
}

///|
fn Parser::alternation(self : Parser) -> Node raise @moonjson.Refused {
  let branches : Array[Node] = [self.sequence()]
  while self.eat(0x7C) {
    branches.push(self.sequence())
  }
  if branches.length() == 1 {
    branches[0]
  } else {
    Either(branches)
  }
}

///|
fn Parser::sequence(self : Parser) -> Node raise @moonjson.Refused {
  let items : Array[Node] = []
  while self.here() >= 0 && self.here() != 0x7C && self.here() != 0x29 {
    items.push(self.quantified())
  }
  match items.length() {
    0 => Empty
    1 => items[0]
    _ => Then(items)
  }
}

///|
fn Parser::quantified(self : Parser) -> Node raise @moonjson.Refused {
  let atom = self.atom()
  match self.here() {
    0x2A => {
      self.i += 1
      Repeat(atom, 0, 0x7FFF_FFFF)
    }
    0x2B => {
      self.i += 1
      Repeat(atom, 1, 0x7FFF_FFFF)
    }
    0x3F => {
      self.i += 1
      Repeat(atom, 0, 1)
    }
    0x7B => {
      let save = self.i
      self.i += 1
      let least = self.number()
      if least < 0 {
        self.i = save
        return atom
      }
      let mut most = least
      if self.eat(0x2C) {
        if self.here() == 0x7D {
          most = 0x7FFF_FFFF
        } else {
          most = self.number()
          if most < 0 || most < least {
            raise @moonjson.Syntax(path=self.src.to_owned(), at=self.i)
          }
        }
      }
      if !self.eat(0x7D) || least > repeat_limit || most > repeat_limit {
        raise @moonjson.Syntax(path=self.src.to_owned(), at=self.i)
      }
      Repeat(atom, least, most)
    }
    _ => atom
  }
}

///|
fn Parser::number(self : Parser) -> Int32 {
  let start = self.i
  let mut value = 0
  while self.here() >= 0x30 && self.here() <= 0x39 {
    value = value * 10 + (self.here() - 0x30)
    if value > repeat_limit {
      value = repeat_limit + 1
    }
    self.i += 1
  }
  if self.i == start {
    -1
  } else {
    value
  }
}

///|
fn Parser::atom(self : Parser) -> Node raise @moonjson.Refused {
  let c = self.here()
  match c {
    0x28 => {
      self.i += 1
      // `(?:` is the only group prefix I-Regexp allows; lookahead and the rest
      // are not in the dialect, and accepting one would mean matching with
      // something the specification does not define.
      if self.here() == 0x3F {
        self.i += 1
        if !self.eat(0x3A) {
          raise @moonjson.Syntax(path=self.src.to_owned(), at=self.i)
        }
      }
      let inner = self.alternation()
      if !self.eat(0x29) {
        raise @moonjson.Syntax(path=self.src.to_owned(), at=self.i)
      }
      inner
    }
    0x2E => {
      self.i += 1
      Any
    }
    0x5E => {
      self.i += 1
      Begin
    }
    0x24 => {
      self.i += 1
      End
    }
    0x5B => self.char_class()
    0x5C => self.escape()
    0x2A | 0x2B | 0x3F | 0x7D | 0x7C | 0x29 =>
      raise @moonjson.Syntax(path=self.src.to_owned(), at=self.i)
    _ => {
      self.i += 1
      Char(c.unsafe_to_char())
    }
  }
}

///|
fn Parser::escape(self : Parser) -> Node raise @moonjson.Refused {
  self.i += 1
  let c = self.here()
  self.i += 1
  match c {
    0x64 => Class(false, [('0', '9')]) // \d
    0x44 => Class(true, [('0', '9')]) // \D
    0x73 =>
      Class(false, [
        ('\t', '\r'),
        (' ', ' '),
        ('\u{00a0}', '\u{00a0}'),
        ('\u{2028}', '\u{2029}'),
      ])
    0x53 =>
      Class(true, [
        ('\t', '\r'),
        (' ', ' '),
        ('\u{00a0}', '\u{00a0}'),
        ('\u{2028}', '\u{2029}'),
      ])
    0x77 => // \w
      Class(false, [('0', '9'), ('A', 'Z'), ('_', '_'), ('a', 'z')])
    0x57 => // \W
      Class(true, [('0', '9'), ('A', 'Z'), ('_', '_'), ('a', 'z')])
    0x6E => Char('\n')
    0x72 => Char('\r')
    0x74 => Char('\t')
    -1 => raise @moonjson.Syntax(path=self.src.to_owned(), at=self.i)
    _ => Char(c.unsafe_to_char())
  }
}

///|
fn Parser::char_class(self : Parser) -> Node raise @moonjson.Refused {
  self.i += 1
  let negated = self.eat(0x5E)
  let ranges : Array[(Char, Char)] = []
  let mut first = true
  while first || self.here() != 0x5D {
    if self.here() < 0 {
      raise @moonjson.Syntax(path=self.src.to_owned(), at=self.i)
    }
    first = false
    let low = self.class_char()
    if self.here() == 0x2D && self.src.at(self.i + 1).to_int() != 0x5D {
      self.i += 1
      let high = self.class_char()
      ranges.push((low, high))
    } else {
      ranges.push((low, low))
    }
  }
  self.i += 1
  Class(negated, ranges)
}

///|
fn Parser::class_char(self : Parser) -> Char {
  if self.here() == 0x5C {
    self.i += 1
    let c = self.here()
    self.i += 1
    match c {
      0x6E => '\n'
      0x72 => '\r'
      0x74 => '\t'
      _ => c.unsafe_to_char()
    }
  } else {
    let c = self.here()
    self.i += 1
    c.unsafe_to_char()
  }
}
