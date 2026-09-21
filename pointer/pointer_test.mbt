// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The document RFC 6901 §5 uses for its worked examples.
let doc : String =
  #|{
  #|  "foo": ["bar", "baz"],
  #|  "": 0,
  #|  "a/b": 1,
  #|  "c%d": 2,
  #|  "e^f": 3,
  #|  "g|h": 4,
  #|  "i\\j": 5,
  #|  "k\"l": 6,
  #|  " ": 7,
  #|  "m~n": 8
  #|}

///|
/// Every pointer RFC 6901 §5 prints, against the document it prints them for.
test "the RFC 6901 examples" {
  let tree = @json.parse(doc[:])
  let cases = [
    ("/foo", "[\"bar\",\"baz\"]"),
    ("/foo/0", "\"bar\""),
    ("/foo/1", "\"baz\""),
    ("/", "0"),
    ("/a~1b", "1"),
    ("/c%d", "2"),
    ("/e^f", "3"),
    ("/g|h", "4"),
    ("/i\\j", "5"),
    ("/k\"l", "6"),
    ("/ ", "7"),
    ("/m~0n", "8"),
  ]
  for case in cases {
    let (path, want) = case
    assert_eq(@json.write(@pointer.get(tree, path)), want)
    assert_true(@pointer.has(tree, path))
  }
  // The empty pointer names the whole document.
  assert_eq(@pointer.get(tree, ""), tree)
}

///|
/// `~1` before `~0`, or `~01` would come out as a slash instead of `~1`.
test "the escapes undo in the right order" {
  assert_eq(@pointer.tokens("/~01"), ["~1"])
  assert_eq(@pointer.tokens("/~10"), ["/0"])
  assert_eq(@pointer.escape("~1"), "~01")
  assert_eq(@pointer.escape("a/b~c"), "a~1b~0c")
  assert_eq(@pointer.join(["a/b", "~", "c"][:]), "/a~1b/~0/c")
  assert_eq(@pointer.tokens(@pointer.join(["a/b", "~", "c"][:])[:]), [
    "a/b", "~", "c",
  ])
}

///|
/// Splitting, at the two edges that catch a naive implementation: the empty
/// pointer names the document and has no tokens, while `"/"` names the member
/// whose name is empty and has one.
test "splitting a pointer" {
  assert_eq(@pointer.tokens(""), [])
  assert_eq(@pointer.tokens("/"), [""])
  assert_eq(@pointer.tokens("//"), ["", ""])
  assert_eq(@pointer.tokens("/a/b/c"), ["a", "b", "c"])
  assert_eq(@pointer.tokens("/a/"), ["a", ""])
}

///|
/// What a pointer must refuse, and with what said about it.
test "a pointer that leads nowhere" {
  let tree = @json.parse("{\"a\":[10,20],\"b\":{\"c\":null},\"n\":1}")
  let missing = ["/z", "/a/2", "/a/-", "/a/01", "/a/x", "/b/z", "/a/0/x"]
  for path in missing {
    assert_false(@pointer.has(tree, path))
  }
  try @pointer.get(tree, "/z") |> ignore catch {
    e => assert_eq(e, Missing(token="z"))
  } noraise {
    _ => fail("a name no member has resolved")
  }
  // `-` is the index one past the end. It exists for JSON Patch's `add` and
  // names no value, so reading through it is a miss, not an invention.
  try @pointer.get(tree, "/a/-") |> ignore catch {
    e => assert_eq(e, Missing(token="-"))
  } noraise {
    _ => fail("the one-past-the-end index resolved")
  }
  try @pointer.get(tree, "/n/x") |> ignore catch {
    e => assert_eq(e, NotContainer(token="x"))
  } noraise {
    _ => fail("a pointer walked into a number")
  }
  try @pointer.get(tree, "a") |> ignore catch {
    e => assert_eq(e, Syntax(at=0))
  } noraise {
    _ => fail("a pointer without a leading slash resolved")
  }
  try @pointer.get(tree, "/~2") |> ignore catch {
    e => assert_eq(e, Syntax(at=1))
  } noraise {
    _ => fail("an unknown escape resolved")
  }
  try @pointer.get(tree, "/~") |> ignore catch {
    e => assert_eq(e, Syntax(at=1))
  } noraise {
    _ => fail("a trailing tilde resolved")
  }
}

///|
/// An array index is decimal with no leading zero (RFC 6901 §4), so `01` is not
/// `1` and a name that looks like a number is still not an index.
test "array indices are strict" {
  let tree = @json.parse("[10,20,30]")
  assert_eq(@json.write(@pointer.get(tree, "/0")), "10")
  assert_eq(@json.write(@pointer.get(tree, "/2")), "30")
  for path in ["/00", "/01", "/+1", "/-1", "/1.0", "/ 1", "/1 ", "/"] {
    assert_false(@pointer.has(tree, path))
  }
}
