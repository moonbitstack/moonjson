// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Cases drawn from JSONTestSuite's `y_` and `n_` files. Each verdict was taken
/// from a third-party parser configured to refuse `NaN` and `Infinity`, which
/// RFC 8259 has no syntax for.
test "the grammar is exactly RFC 8259" {
  let cases = [
    ("[]", true),
    ("{}", true),
    ("[1]", true),
    ("[[]]", true),
    ("[{}]", true),
    ("{\"a\":1}", true),
    ("{\"a\":{\"b\":[1,2]}}", true),
    ("[null]", true),
    ("[true]", true),
    ("[false]", true),
    ("{\"\":0}", true),
    ("{\"a\":\"b\",\"a\":\"c\"}", true),
    ("[[[[[[[[[[[[[[[[[[[\"not too deep\"]]]]]]]]]]]]]]]]]]]", true),
    ("\"string\"", true),
    ("42", true),
    ("true", true),
    ("false", true),
    ("null", true),
    ("-0.5", true),
    ("[0]", true),
    ("[-0]", true),
    ("[1e1]", true),
    ("[1E1]", true),
    ("[1e-1]", true),
    ("[1e+1]", true),
    ("[0.1]", true),
    ("[123e45]", true),
    ("[1234567890123456789012345678901234567890]", true),
    ("[-1]", true),
    ("[0.0]", true),
    ("[01]", false),
    ("[-01]", false),
    ("[.1]", false),
    ("[1.]", false),
    ("[+1]", false),
    ("[1e]", false),
    ("[1e+]", false),
    ("[--1]", false),
    ("[1..1]", false),
    ("[0x1]", false),
    ("[1,]", false),
    ("[-]", false),
    ("[1e1e1]", false),
    ("[0e]", false),
    ("[0E+]", false),
    ("[\"abc\"]", true),
    ("[\"\\\"\\\\\\/\\b\\f\\n\\r\\t\"]", true),
    ("[\"\\u0000\"]", true),
    ("[\"\\u002c\"]", true),
    ("[\" \"]", true),
    ("[\"\\uD834\\uDD1E\"]", true),
    ("[\"\\u00e9\"]", true),
    ("[\"abc]", false),
    ("[\"\\q\"]", false),
    ("[\"\\u00\"]", false),
    ("[\"\\uZZZZ\"]", false),
    ("[\"a\nb\"]", false),
    ("[\"a\tb\"]", false),
    ("['single']", false),
    ("[\"unclosed", false),
    ("[\"\\x41\"]", false),
    ("{\"a\":1,}", false),
    ("[,1]", false),
    ("{,}", false),
    ("{\"a\" 1}", false),
    ("{\"a\":}", false),
    ("{:1}", false),
    ("{\"a\":1\"b\":2}", false),
    ("{a:1}", false),
    ("{\"a\":1,,\"b\":2}", false),
    ("", false),
    ("   ", false),
    ("[", false),
    ("]", false),
    ("{", false),
    ("}", false),
    ("[1", false),
    ("{\"a\"", false),
    ("[1 2]", false),
    ("[1] [2]", false),
    ("{\"a\":1}extra", false),
    ("\t\n [1] \r\n", true),
    ("[ 4]", true),
    ("[4 ]", true),
    ("nul", false),
    ("tru", false),
    ("fals", false),
    ("[NaN]", false),
    ("[Infinity]", false),
    ("[-Infinity]", false),
    ("NaN", false),
    ("Infinity", false),
    ("//c\n[]", false),
    ("/*c*/[]", false),
    ("[1]//c", false),
  ]
  for case in cases {
    let (text, ok) = case
    let parsed = try {
      @json.parse(text) |> ignore
      true
    } catch {
      _ => false
    }
    if parsed != ok {
      fail(
        "\{text} should have been \{if ok { "accepted" } else { "refused" }}",
      )
    }
  }
}

///|
/// A lone half of a surrogate pair is refused. It is not a character, and
/// implementations that accept it disagree about what they then hold — which is
/// why JSONTestSuite files these cases as implementation-defined rather than
/// required either way.
test "a lone surrogate is refused" {
  for
    text in [
      "[\"\\uD800\"]", "[\"\\uDEAD\"]", "[\"\\uD800a\"]", "[\"\\uD800\\uD800\"]",
    ] {
    try @json.parse(text) |> ignore catch {
      e => assert_true(e is BadEscape(_))
    } noraise {
      _ => fail("\{text} was accepted")
    }
  }
  // A whole pair is a character and is accepted.
  assert_eq(@json.write(@json.parse("[\"\\uD834\\uDD1E\"]")), "[\"\u{1D11E}\"]")
}

///|
/// Writing back what was read gives the same text: a number keeps the digits it
/// was written with, and members keep their order.
test "a canonical document round-trips exactly" {
  let cases = [
    "{\"a\":1,\"b\":[1,2,3],\"c\":null}", "[]", "{}", "[0,-0,1e400,0.1,1.0]", "{\"nested\":{\"deep\":{\"deeper\":[true,false,null]}}}",
    "[\"tab\\t\",\"newline\\n\",\"quote\\\"\",\"backslash\\\\\",\"unicode\\u0007\"]",
    "[1234567890123456789012345678901234567890]", "{\"\":\"empty name\"}",
  ]
  for text in cases {
    assert_eq(@json.write(@json.parse(text)), text)
    assert_eq(
      @json.write_bytes(
        @json.parse_bytes(@json.write_bytes(@json.parse(text))[:]),
      ),
      @json.write_bytes(@json.parse(text)),
    )
  }
}

///|
/// What the tree actually holds, since a parser that accepts everything and
/// builds nothing would pass the table above.
test "values come out as themselves" {
  assert_eq(@json.parse("null"), Json::null())
  assert_eq(@json.parse("true"), Json::boolean(true))
  assert_eq(@json.parse("[1,2]"), [1.0, 2.0] |> Json::array)
  assert_eq(@json.parse("\"hi\""), Json::string("hi"))
  assert_eq(@json.parse("\"\\u00e9\""), Json::string("é"))
  assert_eq(
    @json.parse("\"\\t\\n\\r\\b\\f\\/\\\\\""),
    Json::string("\t\n\r\u{08}\u{0C}/\\"),
  )
  match @json.parse("{\"a\":[1],\"b\":{}}") {
    Object(members) => {
      assert_eq(members.length(), 2)
      assert_true(members.get("a") is Some(Array(_)))
    }
    _ => fail("an object did not parse as one")
  }
  // A later member of the same name replaces an earlier one, which is what
  // every implementation does and what RFC 8259 §4 permits.
  match @json.parse("{\"a\":1,\"a\":2}") {
    Object(members) =>
      assert_eq(members.get("a"), Some(Json::number(2.0, repr="2")))
    _ => fail("an object did not parse as one")
  }
}

///|
/// An error has to say where, or it is only half an error.
test "a failure names the line and the column" {
  try @json.parse("{\n  \"a\": 1,\n  \"b\": ?\n}") |> ignore catch {
    e => {
      let spot = e.at()
      assert_eq(spot.line, 3)
      assert_eq(spot.column, 8)
      assert_eq(e, Unexpected(spot, '?'))
    }
  } noraise {
    _ => fail("a bare question mark was accepted")
  }
  try @json.parse("[1, 2") |> ignore catch {
    e => assert_true(e is Truncated(_))
  } noraise {
    _ => fail("a truncated array was accepted")
  }
  try @json.parse("[1] [2]") |> ignore catch {
    e => assert_eq(e.at().at, 4)
  } noraise {
    _ => fail("two documents were read as one")
  }
}

///|
/// Nesting is refused past the limit rather than taken to the stack. A
/// hundred-thousand-bracket document is a denial of service, not a document.
test "nesting is bounded" {
  let deep = StringBuilder()
  for _ in 0..<600 {
    deep.write_char('[')
  }
  for _ in 0..<600 {
    deep.write_char(']')
  }
  try @json.parse(deep.to_string()) |> ignore catch {
    e => assert_true(e is TooDeep(_))
  } noraise {
    _ => fail("six hundred levels were accepted")
  }
  // One level short of the limit is fine.
  let fine = StringBuilder()
  for _ in 0..<400 {
    fine.write_char('[')
  }
  for _ in 0..<400 {
    fine.write_char(']')
  }
  @json.parse(fine.to_string()) |> ignore
}

///|
/// Pretty-printing, and the bytes face.
test "indent and bytes" {
  let value = @json.parse("{\"a\":[1,2],\"b\":{}}")
  assert_eq(
    @json.write(value, indent=2),
    "{\n  \"a\": [\n    1,\n    2\n  ],\n  \"b\": {}\n}",
  )
  assert_eq(@json.write_bytes(value), b"{\"a\":[1,2],\"b\":{}}")
  assert_eq(@json.parse_bytes(b"[1,2]"[:]), @json.parse("[1,2]"))
  // A number a double cannot hold is written back as it came.
  assert_eq(
    @json.write(@json.parse("[1e400,-1e400,1e-400]")),
    "[1e400,-1e400,1e-400]",
  )
}
