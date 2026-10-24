// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Every example RFC 6902 Appendix A prints that ends in a document, as an
/// array of triples: the target, the patch, and the document that results.
///
/// Members are written in the order this implementation holds them — a member
/// added to an object goes on the end — because the RFC prints them unordered.
let appendix : String =
  #|[
  #|  [{"foo":"bar"}, [{"op":"add","path":"/baz","value":"qux"}], {"foo":"bar","baz":"qux"}],
  #|  [{"foo":["bar","baz"]}, [{"op":"add","path":"/foo/1","value":"qux"}], {"foo":["bar","qux","baz"]}],
  #|  [{"baz":"qux","foo":"bar"}, [{"op":"remove","path":"/baz"}], {"foo":"bar"}],
  #|  [{"foo":["bar","qux","baz"]}, [{"op":"remove","path":"/foo/1"}], {"foo":["bar","baz"]}],
  #|  [{"baz":"qux","foo":"bar"}, [{"op":"replace","path":"/baz","value":"boo"}], {"baz":"boo","foo":"bar"}],
  #|  [{"foo":{"bar":"baz","waldo":"fred"},"qux":{"corge":"grault"}}, [{"op":"move","from":"/foo/waldo","path":"/qux/thud"}], {"foo":{"bar":"baz"},"qux":{"corge":"grault","thud":"fred"}}],
  #|  [{"foo":["all","grass","cows","eat"]}, [{"op":"move","from":"/foo/1","path":"/foo/3"}], {"foo":["all","cows","eat","grass"]}],
  #|  [{"baz":"qux","foo":["a",2,"c"]}, [{"op":"test","path":"/baz","value":"qux"},{"op":"test","path":"/foo/1","value":2}], {"baz":"qux","foo":["a",2,"c"]}],
  #|  [{"foo":"bar"}, [{"op":"add","path":"/child","value":{"grandchild":{}}}], {"foo":"bar","child":{"grandchild":{}}}],
  #|  [{"foo":"bar"}, [{"op":"add","path":"/baz","value":"qux","xyz":123}], {"foo":"bar","baz":"qux"}],
  #|  [{"/":9,"~1":10}, [{"op":"test","path":"/~01","value":10}], {"/":9,"~1":10}],
  #|  [{"foo":["bar"]}, [{"op":"add","path":"/foo/-","value":["abc","def"]}], {"foo":["bar",["abc","def"]]}]
  #|]

///|
/// The appendix, applied. The patch text is written back out by the writer and
/// read again, which is also how a patch arrives over a wire.
test "the RFC 6902 appendix A examples" {
  match @json.loads(appendix) {
    Array(cases) =>
      for case in cases {
        match case {
          Array(parts) => {
            let doc = parts[0]
            let ops = @patch.loads(@json.dumps(parts[1]))
            assert_eq(
              @json.dumps(@patch.apply(doc, ops)),
              @json.dumps(parts[2]),
            )
          }
          _ => fail("a case is a triple")
        }
      }
    _ => fail("the appendix is an array of cases")
  }
}

///|
/// What must be refused, and with what said about it: the appendix's error
/// cases, and the rules RFC 6902 §4 states around them.
test "a patch that cannot be applied" {
  let cases : Array[(String, String, @patch.Failure)] = [
    // A.9 — a test that does not hold.
    (
      "{\"baz\":\"qux\"}",
      "[{\"op\":\"test\",\"path\":\"/baz\",\"value\":\"bar\"}]",
      TestFailed(path="/baz"),
    ),
    // A.15 — a number is not the string it was written as.
    (
      "{\"/\":9,\"~1\":10}",
      "[{\"op\":\"test\",\"path\":\"/~01\",\"value\":\"10\"}]",
      TestFailed(path="/~01"),
    ),
    // A.12 — adding to a target that is not there.
    (
      "{\"foo\":\"bar\"}",
      "[{\"op\":\"add\",\"path\":\"/baz/bat\",\"value\":\"qux\"}]",
      Missing(path="/baz/bat", token="baz"),
    ),
    // `replace` and `remove` need the target to be there.
    (
      "{\"a\":1}",
      "[{\"op\":\"replace\",\"path\":\"/x\",\"value\":1}]",
      Missing(path="/x", token="x"),
    ),
    (
      "{\"a\":1}",
      "[{\"op\":\"remove\",\"path\":\"/x\"}]",
      Missing(path="/x", token="x"),
    ),
    // An index past the end is not an append; only `-` appends.
    (
      "{\"list\":[10,20,30]}",
      "[{\"op\":\"add\",\"path\":\"/list/4\",\"value\":1}]",
      Missing(path="/list/4", token="4"),
    ),
    (
      "{\"list\":[10,20,30]}",
      "[{\"op\":\"replace\",\"path\":\"/list/9\",\"value\":1}]",
      Missing(path="/list/9", token="9"),
    ),
    // `-` names a place that does not exist yet, so there is nothing there to
    // replace, and it is not an index anywhere but at the end of an `add`.
    (
      "{\"list\":[10,20,30]}",
      "[{\"op\":\"replace\",\"path\":\"/list/-\",\"value\":1}]",
      BadIndex(path="/list/-", token="-"),
    ),
    (
      "{\"list\":[10,20,30]}",
      "[{\"op\":\"add\",\"path\":\"/list/-/x\",\"value\":1}]",
      BadIndex(path="/list/-/x", token="-"),
    ),
    // An index is decimal without a leading zero (RFC 6901 §4).
    (
      "{\"list\":[10,20,30]}",
      "[{\"op\":\"add\",\"path\":\"/list/01\",\"value\":1}]",
      BadIndex(path="/list/01", token="01"),
    ),
    (
      "{\"list\":[10,20,30]}",
      "[{\"op\":\"remove\",\"path\":\"/list/x\"}]",
      BadIndex(path="/list/x", token="x"),
    ),
    // Walking into a scalar and continuing.
    (
      "{\"a\":1}",
      "[{\"op\":\"add\",\"path\":\"/a/b\",\"value\":1}]",
      NotContainer(path="/a/b", token="b"),
    ),
    // A pointer that is not one.
    (
      "{\"a\":1}",
      "[{\"op\":\"remove\",\"path\":\"a\"}]",
      Syntax(path="a", at=0),
    ),
    (
      "{\"a\":1}",
      "[{\"op\":\"remove\",\"path\":\"/~2\"}]",
      Syntax(path="/~2", at=1),
    ),
    // A location cannot be moved into one of its own children.
    (
      "{\"b\":{\"c\":2}}",
      "[{\"op\":\"move\",\"from\":\"/b\",\"path\":\"/b/c\"}]",
      IntoChild(from="/b", path="/b/c"),
    ),
    // The source has to be there.
    (
      "{\"a\":1}",
      "[{\"op\":\"move\",\"from\":\"/x\",\"path\":\"/y\"}]",
      Missing(path="/x", token="x"),
    ),
    (
      "{\"a\":1}",
      "[{\"op\":\"copy\",\"from\":\"/x\",\"path\":\"/y\"}]",
      Missing(path="/x", token="x"),
    ),
    // The root has no parent to take it from.
    ("{\"a\":1}", "[{\"op\":\"remove\",\"path\":\"\"}]", Root(path="")),
  ]
  for case in cases {
    let (doc, patch, want) = case
    let tree = @json.loads(doc)
    let ops = @patch.loads(patch)
    try @patch.apply(tree, ops) |> ignore catch {
      e => assert_eq(e, want)
    } noraise {
      _ => fail("\{patch} was applied")
    }
  }
}

///|
/// A document that is not a patch, said about the operation that objected.
///
/// The answer is the position in the array, and -1 when the document itself is
/// not an array of operations.
fn refused_at(text : String) -> Int32 {
  try @patch.loads(text) |> ignore catch {
    e =>
      match e {
        Document(..) => -1
        Operation(at~, ..) => at
        _ => -2
      }
  } noraise {
    _ => -3
  }
}

///|
/// What is not a patch document, and what an operation must carry.
///
/// Members RFC 6902 §4 does not define for the operation are ignored, as it
/// says they must be — Appendix A.11 prints a patch carrying an extra `xyz`
/// and expects it applied. A required member that is missing is still an
/// error, which is what catches a misspelling.
test "a document that is not a patch" {
  let cases = [
    ("{}", -1),
    ("1", -1),
    ("\"x\"", -1),
    ("null", -1),
    ("[1]", 0),
    ("[{\"op\":\"remove\",\"path\":\"/a\"},1]", 1),
    ("[{\"path\":\"/a\"}]", 0),
    ("[{\"op\":\"nope\",\"path\":\"/a\"}]", 0),
    ("[{\"op\":\"remove\"}]", 0),
    ("[{\"op\":\"remove\",\"path\":1}]", 0),
    ("[{\"op\":\"add\",\"path\":\"/a\"}]", 0),
    ("[{\"op\":\"replace\",\"path\":\"/a\"}]", 0),
    ("[{\"op\":\"test\",\"path\":\"/a\"}]", 0),
    ("[{\"op\":\"move\",\"path\":\"/a\"}]", 0),
    ("[{\"op\":\"copy\",\"path\":\"/a\"}]", 0),
  ]
  for case in cases {
    let (text, want) = case
    assert_eq(refused_at(text), want)
  }
  // Not JSON at all is the scanner's error, unchanged and still naming the
  // line and the column.
  try @patch.loads("[") |> ignore catch {
    e =>
      match e {
        Unreadable(m) => assert_eq(m.at().line, 1)
        _ => fail("an unclosed array was read as a patch")
      }
  } noraise {
    _ => fail("an unclosed array was read as a patch")
  }
}

///|
/// RFC 6902 Appendix A.13 prints a patch with two `op` members and says there
/// is no standard error handling for duplicates. The scanner's answer is the
/// last one, so this reads as the `remove` it ends with.
test "a repeated op member" {
  assert_eq(
    @patch.loads(
      "[{\"op\":\"add\",\"path\":\"/baz\",\"value\":\"qux\",\"op\":\"remove\"}]",
    ),
    [Remove(path="/baz")],
  )
}

///|
/// Each operation sees the result of the one before it.
test "operations apply in order" {
  let doc = @json.loads("{\"a\":1}")
  let ops = @patch.loads(
    "[{\"op\":\"add\",\"path\":\"/b\",\"value\":2},{\"op\":\"replace\",\"path\":\"/b\",\"value\":3},{\"op\":\"test\",\"path\":\"/b\",\"value\":3}]",
  )
  assert_eq(@json.dumps(@patch.apply(doc, ops)), "{\"a\":1,\"b\":3}")
}

///|
/// The root is a target for `add` and `replace` (RFC 6902 §4.1) and a source
/// for `copy` and `test`, but nothing can be taken away from it.
test "the root as a target" {
  let doc = @json.loads("{\"a\":1}")
  let replaced = @patch.loads(
    "[{\"op\":\"replace\",\"path\":\"\",\"value\":[1,2]}]",
  )
  assert_eq(@json.dumps(@patch.apply(doc, replaced)), "[1,2]")
  let added = @patch.loads("[{\"op\":\"add\",\"path\":\"\",\"value\":\"z\"}]")
  assert_eq(@json.dumps(@patch.apply(doc, added)), "\"z\"")
  let copied = @patch.loads("[{\"op\":\"copy\",\"from\":\"\",\"path\":\"/c\"}]")
  assert_eq(@json.dumps(@patch.apply(doc, copied)), "{\"a\":1,\"c\":{\"a\":1}}")
  let tested = @patch.loads(
    "[{\"op\":\"test\",\"path\":\"\",\"value\":{\"a\":1}}]",
  )
  assert_eq(@patch.apply(doc, tested), doc)
  let removed = @patch.loads("[{\"op\":\"remove\",\"path\":\"\"}]")
  try @patch.apply(doc, removed) |> ignore catch {
    e => assert_eq(e, Root(path=""))
  } noraise {
    _ => fail("the root was removed")
  }
  let moved = @patch.loads("[{\"op\":\"move\",\"from\":\"\",\"path\":\"\"}]")
  try @patch.apply(doc, moved) |> ignore catch {
    e => assert_eq(e, Root(path=""))
  } noraise {
    _ => fail("the root was moved")
  }
}

///|
/// A number is compared as a number: `1` and `1.0` are one number (RFC 6902
/// §4.6), and the tree holds a number as a number rather than as text.
test "test compares values, not their text" {
  let doc = @json.loads("{\"a\":1,\"s\":\"10\"}")
  let same = @patch.loads("[{\"op\":\"test\",\"path\":\"/a\",\"value\":1.0}]")
  assert_eq(@patch.apply(doc, same), doc)
  let other = @patch.loads("[{\"op\":\"test\",\"path\":\"/s\",\"value\":10}]")
  try @patch.apply(doc, other) |> ignore catch {
    e => assert_eq(e, TestFailed(path="/s"))
  } noraise {
    _ => fail("a string tested equal to a number")
  }
}

///|
/// A move to where the value already is changes nothing — not even the order
/// of the members, which taking it away and putting it back would change.
test "a move to where it already is" {
  let doc = @json.loads("{\"x\":1,\"a\":2,\"y\":3}")
  let ops = @patch.loads("[{\"op\":\"move\",\"from\":\"/a\",\"path\":\"/a\"}]")
  assert_eq(@patch.apply(doc, ops), doc)
  // And it still has to be there.
  let absent = @patch.loads(
    "[{\"op\":\"move\",\"from\":\"/z\",\"path\":\"/z\"}]",
  )
  try @patch.apply(doc, absent) |> ignore catch {
    e => assert_eq(e, Missing(path="/z", token="z"))
  } noraise {
    _ => fail("a move from nowhere was applied")
  }
}

///|
/// A patch that fails partway applies nothing (RFC 6902 §5): the document it
/// was given is unchanged, because the answer is a new tree or an error.
test "a failed patch changes nothing" {
  let doc = @json.loads("{\"a\":1}")
  let ops = @patch.loads(
    "[{\"op\":\"add\",\"path\":\"/b\",\"value\":2},{\"op\":\"test\",\"path\":\"/b\",\"value\":99}]",
  )
  try @patch.apply(doc, ops) |> ignore catch {
    e => assert_true(e is TestFailed(_))
  } noraise {
    _ => fail("a failing patch was applied")
  }
  assert_eq(doc, @json.loads("{\"a\":1}"))
  assert_false(@pointer.has(doc, "/b"))
}

///|
/// The document it was given is the document it was given: only the path from
/// the root to the edit is rebuilt.
test "applying leaves the original alone" {
  let doc = @json.loads("{\"a\":{\"b\":1},\"c\":[1,2]}")
  let ops = @patch.loads(
    "[{\"op\":\"add\",\"path\":\"/a/d\",\"value\":2},{\"op\":\"remove\",\"path\":\"/c/0\"}]",
  )
  let after = @patch.apply(doc, ops)
  assert_eq(@json.dumps(after), "{\"a\":{\"b\":1,\"d\":2},\"c\":[2]}")
  assert_eq(@json.dumps(doc), "{\"a\":{\"b\":1},\"c\":[1,2]}")
}

///|
/// A patch read and written again comes back unchanged — the round-trip
/// criterion the family holds every format to — and the bytes face agrees with
/// the text one.
test "a patch round-trips" {
  let ops = @patch.loads(
    "[{\"op\":\"add\",\"path\":\"/a/b\",\"value\":[1,2]},{\"op\":\"remove\",\"path\":\"/c\"},{\"op\":\"replace\",\"path\":\"/d\",\"value\":{\"e\":null}},{\"op\":\"move\",\"from\":\"/f\",\"path\":\"/g\"},{\"op\":\"copy\",\"from\":\"/h\",\"path\":\"/i\"},{\"op\":\"test\",\"path\":\"/j\",\"value\":\"k\"}]",
  )
  assert_eq(@patch.loads(@patch.dumps(ops)), ops)
  assert_eq(@patch.load(@patch.dump(ops)[:]), ops)
}

///|
/// The writer puts the members where RFC 6902's examples put them, and accepts
/// them in any order coming in.
test "a patch is written as the RFC writes one" {
  let ops = @patch.loads(
    "[{\"path\":\"/c\",\"value\":1,\"op\":\"test\"},{\"path\":\"/b\",\"from\":\"/a\",\"op\":\"move\"}]",
  )
  assert_eq(
    @patch.dumps(ops),
    "[{\"op\":\"test\",\"path\":\"/c\",\"value\":1},{\"op\":\"move\",\"from\":\"/a\",\"path\":\"/b\"}]",
  )
  // The writer's arguments do what they say.
  let one = @patch.loads("[{\"op\":\"add\",\"path\":\"/a\",\"value\":1}]")
  assert_eq(
    @patch.dumps(one, indent=2),
    "[\n  {\n    \"op\": \"add\",\n    \"path\": \"/a\",\n    \"value\": 1\n  }\n]",
  )
  assert_eq(@patch.dumps(one, ascii=true), @patch.dumps(one))
}
