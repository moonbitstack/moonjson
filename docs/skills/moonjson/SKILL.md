---
name: moonjson
description: "The JSON family for MoonBit: one tree, and a package for each way of writing it. Use it to read or write JSON, JSONC, JSON5, JSON Lines, or a binary encoding such as CBOR, MessagePack or BSON, and to change or query a document with a JSON Pointer, a patch or JSONPath."
---

# moonjson

```bash
moon add moonbitstack/moonjson
```

```moonbit
import {
  "moonbitstack/moonjson/json",
  "moonbitstack/moonjson/pointer",
}
```

Each notation is a package with the same four verbs — `loads`, `load`, `dumps`,
`dump` — and all of them read into core's `Json`, so a tree read by one package
is written by another with no conversion. There is a package per notation
(`jsonc`, `json5`, `cbor`, `msgpack`, `path`, …); import the ones you call.

## Read a document, write it back

`loads` takes a string, `load` takes bytes; the `s` is the only difference.

```moonbit
let config = @json.loads("{\"host\":\"localhost\",\"port\":8080}")
assert_eq(@json.dumps(config), "{\"host\":\"localhost\",\"port\":8080}")
assert_eq(@json.dumps(config, indent=2), "{\n  \"host\": \"localhost\",\n  \"port\": 8080\n}")
assert_eq(@json.loads(@json.dumps(config)), config)
```

Writing is always strict JSON, whatever the document was written in. The other
readers are the same call under another name: `@jsonc` allows comments and a
trailing comma, `@json5` adds unquoted names, single quotes and hexadecimal,
`@hjson` and `@cson` are lenient readers of their own, and `@lines` is the one
that takes a stream.

```moonbit
let commented = @jsonc.loads("{\"port\": 8080,  // the one we bound\n}")
assert_eq(@json.dumps(commented), "{\"port\":8080}")
assert_eq(@lines.loads_all("{\"n\":1}\n{\"n\":2}\n").length(), 2)
```

## Change a document, or ask it a question

One place is named by a pointer (RFC 6901), a list of operations is a patch
(RFC 6902), a patch that looks like the document is a merge patch (RFC 7396),
and a query with filters is JSONPath (RFC 9535).

```moonbit
let cfg = @json.loads("{\"spec\":{\"replicas\":1,\"image\":\"app:1\"}}")
let wanted = @pointer.set(cfg, "/spec/replicas", Json::number(5))
assert_eq(@json.dumps(wanted), "{\"spec\":{\"replicas\":5,\"image\":\"app:1\"}}")
assert_eq(@json.dumps(@pointer.get(wanted, "/spec/replicas")), "5")

let ops = @patch.loads("[{\"op\":\"replace\",\"path\":\"/spec/replicas\",\"value\":5}]")
assert_eq(@json.dumps(@patch.apply(cfg, ops)), "{\"spec\":{\"replicas\":5,\"image\":\"app:1\"}}")
assert_eq(@json.dumps(@merge.merge(cfg, @json.loads("{\"spec\":{\"image\":null}}"))), "{\"spec\":{\"replicas\":1}}")

let books = @json.loads("{\"book\":[{\"title\":\"A\",\"price\":8.95},{\"title\":\"B\",\"price\":12.99}]}")
let cheap = @path.select(books, "$.book[?@.price < 10].title")
assert_eq(@json.dumps(Json::array(cheap)), "[\"A\"]")
```

`@path.compile` returns a `Path` to run against any number of documents. A
patch applies all its operations or none: when one fails, nothing is changed.

## The same tree as bytes

A binary format has the two verbs that take bytes. CBOR, MessagePack, BSON,
UBJSON, Smile, BJSON, KRSON, CompactBinaryData and the two `jsonb` dialects each
have a package of their own.

```moonbit
let body = @cbor.dump(cfg)
assert_eq(@cbor.load(body[:]), cfg)
assert_eq(@json.dumps(@msgpack.load(@msgpack.dump(cfg)[:])), "{\"spec\":{\"replicas\":1,\"image\":\"app:1\"}}")
```

What JSON has no syntax for — a byte string, a tag, `undefined`, a map whose
keys are not strings, an ObjectId, a date — travels through JSON as a marker
such as `{"$bytes":"0102"}` or `{"$oid":"507f…"}`, and writing reads the same
markers back. A marker name is reserved: an object whose only member is `$oid`
is an ObjectId, not a document that happens to have that member.

## Rules that catch people out

- `Refused` is the one error type for the whole family. `at()` answers the
  offset, line and column for a text format and `None` for a binary one, whose
  variants carry a byte offset instead; `message()` writes the sentence.
- `loads` answers one document and refuses anything after it. A buffer holding
  several values is read with `@moonjson.Decoder`: `read()` answers the next
  value or `None`, and `offset()` is where that value ended.
- A number keeps the text it was written as, so `1e400` and a twenty-digit
  integer come back unchanged. JSON5's `Infinity` and `NaN` have no JSON
  syntax and are written as `null`.
- Nesting past 500 levels is refused rather than taken to the stack, and a lone
  half of a surrogate pair is refused, because it cannot be written back out.
- How to read is a `Flavor` record: the dialect's preset is the base and the one
  you pass lies over it. `@moonjson.Flavor::new(depth=100)` and
  `{ ..@moonjson.strict, duplicates: @moonjson.Duplicates::First }` build the
  same kind of value.
- `duplicates` is `Last` by default; `@moonjson.Duplicates::Reject` says a
  repeated member name is an error worth hearing about.
- CBOR's default deterministic encoding sorts the members of a map (RFC 8949
  §4.2.1), so a round trip through it returns an equal tree in that order.
  `@cbor.Policy::new(deterministic=false)` keeps the order the document had.
- Writing has no `to_string`: that name is `Show`'s in MoonBit. Use `dumps`,
  which takes `indent`, `ascii` and `sort`.
