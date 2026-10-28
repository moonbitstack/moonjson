// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One way of choosing from a node.
pub(all) enum Selector {
  /// A member with this name, or nothing.
  Name(String)
  /// An element at this index, or nothing.
  ///
  /// An index is an I-JSON integer, which RFC 9535 §2.3.3 puts at
  /// ±(2^53 − 1) — wider than `Int32`, and wider than any array that can
  /// exist, which is why an index past the end selects nothing rather than
  /// being refused.
  Index(Int64)
  /// Every element of an array, or every member of an object.
  Wildcard
  /// A range of an array. `None` means "from the beginning", "to the end", or
  /// "by one" — the three defaults RFC 9535 §2.3.4.2 gives the three parts.
  Slice(start~ : Int64?, end~ : Int64?, step~ : Int64?)
  /// The nodes for which the expression holds.
  Filter(Test)
}

///|
/// One step of a query.
pub(all) enum Segment {
  /// The selectors applied to the node itself.
  Child(Array[Selector])
  /// The selectors applied to the node and to every node inside it, in
  /// document order — the `..` segment.
  Descendant(Array[Selector])
}

///|
/// A comparable operator.
pub(all) enum Op {
  /// Equal.
  Eq
  /// Not equal.
  Ne
  /// Less than.
  Lt
  /// Less than or equal.
  Le
  /// Greater than.
  Gt
  /// Greater than or equal.
  Ge
} derive(Eq, Debug)

///|
pub extend Op with Eq::{equal, not_equal}

///|
pub extend Op with Debug::{to_repr}

///|
/// One side of a comparison, or the thing a test asks about.
pub(all) enum Operand {
  /// A literal written in the query.
  Const(Json)
  /// A query: `@` for the node under test, `$` for the document.
  Nodes(root~ : Bool, segments~ : Array[Segment])
  /// One of the five functions RFC 9535 §2.4 defines.
  Call(name~ : String, args~ : Array[Operand])
}

///|
/// What a filter asks.
pub(all) enum Test {
  /// Either side holds.
  Or(Test, Test)
  /// Both sides hold.
  And(Test, Test)
  /// The test does not hold.
  Not(Test)
  /// Whether the query selects anything at all.
  Exists(Operand)
  /// Whether two values compare as the operator says.
  Compare(Operand, Op, Operand)
}

///|
/// A compiled query.
pub(all) struct Path {
  /// The segments, from the first to the last.
  segments : Array[Segment]
}

///|
/// Run a query against a document, answering the nodes it selects in document
/// order.
pub fn select(
  doc : Json,
  query : StringView,
) -> Array[Json] raise @moonjson.Refused {
  compile(query).select(doc)
}

///|
/// Run a compiled query against a document, answering the nodes it selects in
/// document order. The same `Path` can be run against as many documents as you
/// like, which is the reason to compile one.
pub fn Path::select(self : Path, doc : Json) -> Array[Json] {
  let mut nodes : Array[Json] = [doc]
  for segment in self.segments {
    nodes = apply(nodes, segment, doc)
  }
  nodes
}

///|
fn apply(nodes : Array[Json], segment : Segment, root : Json) -> Array[Json] {
  let out : Array[Json] = []
  match segment {
    Child(selectors) =>
      for node in nodes {
        pick(out, node, selectors, root)
      }
    Descendant(selectors) =>
      for node in nodes {
        let all : Array[Json] = []
        descend(node, all)
        for each in all {
          pick(out, each, selectors, root)
        }
      }
  }
  out
}

///|
/// The node and everything inside it, in the order a document is read.
fn descend(node : Json, out : Array[Json]) -> Unit {
  out.push(node)
  match node {
    Array(items) =>
      for item in items {
        descend(item, out)
      }
    Object(members) =>
      for _, held in members {
        descend(held, out)
      }
    _ => ()
  }
}

///|
fn pick(
  out : Array[Json],
  node : Json,
  selectors : Array[Selector],
  root : Json,
) -> Unit {
  for selector in selectors {
    choose(out, node, selector, root)
  }
}

///|
fn choose(
  out : Array[Json],
  node : Json,
  selector : Selector,
  root : Json,
) -> Unit {
  match selector {
    Name(name) =>
      if node is Object(members) {
        if members.get(name) is Some(found) {
          out.push(found)
        }
      }
    Index(index) =>
      if node is Array(items) {
        let length = items.length().to_int64()
        let at = if index < 0L { length + index } else { index }
        if at >= 0L && at < length {
          out.push(items[at.to_int()])
        }
      }
    Wildcard =>
      match node {
        Array(items) =>
          for item in items {
            out.push(item)
          }
        Object(members) =>
          for _, held in members {
            out.push(held)
          }
        _ => ()
      }
    Slice(start~, end~, step~) =>
      if node is Array(items) {
        slice(out, items, start, end, step)
      }
    Filter(check) =>
      match node {
        Array(items) =>
          for item in items {
            if holds(check, item, root) {
              out.push(item)
            }
          }
        Object(members) =>
          for _, held in members {
            if holds(check, held, root) {
              out.push(held)
            }
          }
        _ => ()
      }
  }
}

///|
/// RFC 9535 §2.3.4.2: a slice counts from either end, a step of zero selects
/// nothing rather than running away, and every part is clamped to the array
/// before the walk begins.
fn slice(
  out : Array[Json],
  items : Array[Json],
  start : Int64?,
  end : Int64?,
  step : Int64?,
) -> Unit {
  let length = items.length().to_int64()
  let by = match step {
    Some(n) => n
    None => 1L
  }
  if by == 0L {
    return
  }
  let count = fn(n : Int64) { if n < 0L { n + length } else { n } }
  if by > 0L {
    let lower = clamp(
      match start {
        Some(n) => count(n)
        None => 0L
      },
      0L,
      length,
    )
    let upper = clamp(
      match end {
        Some(n) => count(n)
        None => length
      },
      0L,
      length,
    )
    let mut i = lower
    while i < upper {
      out.push(items[i.to_int()])
      i += by
    }
  } else {
    let upper = clamp(
      match start {
        Some(n) => count(n)
        None => length - 1L
      },
      -1L,
      length - 1L,
    )
    // A missing end is the one value that stays -1: it is "before the first
    // element", not "one before the last" counted from the end of the array.
    let lower = clamp(
      match end {
        Some(n) => count(n)
        None => -1L
      },
      -1L,
      length - 1L,
    )
    let mut i = upper
    while lower < i {
      out.push(items[i.to_int()])
      i += by
    }
  }
}

///|
fn clamp(value : Int64, least : Int64, most : Int64) -> Int64 {
  if value < least {
    least
  } else if value > most {
    most
  } else {
    value
  }
}

///|
/// Whether a filter holds for a node. The name is not `test` because that
/// word is a keyword.
fn holds(check : Test, node : Json, root : Json) -> Bool {
  match check {
    Or(left, right) => holds(left, node, root) || holds(right, node, root)
    And(left, right) => holds(left, node, root) && holds(right, node, root)
    Not(inner) => !holds(inner, node, root)
    Exists(operand) => exists(operand, node, root)
    Compare(left, op, right) => {
      let a = value_of(left, node, root)
      let b = value_of(right, node, root)
      compare(a, op, b)
    }
  }
}

///|
/// Whether an operand selects anything. A function that answers yes or no is a
/// test in its own right — `$[?match(@.a, "x")]` asks whether the pattern
/// matched, not whether it selected a node — so its answer is the answer.
fn exists(operand : Operand, node : Json, root : Json) -> Bool {
  match operand {
    Call(..) =>
      match value_of(operand, node, root) {
        Some(True) => true
        _ => false
      }
    Const(_) => false
    Nodes(..) => nodes_of(operand, node, root).length() > 0
  }
}

///|
/// The nodes an operand selects. A literal is not a node, so it selects
/// nothing — which is what makes `@.a == 1` a comparison and `@.a` an
/// existence test.
fn nodes_of(operand : Operand, node : Json, doc_root : Json) -> Array[Json] {
  match operand {
    Nodes(root~, segments~) => {
      let mut nodes : Array[Json] = [if root { doc_root } else { node }]
      for segment in segments {
        nodes = apply(nodes, segment, doc_root)
      }
      nodes
    }
    _ => []
  }
}

///|
/// The value an operand stands for, when it stands for exactly one.
fn value_of(operand : Operand, node : Json, root : Json) -> Json? {
  match operand {
    Const(value) => Some(value)
    Nodes(..) => {
      let found = nodes_of(operand, node, root)
      if found.length() == 1 {
        Some(found[0])
      } else {
        None
      }
    }
    Call(name~, args~) =>
      match name {
        "length" =>
          match single(args, node, root) {
            // A string's length is its number of characters, which is not its
            // number of UTF-16 code units: `"😀"` is one character and two of
            // them.
            Some(String(s)) => Some(Json::number(characters(s).to_double()))
            Some(Array(items)) => Some(Json::number(items.length().to_double()))
            Some(Object(members)) =>
              Some(Json::number(members.length().to_double()))
            _ => None
          }
        "count" =>
          if args.length() == 1 {
            Some(
              Json::number(nodes_of(args[0], node, root).length().to_double()),
            )
          } else {
            None
          }
        "value" =>
          if args.length() == 1 {
            let found = nodes_of(args[0], node, root)
            if found.length() == 1 {
              Some(found[0])
            } else {
              None
            }
          } else {
            None
          }
        "match" => boolean_call(true, args, node, root)
        "search" => boolean_call(false, args, node, root)
        _ => None
      }
  }
}

///|
/// How many characters a string holds. RFC 9535 §2.4.4 counts Unicode scalar
/// values, and a code unit above U+FFFF is only half of one.
fn characters(text : StringView) -> Int32 {
  let mut count = 0
  for _ in text {
    count += 1
  }
  count
}

///|
fn single(operand : Array[Operand], node : Json, root : Json) -> Json? {
  if operand.length() != 1 {
    return None
  }
  value_of(operand[0], node, root)
}

///|
fn boolean_call(
  whole : Bool,
  args : Array[Operand],
  node : Json,
  root : Json,
) -> Json? {
  if args.length() != 2 {
    return None
  }
  let subject = value_of(args[0], node, root)
  let pattern = value_of(args[1], node, root)
  match (subject, pattern) {
    (Some(String(text)), Some(String(re))) => {
      let found = if whole {
        matches(re[:], text[:]) catch {
          _ => return None
        }
      } else {
        finds(re[:], text[:]) catch {
          _ => return None
        }
      }
      Some(Json::boolean(found))
    }
    _ => None
  }
}

///|
/// Comparisons, as RFC 9535 §2.3.5.2.2 defines them: two empty nodelists are
/// equal to each other and to nothing else, two values of different types are
/// unequal, order exists only between two numbers or two strings, and `<=` is
/// "less than or equal" rather than "has an order" — `null <= null` is true
/// because `null == null` is.
fn compare(a : Json?, op : Op, b : Json?) -> Bool {
  match (a, b) {
    (None, None) => op == Eq
    (Some(left), Some(right)) =>
      match op {
        Eq => alike(left, right)
        Ne => !alike(left, right)
        Lt => less(left, right)
        Le => less(left, right) || alike(left, right)
        Gt => less(right, left)
        Ge => less(right, left) || alike(left, right)
      }
    _ => op == Ne
  }
}

///|
/// Whether one value is ordered before another. Only two numbers and two
/// strings are ordered at all; `1 < "2"` is not false, it is not a comparison.
fn less(a : Json, b : Json) -> Bool {
  match order(a, b) {
    Some(d) => d < 0
    None => false
  }
}

///|
/// Equality of values: numbers by value — `1` and `1.0` are one number — and
/// everything else structurally.
pub fn alike(a : Json, b : Json) -> Bool {
  match (a, b) {
    (Null, Null) | (True, True) | (False, False) => true
    (Number(x, ..), Number(y, ..)) => x == y
    (String(x), String(y)) => x == y
    (Array(x), Array(y)) => {
      if x.length() != y.length() {
        return false
      }
      for i in 0..<x.length() {
        if !alike(x[i], y[i]) {
          return false
        }
      }
      true
    }
    (Object(x), Object(y)) => {
      if x.length() != y.length() {
        return false
      }
      for name, held in x {
        match y.get(name) {
          Some(other) => if !alike(held, other) { return false }
          None => return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// The order of two values, when they have one. Only numbers and strings do;
/// `1 < "2"` is not false, it is not a comparison at all.
fn order(a : Json, b : Json) -> Int32? {
  match (a, b) {
    (Number(x, ..), Number(y, ..)) =>
      Some(if x < y { -1 } else if x > y { 1 } else { 0 })
    (String(x), String(y)) => Some(compare_text(x[:], y[:]))
    _ => None
  }
}

///|
/// RFC 9535 §2.3.5.2.2: strings compare by code point, which is not what this
/// machine's `String` comparison does at the edges.
fn compare_text(a : StringView, b : StringView) -> Int32 {
  let left = a.to_array()
  let right = b.to_array()
  let mut i = 0
  while i < left.length() && i < right.length() {
    let x = left[i].to_int()
    let y = right[i].to_int()
    if x != y {
      return x - y
    }
    i += 1
  }
  left.length() - right.length()
}

// The parser.
//
// The grammar is RFC 9535 §2.2's and the types are §2.4.3's. Two of the
// specification's rules are not about syntax at all, and both are decided here
// rather than at run time: a query used where a value is expected must be
// *singular* — one name or index selector to a segment, no wildcard, slice,
// filter or descendant — and a function that answers a logical value is a test
// of its own, while one that answers a value has to be compared. A query that
// breaks either rule is not a query, and is refused with the offset it stopped
// at rather than run as something else.

///|
/// What an expression stands for, which is what decides where it may appear.
priv enum Kind {
  /// A boolean: a comparison, or a function that answers one.
  Logical
  /// A value: a literal, a singular query, or a function that answers one.
  Value
  /// A nodelist.
  Nodelist
}

///|
priv struct Item {
  kind : Kind
  operand : Operand
  /// Whether a nodes operand names at most one node, which is what lets it
  /// stand where a value is expected.
  singular : Bool
}

///|
/// A cursor over a query.
priv struct QParser {
  src : StringView
  mut i : Int32
}

///|
fn Path::new(segments~ : Array[Segment]) -> Path {
  { segments, }
}

///|
fn QParser::here(self : QParser) -> Int32 {
  if self.i < self.src.length() {
    self.src.at(self.i).to_int()
  } else {
    -1
  }
}

///|
fn QParser::peek(self : QParser, k : Int32) -> Int32 {
  let at = self.i + k
  if at < self.src.length() {
    self.src.at(at).to_int()
  } else {
    -1
  }
}

///|
fn QParser::eat(self : QParser, c : Int32) -> Bool {
  if self.here() == c {
    self.i += 1
    true
  } else {
    false
  }
}

///|
fn QParser::fail(self : QParser) -> @moonjson.Refused {
  @moonjson.Syntax(path=self.src.to_owned(), at=self.i)
}

///|
fn QParser::space(self : QParser) -> Unit {
  while is_space(self.here()) {
    self.i += 1
  }
}

///|
fn is_space(c : Int32) -> Bool {
  c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
}

///|
/// Compile a query.
///
/// The grammar is RFC 9535 §2.2's, and a query that does not parse is refused
/// with the offset it stopped at rather than run as something else. Nothing
/// around the query is whitespace: `" $"` and `"$ "` are not queries.
pub fn compile(query : StringView) -> Path raise @moonjson.Refused {
  let p : QParser = { src: query, i: 0, }
  if !p.eat(0x24) {
    raise p.fail()
  }
  let segments = p.segments(false)
  if p.i < query.length() {
    raise p.fail()
  }
  Path::new(segments~)
}

///|
/// The segments after a `$` or an `@`. `stop` says what to do at the first
/// thing that is not a segment: in a filter that is the end of the query and
/// the caller's operator follows, while at the top it is an error.
///
/// Whitespace comes before a segment and never after the last one, which is
/// what makes `$.. a` two tokens where the grammar has one.
fn QParser::segments(
  self : QParser,
  stop : Bool,
) -> Array[Segment] raise @moonjson.Refused {
  let out : Array[Segment] = []
  while true {
    if self.i >= self.src.length() {
      return out
    }
    let save = self.i
    self.space()
    let c = self.here()
    if c == 0x5B {
      self.i += 1
      out.push(Child(self.selection()))
    } else if c == 0x2E {
      self.i += 1
      if self.eat(0x2E) {
        out.push(Descendant(self.descendant_selection()))
      } else if self.eat(0x2A) {
        out.push(Child([Wildcard]))
      } else {
        out.push(Child([Name(self.shorthand())]))
      }
    } else if stop {
      self.i = save
      return out
    } else {
      raise self.fail()
    }
  } nobreak {
    out
  }
}

///|
fn QParser::descendant_selection(
  self : QParser,
) -> Array[Selector] raise @moonjson.Refused {
  if self.eat(0x5B) {
    self.selection()
  } else if self.eat(0x2A) {
    [Wildcard]
  } else {
    [Name(self.shorthand())]
  }
}

///|
fn QParser::shorthand(self : QParser) -> String raise @moonjson.Refused {
  let start = self.i
  while is_name_char(self.here(), self.i == start) {
    self.i += 1
  }
  if self.i == start {
    raise self.fail()
  }
  self.src[start:self.i].to_owned()
}

///|
/// A member-name shorthand is an identifier: a letter or `_`, then letters,
/// digits and `_`. RFC 9535 §2.5.1 makes `name-first` any code point from
/// U+0080 up, so `$.☺` and `$.😀` name members as well as `$.a` does.
fn is_name_char(c : Int32, first : Bool) -> Bool {
  c == 0x5F ||
  (c >= 0x41 && c <= 0x5A) ||
  (c >= 0x61 && c <= 0x7A) ||
  c > 0x7F ||
  (!first && c >= 0x30 && c <= 0x39)
}

///|
/// The selectors of a bracketed selection, with the `[` already eaten.
fn QParser::selection(
  self : QParser,
) -> Array[Selector] raise @moonjson.Refused {
  let out : Array[Selector] = []
  while true {
    self.space()
    out.push(self.selector())
    self.space()
    if self.eat(0x2C) {
      continue
    }
    if self.eat(0x5D) {
      return out
    }
    raise self.fail()
  } nobreak {
    out
  }
}

///|
fn QParser::selector(self : QParser) -> Selector raise @moonjson.Refused {
  match self.here() {
    0x22 | 0x27 => Name(self.string())
    0x2A => {
      self.i += 1
      Wildcard
    }
    0x3F => {
      self.i += 1
      self.space()
      Filter(self.or_expr())
    }
    0x3A => self.slice(None)
    _ =>
      if self.here() == 0x2D || (self.here() >= 0x30 && self.here() <= 0x39) {
        let value = self.integer()
        self.space()
        if self.here() == 0x3A {
          self.slice(Some(value))
        } else {
          Index(value)
        }
      } else {
        raise self.fail()
      }
  }
}

///|
/// A slice whose first part may already have been read.
fn QParser::slice(
  self : QParser,
  from : Int64?,
) -> Selector raise @moonjson.Refused {
  if !self.eat(0x3A) {
    raise self.fail()
  }
  self.space()
  let to = if self.starts_int() { Some(self.integer()) } else { None }
  self.space()
  let by = if self.eat(0x3A) {
    self.space()
    if self.starts_int() {
      Some(self.integer())
    } else {
      None
    }
  } else {
    None
  }
  Slice(start=from, end=to, step=by)
}

///|
fn QParser::starts_int(self : QParser) -> Bool {
  self.here() == 0x2D || (self.here() >= 0x30 && self.here() <= 0x39)
}

///|
/// The I-JSON bound RFC 9535 §2.3.3 puts on an index and §2.3.4 on each part of
/// a slice: 2^53 − 1, the largest integer a double holds exactly.
let exact : Int64 = 9007199254740991L

///|
/// An integer: no leading zero, no `-0`, and within the I-JSON bound. Anything
/// else is not an integer the specification defines, so the selector is not
/// one either.
fn QParser::integer(self : QParser) -> Int64 raise @moonjson.Refused {
  let negative = self.eat(0x2D)
  let start = self.i
  let mut value = 0L
  while self.here() >= 0x30 && self.here() <= 0x39 {
    value = value * 10L + (self.here() - 0x30).to_int64()
    if value > exact {
      raise self.fail()
    }
    self.i += 1
  }
  if self.i == start {
    raise self.fail()
  }
  if self.i - start > 1 && self.src.at(start).to_int() == 0x30 {
    raise self.fail()
  }
  if negative {
    if value == 0L {
      raise self.fail()
    }
    -value
  } else {
    value
  }
}

///|
/// A string literal: a JSON string in either quote, with the escapes the
/// grammar allows for *that* quote — `\'` inside double quotes and `\"` inside
/// single quotes are both refused, because neither is in `escapable`. An
/// unescaped control character is refused too, and so is half of a surrogate
/// pair, which is not a character.
fn QParser::string(self : QParser) -> String raise @moonjson.Refused {
  let quote = self.here()
  self.i += 1
  let out = StringBuilder()
  while true {
    let c = self.here()
    if c < 0 {
      raise self.fail()
    }
    if c == quote {
      self.i += 1
      return out.to_string()
    }
    if c == 0x5C {
      self.i += 1
      let e = self.here()
      self.i += 1
      match e {
        0x62 => out.write_char('\u{08}')
        0x66 => out.write_char('\u{0C}')
        0x6E => out.write_char('\n')
        0x72 => out.write_char('\r')
        0x74 => out.write_char('\t')
        0x2F => out.write_char('/')
        0x5C => out.write_char('\\')
        0x75 => out.write_char(self.codepoint())
        _ =>
          if e == quote {
            out.write_char(e.unsafe_to_char())
          } else {
            raise self.fail()
          }
      }
    } else if c < 0x20 {
      raise self.fail()
    } else {
      self.i += 1
      out.write_char(c.unsafe_to_char())
    }
  }
  out.to_string()
}

///|
/// `\uXXXX`, joining a surrogate pair into the character it stands for. A lone
/// half is not a character and is refused.
fn QParser::codepoint(self : QParser) -> Char raise @moonjson.Refused {
  let hi = self.quad()
  if hi < 0xD800 || hi > 0xDFFF {
    return hi.unsafe_to_char()
  }
  if hi >= 0xDC00 {
    raise self.fail()
  }
  if self.here() != 0x5C || self.peek(1) != 0x75 {
    raise self.fail()
  }
  self.i += 2
  let lo = self.quad()
  if lo < 0xDC00 || lo > 0xDFFF {
    raise self.fail()
  }
  (0x10000 + (hi - 0xD800) * 0x400 + (lo - 0xDC00)).unsafe_to_char()
}

///|
fn QParser::quad(self : QParser) -> Int32 raise @moonjson.Refused {
  let mut value = 0
  for _ in 0..<4 {
    let digit = nibble(self.here())
    if digit < 0 {
      raise self.fail()
    }
    value = value * 16 + digit
    self.i += 1
  }
  value
}

///|
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
fn QParser::or_expr(self : QParser) -> Test raise @moonjson.Refused {
  let mut check = self.and_expr()
  while true {
    self.space()
    if self.here() == 0x7C && self.peek(1) == 0x7C {
      self.i += 2
      check = Or(check, self.and_expr())
    } else {
      return check
    }
  } nobreak {
    check
  }
}

///|
fn QParser::and_expr(self : QParser) -> Test raise @moonjson.Refused {
  let mut check = self.basic()
  while true {
    self.space()
    if self.here() == 0x26 && self.peek(1) == 0x26 {
      self.i += 2
      check = And(check, self.basic())
    } else {
      return check
    }
  } nobreak {
    check
  }
}

///|
/// A parenthesised expression, with the `(` already eaten.
fn QParser::paren(self : QParser) -> Test raise @moonjson.Refused {
  self.i += 1
  let inner = self.or_expr()
  self.space()
  if !self.eat(0x29) {
    raise self.fail()
  }
  inner
}

///|
/// A basic expression: a parenthesised one, a comparison, or a test.
///
/// `!` may stand before a parenthesised expression or before a test, and not
/// before a comparison: `!@.a == 1` is two expressions where the grammar has
/// one, and it is refused rather than read as `!(…)`.
fn QParser::basic(self : QParser) -> Test raise @moonjson.Refused {
  self.space()
  if self.here() == 0x21 {
    self.i += 1
    self.space()
    if self.here() == 0x28 {
      return Not(self.paren())
    }
    match as_test(self.operand()) {
      Some(check) => return Not(check)
      None => raise self.fail()
    }
  }
  if self.here() == 0x28 {
    return self.paren()
  }
  let left = self.operand()
  self.space()
  match self.comparison() {
    Some(op) => {
      let a = match as_value(left) {
        Some(operand) => operand
        None => raise self.fail()
      }
      self.space()
      let right = self.operand()
      let b = match as_value(right) {
        Some(operand) => operand
        None => raise self.fail()
      }
      Compare(a, op, b)
    }
    None =>
      match as_test(left) {
        Some(check) => check
        None => raise self.fail()
      }
  }
}

///|
fn QParser::comparison(self : QParser) -> Op? {
  match self.here() {
    0x3D =>
      if self.peek(1) == 0x3D {
        self.i += 2
        Some(Eq)
      } else {
        None
      }
    0x21 =>
      if self.peek(1) == 0x3D {
        self.i += 2
        Some(Ne)
      } else {
        None
      }
    0x3C =>
      if self.peek(1) == 0x3D {
        self.i += 2
        Some(Le)
      } else {
        self.i += 1
        Some(Lt)
      }
    0x3E =>
      if self.peek(1) == 0x3D {
        self.i += 2
        Some(Ge)
      } else {
        self.i += 1
        Some(Gt)
      }
    _ => None
  }
}

///|
/// An operand: a literal, a query, or a function call.
fn QParser::operand(self : QParser) -> Item raise @moonjson.Refused {
  match self.here() {
    0x22 | 0x27 =>
      {
        kind: Value,
        operand: Const(Json::string(self.string())),
        singular: false,
      }
    0x2D
    | 0x30
    | 0x31
    | 0x32
    | 0x33
    | 0x34
    | 0x35
    | 0x36
    | 0x37
    | 0x38
    | 0x39 =>
      {
        kind: Value,
        operand: Const(Json::number(self.number())),
        singular: false,
      }
    0x40 | 0x24 => {
      let root = self.here() == 0x24
      self.i += 1
      let segments = self.segments(true)
      {
        kind: Nodelist,
        operand: Nodes(root~, segments~),
        singular: singular(segments),
      }
    }
    _ =>
      if self.ahead("true") {
        self.i += 4
        { kind: Value, operand: Const(Json::boolean(true)), singular: false, }
      } else if self.ahead("false") {
        self.i += 5
        { kind: Value, operand: Const(Json::boolean(false)), singular: false, }
      } else if self.ahead("null") {
        self.i += 4
        { kind: Value, operand: Const(Json::null()), singular: false, }
      } else {
        let name = self.shorthand()
        if !self.eat(0x28) {
          raise self.fail()
        }
        self.call(name)
      }
  }
}

///|
/// A function call, with the name read and the `(` eaten.
///
/// Only the five functions RFC 9535 §2.4 defines exist, each with one signature:
/// an unknown name, the wrong number of arguments, or an argument of the wrong
/// type is not a query.
fn QParser::call(self : QParser, name : String) -> Item raise @moonjson.Refused {
  let wants : Array[Kind] = match name {
    "length" => [Value]
    "count" | "value" => [Nodelist]
    "match" | "search" => [Value, Value]
    _ => raise self.fail()
  }
  let answer = if name == "match" || name == "search" { Logical } else { Value }
  let args : Array[Operand] = []
  self.space()
  if !self.eat(0x29) {
    while true {
      self.space()
      let item = self.operand()
      if args.length() >= wants.length() {
        raise self.fail()
      }
      let operand = match wants[args.length()] {
        Value =>
          match as_value(item) {
            Some(operand) => operand
            None => raise self.fail()
          }
        Nodelist =>
          match item.kind {
            Nodelist => item.operand
            _ => raise self.fail()
          }
        Logical => raise self.fail()
      }
      args.push(operand)
      self.space()
      if self.eat(0x2C) {
        continue
      }
      if self.eat(0x29) {
        break
      }
      raise self.fail()
    }
  }
  if args.length() != wants.length() {
    raise self.fail()
  }
  { kind: answer, operand: Call(name~, args~), singular: false, }
}

///|
fn QParser::ahead(self : QParser, word : String) -> Bool {
  if self.i + word.length() > self.src.length() {
    return false
  }
  for k in 0..<word.length() {
    if self.src.at(self.i + k) != word.at(k) {
      return false
    }
  }
  true
}

///|
/// A number as JSON writes one; the query language has no other numbers.
fn QParser::number(self : QParser) -> Double raise @moonjson.Refused {
  let start = self.i
  if self.eat(0x2D) {
    ()
  }
  while self.here() >= 0x30 && self.here() <= 0x39 {
    self.i += 1
  }
  if self.eat(0x2E) {
    while self.here() >= 0x30 && self.here() <= 0x39 {
      self.i += 1
    }
  }
  if self.here() == 0x65 || self.here() == 0x45 {
    self.i += 1
    if self.here() == 0x2B || self.here() == 0x2D {
      self.i += 1
    }
    while self.here() >= 0x30 && self.here() <= 0x39 {
      self.i += 1
    }
  }
  let value = @moonjson.loads(self.src[start:self.i], @moonjson.strict) catch {
    _ => raise self.fail()
  }
  match value {
    Number(n, ..) => n
    _ => raise self.fail()
  }
}

///|
/// An operand where a value is expected: a literal, a function that answers
/// one, or a query that names at most one node.
fn as_value(item : Item) -> Operand? {
  match item.kind {
    Value => Some(item.operand)
    Nodelist => if item.singular { Some(item.operand) } else { None }
    Logical => None
  }
}

///|
/// An operand where a test is expected: a query, or a function that answers a
/// logical value. A literal is neither — `$[?true]` is not a test.
fn as_test(item : Item) -> Test? {
  match item.kind {
    Nodelist | Logical => Some(Exists(item.operand))
    Value => None
  }
}

///|
/// Whether a query names at most one node: every segment has exactly one
/// selector, and that selector is a name or an index. RFC 9535 §2.3.5.1's
/// `singular-query`, which is what may be compared.
fn singular(segments : Array[Segment]) -> Bool {
  for segment in segments {
    match segment {
      Descendant(_) => return false
      Child(selectors) =>
        if selectors.length() != 1 {
          return false
        } else {
          match selectors[0] {
            Name(_) | Index(_) => ()
            _ => return false
          }
        }
    }
  }
  true
}
