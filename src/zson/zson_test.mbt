// ZSON — https://github.com/postgrespro/zson
//
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A ZSON value is `jsonb`, i.e. JSON. Reading it through this package must
/// therefore yield exactly the tree `@json.loads` reads from the same text.
test "a ZSON value reads the same as plain JSON" {
  let doc =
    #|{"name": "ZSON", "compressed": true, "ratio": 0.5, "keys": ["a", "b"]}
  assert_eq(@zson.loads(doc), @json.loads(doc))
}

///|
/// Reading the same value from bytes (no BOM) gives the same tree, because the
/// compressed payload is JSON either way.
test "the same value reads the same from bytes" {
  assert_eq(
    @zson.load(@utf8.encode("{ \"x\": 1 }")),
    @json.loads("{ \"x\": 1 }"),
  )
}

///|
/// The package is a pass-through, so `loads` → `dumps` → `@json.loads` returns
/// the same tree — ZSON's compression is PostgreSQL's concern, not this reader's.
test "loads then dumps then json.loads round-trips the structure" {
  let tree = @zson.loads("{ \"a\": [1, 2, 3], \"b\": \"hello\" }")
  let written = @zson.dumps(tree)
  assert_eq(@json.loads(written), tree)
}

///|
/// `dump` produces the UTF-8 bytes of the same JSON `dumps` writes.
test "dump matches dumps" {
  let tree = @zson.loads("{ \"ok\": true }")
  let bytes = @zson.dump(tree)
  assert_eq(bytes, @utf8.encode(@zson.dumps(tree)))
}

///|
/// A nested value round-trips unchanged through the JSON delegation.
test "a deeply nested value round-trips" {
  let doc =
    #|{
    #|  "user": { "id": 7, "tags": ["x", "y"] },
    #|  "score": 42.5,
    #|  "active": false,
    #|  "meta": null
    #|}
  let tree = @zson.loads(doc)
  assert_eq(@json.loads(@zson.dumps(tree, indent=2)), tree)
}
