// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The document RFC 9535 §1.5 uses for every example in the specification.
let store : String = "{\"store\":{\"book\":[{\"category\":\"reference\",\"author\":\"Nigel Rees\",\"title\":\"Sayings of the Century\",\"price\":8.95},{\"category\":\"fiction\",\"author\":\"Evelyn Waugh\",\"title\":\"Sword of Honour\",\"price\":12.99},{\"category\":\"fiction\",\"author\":\"Herman Melville\",\"title\":\"Moby Dick\",\"isbn\":\"0-553-21311-3\",\"price\":8.99},{\"category\":\"fiction\",\"author\":\"J. R. R. Tolkien\",\"title\":\"The Lord of the Rings\",\"isbn\":\"0-395-19395-8\",\"price\":22.99}],\"bicycle\":{\"color\":\"red\",\"price\":399}}}"

///|
fn picked(query : String) -> String raise {
  let doc = @json.loads(store)
  let nodes = @path.select(doc, query[:])
  @json.dumps(Json::array(nodes))
}

///|
/// The queries and answers of RFC 9535 table 12, in the order the RFC prints
/// them.
test "the RFC's own table" {
  let cases : Array[(String, String)] = [
    (
      "$.store.book[*].author", "[\"Nigel Rees\",\"Evelyn Waugh\",\"Herman Melville\",\"J. R. R. Tolkien\"]",
    ),
    (
      "$..author", "[\"Nigel Rees\",\"Evelyn Waugh\",\"Herman Melville\",\"J. R. R. Tolkien\"]",
    ),
    ("$..book[2].author", "[\"Herman Melville\"]"),
    ("$..book[2].publisher", "[]"),
    ("$..book[-1].title", "[\"The Lord of the Rings\"]"),
    ("$..book[0,1].title", "[\"Sayings of the Century\",\"Sword of Honour\"]"),
    ("$..book[:2].title", "[\"Sayings of the Century\",\"Sword of Honour\"]"),
    ("$..book[?@.isbn].title", "[\"Moby Dick\",\"The Lord of the Rings\"]"),
    ("$..book[?@.price<10].title", "[\"Sayings of the Century\",\"Moby Dick\"]"),
    ("$.store.bicycle.color", "[\"red\"]"),
    ("$.store['bicycle'].price", "[399]"),
    ("$.store.book[?(@.price == 8.99)].title", "[\"Moby Dick\"]"),
  ]
  for row in cases {
    let (query, want) = row
    assert_eq(picked(query), want)
  }
}

///|
/// `..` visits every node, so `$..price` finds all five prices in document
/// order — the four books, then the bicycle.
test "a descendant segment reaches everything" {
  assert_eq(picked("$..price"), "[8.95,12.99,8.99,22.99,399]")
  assert_eq(picked("$.store.*").length() > 0, true)
}

///|
/// A slice counts from either end and steps by any non-zero amount.
test "slices" {
  let doc = @json.loads("[0,1,2,3,4,5]")
  let cases : Array[(String, String)] = [
    ("$[1:3]", "[1,2]"),
    ("$[:2]", "[0,1]"),
    ("$[4:]", "[4,5]"),
    ("$[::2]", "[0,2,4]"),
    ("$[::-1]", "[5,4,3,2,1,0]"),
    ("$[-2:]", "[4,5]"),
    ("$[1:-1]", "[1,2,3,4]"),
    ("$[::0]", "[]"),
  ]
  for row in cases {
    let (query, want) = row
    assert_eq(@json.dumps(Json::array(@path.select(doc, query[:]))), want)
  }
}

///|
/// The five functions RFC 9535 §2.4 defines.
test "functions" {
  let doc = @json.loads(
    "[{\"a\":\"xy\"},{\"a\":\"xyz\"},{\"a\":[1,2]},{\"a\":1}]",
  )
  let cases : Array[(String, String)] = [
    ("$[?length(@.a) == 2]", "[{\"a\":\"xy\"},{\"a\":[1,2]}]"),
    ("$[?match(@.a, \"xy\")]", "[{\"a\":\"xy\"}]"),
    ("$[?search(@.a, \"y\")]", "[{\"a\":\"xy\"},{\"a\":\"xyz\"}]"),
    ("$[?count(@.a[*]) == 2]", "[{\"a\":[1,2]}]"),
  ]
  for row in cases {
    let (query, want) = row
    assert_eq(@json.dumps(Json::array(@path.select(doc, query[:]))), want)
  }
}

///|
/// `match` is the whole string and `search` is any part of it; that is the only
/// difference between them, and it is the one that catches an implementation
/// that treats both as a search.
test "match and search differ" {
  assert_true(@path.matches("a.*", "abc"))
  assert_false(@path.matches("a.*", "zabc"))
  assert_true(@path.finds("a.*", "zabc"))
  assert_true(@path.matches("\\d{2,3}", "123"))
  assert_false(@path.matches("\\d{2,3}", "1"))
  assert_true(@path.finds("(?:(a|b)c)+", "zzacbc"))
}

///|
/// A logical expression: `!`, `&&`, `||` and parentheses, in that precedence.
test "logical expressions" {
  let doc = @json.loads("[1,2,3,4,5]")
  let cases : Array[(String, String)] = [
    ("$[?@ > 3 && @ < 5]", "[4]"),
    ("$[?@ < 2 || @ > 4]", "[1,5]"),
    ("$[?!( @ < 3 )]", "[3,4,5]"),
  ]
  for row in cases {
    let (query, want) = row
    assert_eq(@json.dumps(Json::array(@path.select(doc, query[:]))), want)
  }
}

///|
/// A query that does not parse is refused with the offset it stopped at, not
/// run as something else.
test "a query that is not one" {
  let cases : Array[String] = ["store.book", "$..", "$[", "$[?@ >]", "$.a b"]
  for query in cases {
    try @path.compile(query[:]) |> ignore catch {
      e => assert_true(e is @moonjson.Syntax(..))
    } noraise {
      _ => fail("\{query} was accepted")
    }
  }
}

///|
/// A name that is not a shorthand takes the bracketed form, and the two are the
/// same selector.
test "names and shorthands" {
  let doc = @json.loads("{\"a b\":1,\"a\":{\"b\":2}}")
  assert_eq(@json.dumps(Json::array(@path.select(doc, "$['a b']"[:]))), "[1]")
  assert_eq(@json.dumps(Json::array(@path.select(doc, "$.a.b"[:]))), "[2]")
}
