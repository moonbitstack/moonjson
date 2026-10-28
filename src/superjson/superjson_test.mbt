// Superjson — https://github.com/blitz-js/superjson
//
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A representative superjson envelope: a payload carrying a `Date` (named in
/// `meta.values` by its JSON pointer path) alongside the usual mix of JSON
/// value kinds. It is, underneath, plain JSON.
let envelope : String =
  #|{
  #|  "json": {
  #|    "name": "Alice",
  #|    "age": 30,
  #|    "active": true,
  #|    "tags": ["a", "b"],
  #|    "when": "2023-01-01T00:00:00.000Z"
  #|  },
  #|  "meta": {
  #|    "values": { "when": "Date" },
  #|    "map": {},
  #|    "set": {}
  #|  }
  #|}

///|
/// A superjson payload is valid JSON, so reading it through this package must
/// yield exactly the tree `@json.loads` reads from the same text — envelope and
/// all, with `json` and `meta` preserved verbatim.
test "the envelope parses the same as plain JSON" {
  assert_eq(@superjson.loads(envelope), @json.loads(envelope))
}

///|
/// Reading a payload as bytes (no BOM) gives the same tree as reading it as
/// text: the envelope is ordinary JSON either way.
test "the envelope parses the same from bytes" {
  assert_eq(@superjson.load(@utf8.encode(envelope)), @json.loads(envelope))
}

///|
/// The package is a pass-through, so `loads` → `dumps` → `@json.loads` returns
/// the same tree as the original `loads`. The structure survives the round
/// trip, which is all a `Json` tree without `Date`/`BigInt`/`Map`/`Set` can
/// promise: the typed values live on as their plain JSON, and the type table
/// lives on as the verbatim `meta`.
test "loads then dumps then json.loads round-trips the structure" {
  let tree = @superjson.loads(envelope)
  let written = @superjson.dumps(tree)
  assert_eq(@json.loads(written), tree)
}

///|
/// Writing a payload with indentation still round-trips: whitespace never
/// changes the tree.
test "dumps with indent round-trips" {
  let tree = @superjson.loads(envelope)
  let written = @superjson.dumps(tree, indent=2)
  assert_eq(@json.loads(written), tree)
}

///|
/// `dump` produces the UTF-8 bytes of the same JSON `dumps` writes.
test "dump matches dumps" {
  let tree = @superjson.loads(envelope)
  let bytes = @superjson.dump(tree)
  assert_eq(bytes, @utf8.encode(@superjson.dumps(tree)))
}
