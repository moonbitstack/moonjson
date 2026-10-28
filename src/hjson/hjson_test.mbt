///|
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Comments of every kind are ignored.
test "comments are ignored" {
  let doc = @hjson.loads(
    "{\n  // a line comment\n  a: 1\n  b: 2 # a hash comment trails the value\n  /* a block comment */\n  c: 3\n}",
  )
  match doc {
    Object(m) => {
      assert_eq(m.get("a"), Some(Json::number(1.0)))
      assert_eq(m.get("b"), Some(Json::number(2.0)))
      assert_eq(m.get("c"), Some(Json::number(3.0)))
    }
    _ => fail("comments fixture did not parse as an object")
  }
}

///|
/// The braces around a root object are optional.
test "root braces are optional" {
  let bare = @hjson.loads("a: 1\nb: 2")
  let braced = @hjson.loads("{ a: 1, b: 2 }")
  let want = Json::object(
    Map::from_array([("a", Json::number(1.0)), ("b", Json::number(2.0))]),
  )
  assert_eq(bare, want)
  assert_eq(braced, want)
}

///|
/// Keys need not be quoted and commas are optional and may trail.
test "quoteless keys and optional, trailing commas" {
  let doc = @hjson.loads("{\n  name: Alice\n  age: 30,\n  city: London\n}")
  match doc {
    Object(m) => {
      assert_eq(m.get("name"), Some(Json::string("Alice")))
      assert_eq(m.get("age"), Some(Json::number(30.0)))
      assert_eq(m.get("city"), Some(Json::string("London")))
    }
    _ => fail("key fixture did not parse as an object")
  }
}

///|
/// Arrays accept brackets, or a dash-led, bracket-less block.
test "arrays with and without dashes" {
  let bracketed = @hjson.loads("[ 1, 2, 3 ]")
  assert_eq(
    bracketed,
    Json::array([Json::number(1.0), Json::number(2.0), Json::number(3.0)]),
  )
  let dashed = @hjson.loads("- 1\n- 2\n- 3")
  assert_eq(
    dashed,
    Json::array([Json::number(1.0), Json::number(2.0), Json::number(3.0)]),
  )
}

///|
/// Numbers, the words, and hexadecimal notation all read.
test "numbers, true, false, null and hex" {
  let doc = @hjson.loads(
    "{\n  int: 42\n  neg: -3.14\n  hex: 0xFF\n  yes: true\n  no: false\n  nothing: null\n}",
  )
  match doc {
    Object(m) => {
      assert_eq(m.get("int"), Some(Json::number(42.0)))
      assert_eq(m.get("neg"), Some(Json::number(-3.14)))
      assert_eq(m.get("hex"), Some(Json::number(255.0)))
      assert_eq(m.get("yes"), Some(Json::boolean(true)))
      assert_eq(m.get("no"), Some(Json::boolean(false)))
      assert_eq(m.get("nothing"), Some(Json::null()))
    }
    _ => fail("scalar fixture did not parse as an object")
  }
}

///|
/// A multiline string keeps its lines, dedented.
test "a multiline string" {
  let doc = @hjson.loads("text: '''\nhello\nworld\n'''")
  match doc {
    Object(m) => assert_eq(m.get("text"), Some(Json::string("hello\nworld")))
    _ => fail("multiline fixture did not parse as an object")
  }
}

///|
/// Objects and arrays nest, braces and brackets mixing freely.
test "a nested structure" {
  let doc = @hjson.loads(
    "{\n  user: {\n    name: Alice\n    age: 30\n    roles: [\n      admin\n      user\n    ]\n  }\n  active: true\n}",
  )
  let want = Json::object(
    Map::from_array([
      (
        "user",
        Json::object(
          Map::from_array([
            ("name", Json::string("Alice")),
            ("age", Json::number(30.0)),
            (
              "roles",
              Json::array([Json::string("admin"), Json::string("user")]),
            ),
          ]),
        ),
      ),
      ("active", Json::boolean(true)),
    ]),
  )
  assert_eq(doc, want)
}

///|
/// A tree read and written comes back unchanged, and so does the strict
/// reader on the same text.
test "round trips" {
  let trees = [
    Json::object(
      Map::from_array([
        ("name", Json::string("Alice")),
        ("age", Json::number(30.0)),
        ("active", Json::boolean(true)),
        ("scores", Json::array([Json::number(1.0), Json::number(2.0)])),
      ]),
    ),
    Json::array([Json::number(1.0), Json::string("two"), Json::null()]),
    Json::number(-2.5),
    Json::string("a quoteless-ish.value"),
  ]
  for tree in trees {
    let written = @hjson.dumps(tree, indent=2)
    assert_true(@hjson.loads(written) == tree)
    assert_true(@json.loads(written) == tree)
  }
}

///|
/// A few malformed documents are refused.
test "malformed documents are refused" {
  let bad = ["\"unterminated", "]", "\"x\\q\""]
  for text in bad {
    try @hjson.loads(text) |> ignore catch {
      _ => ()
    } noraise {
      _ => fail("\{text} was accepted")
    }
  }
}

///|
/// `load` decodes UTF-8 bytes, the same tree as `loads`.
test "load reads UTF-8 bytes" {
  let bytes = @utf8.encode("a: 1"[:])
  let doc = @hjson.load(bytes)
  assert_eq(doc, Json::object(Map::from_array([("a", Json::number(1.0))])))

  let not_utf8 = Bytes::from_array([0xFF, 0xFE, 0x00])
  try @hjson.load(not_utf8) |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("invalid UTF-8 was accepted")
  }
}
