// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A document with something to edit at every depth: a member, an element, a
/// nested object, and a scalar to walk into and be refused.
fn tree() -> Json {
  Json::object({
    "foo": Json::array([Json::string("bar"), Json::string("baz")]),
    "spec": Json::object({
      "replicas": Json::number(1),
      "image": Json::string("greeter:1"),
    }),
    "count": Json::number(7),
  })
}

///|
/// Read, change one field, write back — the three lines this exists for.
test "a field changes and nothing else does" {
  let before = tree()
  let after = @pointer.set(before, "/spec/replicas", Json::number(5))
  assert_eq(@pointer.get(after, "/spec/replicas"), Json::number(5))
  // Its neighbours are untouched.
  assert_eq(@pointer.get(after, "/spec/image"), Json::string("greeter:1"))
  assert_eq(@pointer.get(after, "/count"), Json::number(7))
  assert_eq(@pointer.get(after, "/foo/0"), Json::string("bar"))
  // And the document it was given is the document it was given.
  assert_eq(@pointer.get(before, "/spec/replicas"), Json::number(1))
  assert_eq(before, tree())
}

///|
/// A name that is not there is created; one that is, is replaced. That is RFC
/// 6902's `add` and `replace` taken together, which is what a caller editing a
/// configuration means either way.
test "a member is created or replaced" {
  let added = @pointer.set(tree(), "/spec/port", Json::number(12000))
  assert_eq(@pointer.get(added, "/spec/port"), Json::number(12000))
  let replaced = @pointer.set(added, "/spec/port", Json::number(12001))
  assert_eq(@pointer.get(replaced, "/spec/port"), Json::number(12001))
  // At the root as well.
  let top = @pointer.set(tree(), "/extra", Json::boolean(true))
  assert_eq(@pointer.get(top, "/extra"), Json::boolean(true))
}

///|
/// An element is replaced by index, and `-` appends — the one place RFC 6901 §4
/// gives that token a meaning, and the reason `get` refuses it.
test "an element is replaced by index, and a dash appends" {
  let changed = @pointer.set(tree(), "/foo/1", Json::string("qux"))
  assert_eq(
    @pointer.get(changed, "/foo"),
    Json::array([Json::string("bar"), Json::string("qux")]),
  )
  let grown = @pointer.set(tree(), "/foo/-", Json::string("third"))
  assert_eq(
    @pointer.get(grown, "/foo"),
    Json::array([
      Json::string("bar"),
      Json::string("baz"),
      Json::string("third"),
    ]),
  )
  // `-` names a place that does not exist yet, so reading it is refused.
  try @pointer.get(tree(), "/foo/-") |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("a dash was read as an index")
  }
}

///|
/// A pointer that runs past the end of the document is a pointer to nowhere.
/// Inventing the objects along the way would make a typo succeed quietly.
test "a path that does not exist is not invented" {
  try @pointer.set(tree(), "/nope/deeper", Json::number(1)) |> ignore catch {
    e => assert_eq(e, @pointer.Missing(token="nope"))
  } noraise {
    _ => fail("a pointer through a missing object was followed")
  }
  // Walking into a scalar and continuing is refused too.
  try @pointer.set(tree(), "/count/deeper", Json::number(1)) |> ignore catch {
    e => assert_eq(e, @pointer.NotContainer(token="deeper"))
  } noraise {
    _ => fail("a pointer walked into a number")
  }
  // An index past the end is not an append.
  try @pointer.set(tree(), "/foo/9", Json::string("x")) |> ignore catch {
    e => assert_eq(e, @pointer.Missing(token="9"))
  } noraise {
    _ => fail("an index past the end was accepted")
  }
}

///|
/// Taking something away leaves the rest as it was.
test "a member and an element are removed" {
  let without = @pointer.remove(tree(), "/spec/image")
  assert_false(@pointer.has(without, "/spec/image"))
  assert_eq(@pointer.get(without, "/spec/replicas"), Json::number(1))
  let shorter = @pointer.remove(tree(), "/foo/0")
  assert_eq(@pointer.get(shorter, "/foo"), Json::array([Json::string("baz")]))
  // What was never there cannot be taken away.
  try @pointer.remove(tree(), "/spec/nope") |> ignore catch {
    e => assert_eq(e, @pointer.Missing(token="nope"))
  } noraise {
    _ => fail("a member that was not there was removed")
  }
  // The root names the whole document; there would be nothing to answer with.
  try @pointer.remove(tree(), "") |> ignore catch {
    e => assert_eq(e, @pointer.Syntax(at=0))
  } noraise {
    _ => fail("the root was removed")
  }
}

///|
/// A name with a slash or a tilde in it is escaped the same way going in as
/// coming out, so a key called `a/b` is one key.
test "an escaped name is one name" {
  let tricky = @pointer.set(Json::object({}), "/a~1b", Json::number(1))
  assert_eq(@pointer.get(tricky, "/a~1b"), Json::number(1))
  assert_eq(@pointer.escape("a/b"[:]), "a~1b")
  let tilde = @pointer.set(Json::object({}), "/m~0n", Json::number(2))
  assert_eq(@pointer.get(tilde, "/m~0n"), Json::number(2))
}
