// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A configuration file of the kind the dialect exists for.
let settings : String =
  #|{
  #|  // The compiler options, as tsconfig writes them.
  #|  "compilerOptions": {
  #|    "target": "es2022",  // the oldest runtime we support
  #|    "strict": true,
  #|    /* Several lines,
  #|       because a block comment may span them. */
  #|    "lib": ["dom", "es2022"],
  #|  },
  #|  "exclude": ["node_modules"],
  #|}

///|
test "a settings file reads, comments and all" {
  let doc = @jsonc.loads(settings[:])
  assert_eq(
    @jsonc.dumps(doc),
    "{\"compilerOptions\":{\"target\":\"es2022\",\"strict\":true,\"lib\":[\"dom\",\"es2022\"]},\"exclude\":[\"node_modules\"]}",
  )
}

///|
/// The two extras, and nothing else: a name is still quoted and a string still
/// double-quoted, which is where this dialect stops and JSON5 goes on.
test "comments and trailing commas, and no more" {
  let good = [
    ("[1] // after", "[1]"),
    ("// before\n[1]", "[1]"),
    ("/* around */ [1] /* it */", "[1]"),
    ("[1,2,]", "[1,2]"),
    ("{\"a\":1,}", "{\"a\":1}"),
    ("[/* inside */1]", "[1]"),
    ("[1//\n]", "[1]"),
    ("{\"a\"/**/:/**/1}", "{\"a\":1}"),
  ]
  for case in good {
    let (text, want) = case
    assert_eq(@jsonc.dumps(@jsonc.loads(text)), want)
  }
  let bad = ["{a:1}", "['x']", "[+1]", "[.5]", "[0x1]", "[/* unclosed", "[1,,]"]
  for text in bad {
    try @jsonc.loads(text) |> ignore catch {
      _ => ()
    } noraise {
      _ => fail("\{text} was accepted")
    }
  }
}

///|
/// The same documents under strict JSON must fail, or the dialect is not adding
/// anything.
test "strict JSON refuses what this accepts" {
  for text in ["[1] // after", "[1,2,]", "{\"a\":1,}", "/* c */ [1]"] {
    try @moonjson.loads(text[:], @moonjson.strict) |> ignore catch {
      _ => ()
    } noraise {
      _ => fail("strict JSON accepted \{text}")
    }
  }
}

///|
/// A comment is discarded, so the position of what follows must still be right.
test "a failure after a comment names the right place" {
  try @jsonc.loads("// one\n// two\n[1, ?]") |> ignore catch {
    e => {
      let spot = e.at()
      assert_eq(spot.line, 3)
      assert_eq(spot.column, 5)
    }
  } noraise {
    _ => fail("a bare question mark was accepted")
  }
}

///|
test "bytes in and out" {
  assert_eq(@jsonc.load(b"[1] // c"[:]), @jsonc.loads("[1]"))
  assert_eq(@jsonc.dump(@jsonc.loads("[1,]")), b"[1]")
  assert_eq(
    @jsonc.dumps(@jsonc.loads("{\"a\":1,}"), indent=2),
    "{\n  \"a\": 1\n}",
  )
}
