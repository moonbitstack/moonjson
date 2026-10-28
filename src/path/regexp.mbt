// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The I-Regexp dialect of RFC 9485, which is what JSONPath's `match` and
/// `search` take: a restricted XSD regular expression — no backreferences, no
/// lookaround, no flags, no multi-character escapes — small enough to be
/// matched by backtracking over code points.
///
/// A pattern is parsed once per call and matched over the characters of the
/// text, not over its UTF-16 code units: `.` is one character, and a character
/// above U+FFFF is one too. Matching code units would make `a.b` fail on a
/// document that holds `a𐄁b`.
priv enum Node {
  Empty
  Char(Int32)
  Any
  Class(Bool, Array[(Int32, Int32)], Int32)
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
/// A compiled pattern; `matches` is the whole of the string and `finds` any
/// part of it, which is the difference RFC 9535 draws between `match` and
/// `search`.
priv struct Regexp {
  node : Node
}

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
/// Whether the pattern matches the whole of the text.
///
/// The dialect is I-Regexp (RFC 9485): `.`, the classes `[...]`, `\p{...}` for
/// the Unicode general categories, the four quantifiers, alternation and
/// groups. `\d`, `\w` and `\s` and their negations are accepted as well, which
/// I-Regexp itself leaves out; they are what a pattern written for another
/// dialect reaches for first, and refusing them would be a surprise rather
/// than a service.
pub fn matches(
  pattern : StringView,
  text : StringView,
) -> Bool raise @moonjson.Refused {
  let regexp = pattern_of(pattern)
  let chars = text.to_array()
  let end = chars.length()
  run(regexp.node, chars, 0, fn(k) { k == end })
}

///|
/// Whether the pattern matches any part of the text.
pub fn finds(
  pattern : StringView,
  text : StringView,
) -> Bool raise @moonjson.Refused {
  let regexp = pattern_of(pattern)
  let chars = text.to_array()
  let mut start = 0
  while start <= chars.length() {
    if run(regexp.node, chars, start, fn(_) { true }) {
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
  chars : Array[Char],
  at : Int32,
  next : (Int32) -> Bool,
) -> Bool {
  match node {
    Empty => next(at)
    Char(c) => at < chars.length() && chars[at].to_int() == c && next(at + 1)
    Any =>
      at < chars.length() && !is_line_end(chars[at].to_int()) && next(at + 1)
    Class(negated, ranges, mask) => {
      if at >= chars.length() {
        return false
      }
      let c = chars[at].to_int()
      let mut inside = mask != 0 && (mask & (1 << category_of(c))) != 0
      if !inside {
        for range in ranges {
          if c >= range.0 && c <= range.1 {
            inside = true
          }
        }
      }
      inside != negated && next(at + 1)
    }
    Begin => at == 0 && next(at)
    End => at == chars.length() && next(at)
    Then(nodes) => step(nodes, 0, chars, at, next)
    Either(branches) => {
      let mut matched = false
      for branch in branches {
        if run(branch, chars, at, next) {
          matched = true
        }
      }
      matched
    }
    Repeat(inner, least, most) => repeat(inner, least, most, 0, chars, at, next)
  }
}

///|
fn step(
  nodes : Array[Node],
  index : Int32,
  chars : Array[Char],
  at : Int32,
  next : (Int32) -> Bool,
) -> Bool {
  if index == nodes.length() {
    return next(at)
  }
  run(nodes[index], chars, at, fn(end) {
    step(nodes, index + 1, chars, end, next)
  })
}

///|
fn repeat(
  inner : Node,
  least : Int32,
  most : Int32,
  count : Int32,
  chars : Array[Char],
  at : Int32,
  next : (Int32) -> Bool,
) -> Bool {
  if count < least {
    // An inner node that matched nothing would repeat forever, so a repeat of
    // an empty match counts as done.
    return run(inner, chars, at, fn(end) {
      end != at && repeat(inner, least, most, count + 1, chars, end, next)
    })
  }
  if count == most {
    return next(at)
  }
  run(inner, chars, at, fn(end) {
    end != at && repeat(inner, least, most, count + 1, chars, end, next)
  }) ||
  next(at)
}

///|
/// The two characters `.` does not match. XSD's dot — and I-Regexp is a subset
/// of XSD — excludes the line feed and the carriage return, and nothing else:
/// U+2028 and U+2029 are ordinary characters here, which is the one place this
/// differs from ECMAScript.
fn is_line_end(c : Int32) -> Bool {
  c == 0x0A || c == 0x0D
}

// The general categories, one bit each, in the order `category.mbt` numbers
// them. A pattern names one with `\p{...}`, and a class may hold several.

///|
let lu : Int32 = 1 << 0

///|
let ll : Int32 = 1 << 1

///|
let lt : Int32 = 1 << 2

///|
let lm : Int32 = 1 << 3

///|
let lo : Int32 = 1 << 4

///|
let mn : Int32 = 1 << 5

///|
let mc : Int32 = 1 << 6

///|
let me : Int32 = 1 << 7

///|
let nd : Int32 = 1 << 8

///|
let nl : Int32 = 1 << 9

///|
let no : Int32 = 1 << 10

///|
let pc : Int32 = 1 << 11

///|
let pd : Int32 = 1 << 12

///|
let ps : Int32 = 1 << 13

///|
let pe : Int32 = 1 << 14

///|
let pi : Int32 = 1 << 15

///|
let pf : Int32 = 1 << 16

///|
let po : Int32 = 1 << 17

///|
let sm : Int32 = 1 << 18

///|
let sc : Int32 = 1 << 19

///|
let sk : Int32 = 1 << 20

///|
let so : Int32 = 1 << 21

///|
let zs : Int32 = 1 << 22

///|
let zl : Int32 = 1 << 23

///|
let zp : Int32 = 1 << 24

///|
let cc : Int32 = 1 << 25

///|
let cf : Int32 = 1 << 26

///|
let co : Int32 = 1 << 27

///|
let cs : Int32 = 1 << 28

///|
let cn : Int32 = 1 << 29

///|
/// Every category, which is what the complement of a `\P{...}` in a class is.
let every : Int32 = (1 << 30) - 1

///|
/// The category a code point has, looked up in the table: a code point in no
/// range of it is unassigned, which is `Cn`.
fn category_of(c : Int32) -> Int32 {
  let mut low = 0
  let mut high = ranges.length() - 1
  while low <= high {
    let mid = (low + high) / 2
    let (from, to, id) = ranges[mid]
    if c < from {
      high = mid - 1
    } else if c > to {
      low = mid + 1
    } else {
      return id
    }
  }
  cn_id
}

///|
/// The number `Cn` has in the table, which is the last one.
let cn_id : Int32 = 29

///|
/// The categories a `\p{...}` names, as a mask, or `None` when the name is not
/// one the grammar allows. Only the general categories exist in I-Regexp: no
/// scripts, no blocks, no binary properties.
fn category_mask(name : StringView) -> Int32? {
  match name {
    "L" => Some(lu | ll | lt | lm | lo)
    "M" => Some(mn | mc | me)
    "N" => Some(nd | nl | no)
    "P" => Some(pc | pd | ps | pe | pi | pf | po)
    "S" => Some(sm | sc | sk | so)
    "Z" => Some(zs | zl | zp)
    "C" => Some(cc | cf | co | cs | cn)
    "Lu" => Some(lu)
    "Ll" => Some(ll)
    "Lt" => Some(lt)
    "Lm" => Some(lm)
    "Lo" => Some(lo)
    "Mn" => Some(mn)
    "Mc" => Some(mc)
    "Me" => Some(me)
    "Nd" => Some(nd)
    "Nl" => Some(nl)
    "No" => Some(no)
    "Pc" => Some(pc)
    "Pd" => Some(pd)
    "Ps" => Some(ps)
    "Pe" => Some(pe)
    "Pi" => Some(pi)
    "Pf" => Some(pf)
    "Po" => Some(po)
    "Sm" => Some(sm)
    "Sc" => Some(sc)
    "Sk" => Some(sk)
    "So" => Some(so)
    "Zs" => Some(zs)
    "Zl" => Some(zl)
    "Zp" => Some(zp)
    "Cc" => Some(cc)
    "Cf" => Some(cf)
    "Co" => Some(co)
    "Cs" => Some(cs)
    "Cn" => Some(cn)
    _ => None
  }
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
fn Parser::peek(self : Parser, k : Int32) -> Int32 {
  let at = self.i + k
  if at < self.src.length() {
    self.src.at(at).to_int()
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
fn Parser::fail(self : Parser) -> @moonjson.Refused {
  @moonjson.Syntax(path=self.src.to_owned(), at=self.i)
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
            raise self.fail()
          }
        }
      }
      if !self.eat(0x7D) || least > repeat_limit || most > repeat_limit {
        raise self.fail()
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
          raise self.fail()
        }
      }
      let inner = self.alternation()
      if !self.eat(0x29) {
        raise self.fail()
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
    0x2A | 0x2B | 0x3F | 0x7D | 0x7C | 0x29 | -1 => raise self.fail()
    _ => {
      self.i += 1
      Char(c)
    }
  }
}

///|
fn Parser::escape(self : Parser) -> Node raise @moonjson.Refused {
  self.i += 1
  let c = self.here()
  self.i += 1
  match c {
    0x70 | 0x50 => {
      let (negated, mask) = self.category()
      Class(negated, [], mask)
    }
    0x64 => Class(false, [(0x30, 0x39)], 0) // \d
    0x44 => Class(true, [(0x30, 0x39)], 0) // \D
    0x73 =>
      Class(
        false,
        [(0x09, 0x0D), (0x20, 0x20), (0xA0, 0xA0), (0x2028, 0x2029)],
        0,
      )
    0x53 =>
      Class(
        true,
        [(0x09, 0x0D), (0x20, 0x20), (0xA0, 0xA0), (0x2028, 0x2029)],
        0,
      )
    0x77 =>
      Class(false, [(0x30, 0x39), (0x41, 0x5A), (0x5F, 0x5F), (0x61, 0x7A)], 0)
    0x57 =>
      Class(true, [(0x30, 0x39), (0x41, 0x5A), (0x5F, 0x5F), (0x61, 0x7A)], 0)
    _ => {
      let single = match c {
        0x6E => 0x0A // \n
        0x72 => 0x0D // \r
        0x74 => 0x09 // \t
        _ => c
      }
      // SingleCharEsc is a closed set: the punctuation that would otherwise be
      // a metacharacter, and n, r and t. Anything else is not this dialect.
      let allowed = single == 0x6E ||
        single == 0x72 ||
        single == 0x74 ||
        (single >= 0x28 && single <= 0x2B) ||
        single == 0x2D ||
        single == 0x2E ||
        single == 0x3F ||
        (single >= 0x5B && single <= 0x5E) ||
        (single >= 0x7B && single <= 0x7D)
      if !allowed {
        raise self.fail()
      }
      Char(single)
    }
  }
}

///|
/// The body of a `\p{...}` or `\P{...}`, with the `p` or `P` already consumed.
fn Parser::category(self : Parser) -> (Bool, Int32) raise @moonjson.Refused {
  let negated = self.src.at(self.i - 1).to_int() == 0x50
  if !self.eat(0x7B) {
    raise self.fail()
  }
  let start = self.i
  while (self.here() >= 0x41 && self.here() <= 0x5A) ||
        (self.here() >= 0x61 && self.here() <= 0x7A) {
    self.i += 1
  }
  let name = self.src[start:self.i]
  if !self.eat(0x7D) {
    raise self.fail()
  }
  match category_mask(name) {
    Some(mask) => (negated, mask)
    None => raise self.fail()
  }
}

///|
fn Parser::char_class(self : Parser) -> Node raise @moonjson.Refused {
  self.i += 1
  let negated = self.eat(0x5E)
  let ranges : Array[(Int32, Int32)] = []
  let mut mask = 0
  let mut members = 0
  while self.here() != 0x5D {
    if self.here() < 0 {
      raise self.fail()
    }
    if self.here() == 0x5C && (self.peek(1) == 0x70 || self.peek(1) == 0x50) {
      self.i += 2
      let (complement, named) = self.category()
      mask = mask | (if complement { every ^ named } else { named })
      members += 1
      continue
    }
    let low = self.class_char()
    if self.here() == 0x2D && self.peek(1) != 0x5D {
      self.i += 1
      let high = self.class_char()
      if high < low {
        raise self.fail()
      }
      ranges.push((low, high))
    } else {
      ranges.push((low, low))
    }
    members += 1
  }
  // `[]` and `[^]` are not character classes: a class has at least one member.
  if members == 0 {
    raise self.fail()
  }
  self.i += 1
  Class(negated, ranges, mask)
}

///|
/// One character of a class, as a code point. `\d`, `\w` and `\s` are not
/// members of a class in this dialect, because a class holds characters rather
/// than the sets they stand for; `\p{Nd}` is where the digits of every script
/// are meant.
fn Parser::class_char(self : Parser) -> Int32 raise @moonjson.Refused {
  if self.here() == 0x5C {
    self.i += 1
    let c = self.here()
    self.i += 1
    match c {
      0x6E => 0x0A
      0x72 => 0x0D
      0x74 => 0x09
      0x2D | 0x2E | 0x5B | 0x5C | 0x5D | 0x5E => c
      _ => raise self.fail()
    }
  } else {
    let c = self.here()
    if c < 0 {
      raise self.fail()
    }
    self.i += 1
    c
  }
}
