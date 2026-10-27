// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The document json5.org puts on its front page, which exercises every feature
/// the dialect adds at once.
let showcase : String =
  #|{
  #|  // comments
  #|  unquoted: 'and you can quote me on that',
  #|  singleQuotes: 'I can use "double quotes" here',
  #|  lineBreaks: "Look, Mom! \
  #|No \\n's!",
  #|  hexadecimal: 0xdecaf,
  #|  leadingDecimalPoint: .8675309, andTrailing: 8675309.,
  #|  positiveSign: +1,
  #|  trailingComma: 'in objects', andIn: ['arrays',],
  #|  "backwardsCompatible": "with JSON",
  #|}

///|
test "the JSON5 showcase reads as itself" {
  let doc = @json5.loads(showcase[:])
  match doc {
    Object(members) => {
      assert_eq(members.length(), 10)
      assert_eq(
        members.get("unquoted"),
        Some(Json::string("and you can quote me on that")),
      )
      assert_eq(
        members.get("singleQuotes"),
        Some(Json::string("I can use \"double quotes\" here")),
      )
      assert_eq(
        members.get("lineBreaks"),
        Some(Json::string("Look, Mom! No \\n's!")),
      )
      assert_eq(members.get("hexadecimal"), Some(Json::number(912559.0)))
      assert_eq(
        members.get("leadingDecimalPoint"),
        Some(Json::number(0.8675309)),
      )
      assert_eq(members.get("andTrailing"), Some(Json::number(8675309.0)))
      assert_eq(members.get("positiveSign"), Some(Json::number(1.0)))
      assert_eq(members.get("trailingComma"), Some(Json::string("in objects")))
      assert_eq(
        members.get("andIn"),
        Some(Json::array([Json::string("arrays")])),
      )
      assert_eq(
        members.get("backwardsCompatible"),
        Some(Json::string("with JSON")),
      )
    }
    _ => fail("the showcase did not parse as an object")
  }
}

///|
/// Every extra the dialect allows, one at a time, with what strict JSON makes
/// of the same text underneath.
test "each extra, and what strict JSON says to it" {
  let cases = [
    ("{a:1}", "{\"a\":1}"),
    ("{'a':1}", "{\"a\":1}"),
    ("{\"a\":1,}", "{\"a\":1}"),
    ("[1,2,]", "[1,2]"),
    ("[0xFF]", "[255]"),
    ("[0X10]", "[16]"),
    ("[-0xff]", "[-255]"),
    ("[+1]", "[1]"),
    ("[.5]", "[0.5]"),
    ("[5.]", "[5]"),
    ("[1] // trailing comment", "[1]"),
    ("/* leading */ [1]", "[1]"),
    ("[1 /* between */ , 2]", "[1,2]"),
    ("{$dollar:1,_under:2,a9:3}", "{\"$dollar\":1,\"_under\":2,\"a9\":3}"),
    ("['\\x41']", "[\"A\"]"),
    ("['\\v\\0']", "[\"\\u000b\\u0000\"]"),
    ("['a\\'b']", "[\"a'b\"]"),
    ("[\"a\\qb\"]", "[\"aqb\"]"),
  ]
  for case in cases {
    let (json5, strict) = case
    assert_eq(@json5.dumps(@json5.loads(json5)), strict)
    try @moonjson.loads(json5[:], @moonjson.strict) |> ignore catch {
      _ => ()
    } noraise {
      _ =>
        // A few of these are valid JSON too; the ones that are must agree.
        assert_eq(
          @json5.dumps(@moonjson.loads(json5[:], @moonjson.strict)),
          strict,
        )
    }
  }
}

///|
/// `Infinity` and `NaN` have no JSON syntax, so a document that carries them
/// cannot be written back as JSON. It becomes `null`, which is what every
/// JavaScript engine writes, rather than something that will not parse.
test "the values JSON cannot write become null" {
  let doc = @json5.loads("{inf:Infinity,ninf:-Infinity,nan:NaN}")
  match doc {
    Object(members) => {
      assert_true(members.get("inf") is Some(Number(_, ..)))
      assert_true(members.get("nan") is Some(_))
    }
    _ => fail("the document did not parse as an object")
  }
  assert_eq(@json5.dumps(doc), "{\"inf\":null,\"ninf\":null,\"nan\":null}")
}

///|
/// What JSON5 still refuses.
test "JSON5 is not everything" {
  let bad = [
    "{a b:1}", "[01]", "[0x]", "['unclosed]", "[/* unclosed", "{,}", "[,]", "[1,,2]",
    "[1 2]", "{:1}", "['\\1']", "[Infinit]", "[+]", "[.]",
  ]
  for text in bad {
    try @json5.loads(text) |> ignore catch {
      _ => ()
    } noraise {
      _ => fail("\{text} was accepted")
    }
  }
}

///|
/// The extra whitespace of ECMAScript, which JSON5 §2 inherits.
test "JSON5 whitespace" {
  assert_eq(
    @json5.dumps(@json5.loads("\u{FEFF}[\u{00A0}1\u{2028},\u{2029}2\u{000B}]")),
    "[1,2]",
  )
}
