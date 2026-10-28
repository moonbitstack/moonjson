// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A single key:value pair at the root, with a bareword value.
test "simple key:value object" {
  let doc = @cson.loads("a: 1\nb: two\n")
  match doc {
    Object(m) => {
      assert_eq(m.get("a"), Some(Json::number(1.0)))
      assert_eq(m.get("b"), Some(Json::string("two")))
    }
    _ => fail("the document did not parse as an object")
  }
}

///|
/// Indentation nests one object inside another.
test "nested object" {
  let doc = @cson.loads("a:\n  b: 1\n  c: 2\n")
  match doc {
    Object(m) =>
      assert_eq(
        m.get("a"),
        Some(
          Json::object(
            Map::from_array([("b", Json::number(1.0)), ("c", Json::number(2.0))]),
          ),
        ),
      )
    _ => fail("the document did not parse as an object")
  }
}

///|
/// A `- ` block under a key is a nested array.
test "nested array" {
  let doc = @cson.loads("arr:\n  - 1\n  - 2\n  - 3\n")
  match doc {
    Object(m) =>
      assert_eq(
        m.get("arr"),
        Some(
          Json::array([Json::number(1.0), Json::number(2.0), Json::number(3.0)]),
        ),
      )
    _ => fail("the document did not parse as an object")
  }
}

///|
/// A `#` to end-of-line comment is ignored.
test "line comment" {
  let doc = @cson.loads(
    "# a leading comment\n# another\na: 1\n  # indented comment\nb: 2\n",
  )
  match doc {
    Object(m) => {
      assert_eq(m.get("a"), Some(Json::number(1.0)))
      assert_eq(m.get("b"), Some(Json::number(2.0)))
    }
    _ => fail("the document did not parse as an object")
  }
}

///|
/// A document whose first line is a bullet is a root array.
test "root array" {
  let doc = @cson.loads("- 1\n- 2\n- 3\n")
  assert_eq(
    doc,
    Json::array([Json::number(1.0), Json::number(2.0), Json::number(3.0)]),
  )
}

///|
/// Bareword numbers, `true`, `false` and `null` parse to the right singletons.
test "numbers, booleans and null" {
  let doc = @cson.loads(
    "i: 42\nf: 3.14\nh: 0xFF\nneg: -7\ne: 1.5e3\nt: true\nf2: false\nn: null\n",
  )
  match doc {
    Object(m) => {
      assert_eq(m.get("i"), Some(Json::number(42.0)))
      assert_eq(m.get("f"), Some(Json::number(3.14)))
      assert_eq(m.get("h"), Some(Json::number(255.0)))
      assert_eq(m.get("neg"), Some(Json::number(-7.0)))
      assert_eq(m.get("e"), Some(Json::number(1500.0)))
      assert_eq(m.get("t"), Some(Json::boolean(true)))
      assert_eq(m.get("f2"), Some(Json::boolean(false)))
      assert_eq(m.get("n"), Some(Json::null()))
    }
    _ => fail("the document did not parse as an object")
  }
}

///|
/// A quoted key paired with a quoted value.
test "quoted key and quoted value" {
  let doc = @cson.loads("\"key\": 'value'\n")
  match doc {
    Object(m) => assert_eq(m.get("key"), Some(Json::string("value")))
    _ => fail("the document did not parse as an object")
  }
}

///|
/// A `'''` block string keeps its line breaks and is dedented.
test "multiline block string" {
  let src =
    #|
    #|str: '''
    #|  hello
    #|  world
    #|'''
  let doc = @cson.loads(src)
  match doc {
    Object(m) => assert_eq(m.get("str"), Some(Json::string("hello\nworld")))
    _ => fail("the document did not parse as an object")
  }
}

///|
/// An object whose elements are themselves objects, written with `- key:`.
test "array of objects" {
  let doc = @cson.loads("- name: one\n  value: 1\n- name: two\n  value: 2\n")
  assert_eq(
    doc,
    Json::array([
      Json::object(
        Map::from_array([
          ("name", Json::string("one")),
          ("value", Json::number(1.0)),
        ]),
      ),
      Json::object(
        Map::from_array([
          ("name", Json::string("two")),
          ("value", Json::number(2.0)),
        ]),
      ),
    ]),
  )
}

///|
/// The writer delegates to `@moonjson`, so it emits strict JSON.
test "writer emits strict JSON" {
  let tree = Json::object(
    Map::from_array([("a", Json::number(1.0)), ("b", Json::string("x"))]),
  )
  assert_eq(@cson.dumps(tree), "{\"a\":1,\"b\":\"x\"}")
  assert_eq(@cson.dumps(tree), @moonjson.dumps(tree))
}

///|
/// A CSON tree, written as JSON, reads back to the same tree through the strict
/// JSON reader — the only faithful round trip CSON admits.
test "round trip through strict JSON" {
  let src =
    #|
    #|a: 1
    #|b:
    #|  c: 2
    #|  d:
    #|    - 3
    #|    - 4
    #|s: "quoted"
  let tree = @cson.loads(src)
  let json = @cson.dumps(tree)
  let back = @json.loads(json)
  match (tree, back) {
    (Object(t), Object(b)) => {
      assert_eq(t.get("a"), b.get("a"))
      match (t.get("b"), b.get("b")) {
        (Some(Object(to)), Some(Object(bo))) => {
          assert_eq(to.get("c"), bo.get("c"))
          assert_eq(to.get("d"), bo.get("d"))
        }
        _ => fail("b did not round trip as an object")
      }
      assert_eq(t.get("s"), b.get("s"))
    }
    _ => fail("the document did not parse as an object")
  }
}

///|
/// A document that is not CSON is refused rather than silently misread.
test "a syntax error is refused" {
  let bad = ["{ this is not cson", "a: 1\nb", "- 1\nkey: 2"]
  for text in bad {
    let raised = try {
      @cson.loads(text) |> ignore
      false
    } catch {
      _ => true
    }
    if !raised {
      fail("\{text} was accepted")
    }
  }
}

///|
/// `load` decodes UTF-8 bytes the same way `loads` reads text.
test "load reads UTF-8 bytes" {
  let doc = @cson.load(b"a: 1\n")
  match doc {
    Object(m) => assert_eq(m.get("a"), Some(Json::number(1.0)))
    _ => fail("the bytes did not parse as an object")
  }
}
