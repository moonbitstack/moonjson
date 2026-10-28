// ZJSON (Zed JSON) — https://github.com/brimdata/zed/blob/main/docs/formats/zjson.md
//
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A representative ZJSON value: a Zed record with a typed `ts`, an `int64`, and
/// an `ipaddr`, each carried as a `{"type", "value"}` object in a JSON array.
let records : String =
  #|[
  #|  {
  #|    "type": {
  #|      "id": 0, "kind": "record",
  #|      "fields": [
  #|        {"name": "ts", "type": {"kind": "primitive", "name": "time"}},
  #|        {"name": "a", "type": {"kind": "primitive", "name": "string"}},
  #|        {"name": "b", "type": {
  #|          "id": 1, "kind": "record",
  #|          "fields": [
  #|            {"name": "x", "type": {"kind": "primitive", "name": "int64"}},
  #|            {"name": "y", "type": {"kind": "primitive", "name": "ip"}}
  #|          ]
  #|        }}
  #|      ]
  #|    },
  #|    "value": [
  #|      "2020-01-01T00:00:00Z",
  #|      "hello, world",
  #|      ["4611686018427387904", "127.0.0.1"]
  #|    ]
  #|  }
  #|]

///|
/// A ZJSON document is valid JSON, so reading it through this package must yield
/// exactly the tree `@json.loads` reads from the same text — `type` and `value`
/// included.
test "a ZJSON document reads the same as plain JSON" {
  assert_eq(@zjson.loads(records), @json.loads(records))
}

///|
/// Reading the same document from bytes (no BOM) gives the same tree, because the
/// ZJSON envelope is ordinary JSON either way.
test "the document reads the same from bytes" {
  assert_eq(@zjson.load(@utf8.encode(records)), @json.loads(records))
}

///|
/// The package is a pass-through, so `loads` → `dumps` → `@json.loads` returns
/// the same tree. The Zed types survive as the preserved `type` member — a `Json`
/// tree has no richer type to rebuild them into.
test "loads then dumps then json.loads round-trips the structure" {
  let tree = @zjson.loads(records)
  let written = @zjson.dumps(tree)
  assert_eq(@json.loads(written), tree)
}

///|
/// `dump` produces the UTF-8 bytes of the same JSON `dumps` writes.
test "dump matches dumps" {
  let tree = @zjson.loads(records)
  let bytes = @zjson.dump(tree)
  assert_eq(bytes, @utf8.encode(@zjson.dumps(tree)))
}

///|
/// A simple ZJSON scalar value round-trips unchanged through the JSON delegation.
test "a scalar ZJSON value round-trips" {
  let scalar =
    #|{"type": {"kind": "primitive", "name": "int64"}, "value": "123"}
  let tree = @zjson.loads(scalar)
  assert_eq(@json.loads(@zjson.dumps(tree, indent=2)), tree)
}
