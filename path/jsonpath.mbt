// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One way of choosing from a node.
pub(all) enum Selector {
  /// A member with this name, or nothing.
  Name(String)
  /// An element at this index, or nothing.
  Index(Int32)
  /// Every element of an array, or every member of an object.
  Wildcard
  /// A range of an array. `None` means "from the beginning", "to the end", or
  /// "by one" — the three defaults RFC 9535 §2.3.4.2 gives the three parts.
  Slice(start~ : Int32?, end~ : Int32?, step~ : Int32?)
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
  Eq
  Ne
  Lt
  Le
  Gt
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
  Or(Test, Test)
  And(Test, Test)
  Not(Test)
  /// Whether the query selects anything at all.
  Exists(Operand)
  Compare(Operand, Op, Operand)
}

///|
/// A compiled query.
pub(all) struct Path {
  segments : Array[Segment]
}

///|
/// Compile a query.
///
/// The grammar is RFC 9535 §2.2's, and a query that does not parse is refused
/// with the offset it stopped at rather than run as something else.
pub fn compile(query : StringView) -> Path raise @moonjson.Refused {
  let p : QParser = { src: query, i: 0, }
  p.space()
  if !p.eat(0x24) {
    raise @moonjson.Syntax(path=query.to_owned(), at=p.i)
  }
  Path::new(segments=p.segments(false))
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
        let at = if index < 0 { items.length() + index } else { index }
        if at >= 0 && at < items.length() {
          out.push(items[at])
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
/// RFC 9535 §2.3.4.2: a slice counts from either end, and a step of zero
/// selects nothing rather than running away.
fn slice(
  out : Array[Json],
  items : Array[Json],
  start : Int32?,
  end : Int32?,
  step : Int32?,
) -> Unit {
  let length = items.length()
  let by = match step {
    Some(n) => n
    None => 1
  }
  if by == 0 {
    return
  }
  let mut from = match start {
    Some(n) => if n < 0 { n + length } else { n }
    None => if by > 0 { 0 } else { length - 1 }
  }
  let mut to = match end {
    Some(n) => if n < 0 { n + length } else { n }
    None => if by > 0 { length } else { -length - 1 }
  }
  if by > 0 {
    if from < 0 {
      from = 0
    }
    if to > length {
      to = length
    }
    let mut at = from
    while at < to {
      if at >= 0 && at < length {
        out.push(items[at])
      }
      at += by
    }
  } else {
    if from > length - 1 {
      from = length - 1
    }
    let mut at = from
    while at > to {
      if at >= 0 && at < length {
        out.push(items[at])
      }
      at += by
    }
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
            Some(String(s)) => Some(Json::number(s.length().to_double()))
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
/// Comparisons, as RFC 9535 §2.3.5.2.2 defines them: a comparison with nothing
/// is false, two values of different types are unequal, and order exists only
/// between two numbers or two strings.
fn compare(a : Json?, op : Op, b : Json?) -> Bool {
  match (a, b) {
    (Some(left), Some(right)) =>
      match op {
        Eq => alike(left, right)
        Ne => !alike(left, right)
        Lt | Le | Gt | Ge =>
          match order(left, right) {
            Some(d) =>
              match op {
                Lt => d < 0
                Le => d <= 0
                Gt => d > 0
                Ge => d >= 0
                _ => false
              }
            None => false
          }
      }
    _ => op == Ne && (a is Some(_) || b is Some(_))
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
  let mut i = 0
  while i < a.length() && i < b.length() {
    let left = a.at(i).to_int()
    let right = b.at(i).to_int()
    if left != right {
      return left - right
    }
    i += 1
  }
  a.length() - b.length()
}

// The parser.

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

///|
/// The segments after a `$` or an `@`. `stop` says what to do at the first
/// thing that is not a segment: in a filter that is the end of the query and
/// the caller's operator follows, while at the top it is an error.
fn QParser::segments(
  self : QParser,
  stop : Bool,
) -> Array[Segment] raise @moonjson.Refused {
  let out : Array[Segment] = []
  while true {
    self.space()
    if self.here() < 0 {
      return out
    }
    if self.eat(0x5B) {
      out.push(Child(self.selection()))
    } else if self.here() == 0x2E {
      self.i += 1
      if self.eat(0x2E) {
        out.push(Descendant(self.descendant_selection()))
      } else if self.eat(0x2A) {
        out.push(Child([Wildcard]))
      } else {
        out.push(Child([Name(self.shorthand())]))
      }
    } else if stop {
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
  self.space()
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
  from : Int32?,
) -> Selector raise @moonjson.Refused {
  if !self.eat(0x3A) {
    raise self.fail()
  }
  self.space()
  let to = if self.here() == 0x2D ||
    (self.here() >= 0x30 && self.here() <= 0x39) {
    Some(self.integer())
  } else {
    None
  }
  self.space()
  let by = if self.eat(0x3A) {
    self.space()
    if self.here() == 0x2D || (self.here() >= 0x30 && self.here() <= 0x39) {
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
fn QParser::integer(self : QParser) -> Int32 raise @moonjson.Refused {
  let negative = self.eat(0x2D)
  let start = self.i
  let mut value = 0
  while self.here() >= 0x30 && self.here() <= 0x39 {
    value = value * 10 + (self.here() - 0x30)
    if value > 2_000_000_000 {
      raise self.fail()
    }
    self.i += 1
  }
  if self.i == start {
    raise self.fail()
  }
  if negative {
    -value
  } else {
    value
  }
}

///|
/// A string literal, with the escapes JSON allows.
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
        0x22 => out.write_char('"')
        0x27 => out.write_char('\'')
        0x5C => out.write_char('\\')
        0x2F => out.write_char('/')
        0x62 => out.write_char('\u{08}')
        0x66 => out.write_char('\u{0C}')
        0x6E => out.write_char('\n')
        0x72 => out.write_char('\r')
        0x74 => out.write_char('\t')
        0x75 => {
          let mut value = 0
          for _ in 0..<4 {
            let digit = nibble(self.here())
            if digit < 0 {
              raise self.fail()
            }
            value = value * 16 + digit
            self.i += 1
          }
          out.write_char(value.unsafe_to_char())
        }
        _ => raise self.fail()
      }
    } else {
      self.i += 1
      out.write_char(c.unsafe_to_char())
    }
  }
  out.to_string()
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
fn QParser::basic(self : QParser) -> Test raise @moonjson.Refused {
  self.space()
  if self.eat(0x21) {
    return Not(self.basic())
  }
  if self.here() == 0x28 {
    self.i += 1
    let inner = self.or_expr()
    self.space()
    if !self.eat(0x29) {
      raise self.fail()
    }
    return inner
  }
  let left = self.operand()
  self.space()
  let op = match self.here() {
    0x3D =>
      if self.src.at(self.i + 1).to_int() == 0x3D {
        self.i += 2
        Some(Eq)
      } else {
        raise self.fail()
      }
    0x21 =>
      if self.src.at(self.i + 1).to_int() == 0x3D {
        self.i += 2
        Some(Ne)
      } else {
        raise self.fail()
      }
    0x3C =>
      if self.src.at(self.i + 1).to_int() == 0x3D {
        self.i += 2
        Some(Le)
      } else {
        self.i += 1
        Some(Lt)
      }
    0x3E =>
      if self.src.at(self.i + 1).to_int() == 0x3D {
        self.i += 2
        Some(Ge)
      } else {
        self.i += 1
        Some(Gt)
      }
    _ => None
  }
  match op {
    Some(operator) => {
      self.space()
      Compare(left, operator, self.operand())
    }
    None => Exists(left)
  }
}

///|
fn QParser::or_expr(self : QParser) -> Test raise @moonjson.Refused {
  let mut check = self.and_expr()
  while true {
    self.space()
    if self.here() == 0x7C && self.src.at(self.i + 1).to_int() == 0x7C {
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
    if self.here() == 0x26 && self.src.at(self.i + 1).to_int() == 0x26 {
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
fn QParser::operand(self : QParser) -> Operand raise @moonjson.Refused {
  match self.here() {
    0x22 | 0x27 => Const(Json::string(self.string()))
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
    | 0x39 => Const(Json::number(self.number()))
    0x40 | 0x24 => {
      let root = self.here() == 0x24
      self.i += 1
      Nodes(root~, segments=self.segments(true))
    }
    _ =>
      if self.here() == 0x74 && self.ahead("true") {
        self.i += 4
        Const(Json::boolean(true))
      } else if self.here() == 0x66 && self.ahead("false") {
        self.i += 5
        Const(Json::boolean(false))
      } else if self.here() == 0x6E && self.ahead("null") {
        self.i += 4
        Const(Json::null())
      } else {
        let name = self.shorthand()
        self.space()
        if !self.eat(0x28) {
          raise self.fail()
        }
        let args : Array[Operand] = []
        self.space()
        if !self.eat(0x29) {
          while true {
            self.space()
            args.push(self.operand())
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
        Call(name~, args~)
      }
  }
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
