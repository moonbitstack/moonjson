// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Every binary format reads back the sample unchanged.
test "every binary round-trips the sample" {
  let t = @roundtrip.sample()
  assert_eq(@cbor.load(@cbor.dump(t)[:]), t)
  assert_eq(@msgpack.load(@msgpack.dump(t)[:]), t)
  assert_eq(@bson.load(@bson.dump(t)[:]), t)
  assert_eq(@ubjson.load(@ubjson.dump(t)[:]), t)
  assert_eq(@smile.load(@smile.dump(t)[:]), t)
  assert_eq(@bjson.load(@bjson.dump(t)[:]), t)
  assert_eq(@krson.load(@krson.dump(t)[:]), t)
  assert_eq(@cbd.load(@cbd.dump(t)[:]), t)
  assert_eq(@sqlite.load(@sqlite.dump(t)[:]), t)
  assert_eq(@pg.load(@pg.dump(t)[:]), t)
}

///|
/// Every text dialect reads back the sample unchanged.
test "every text dialect round-trips the sample" {
  let t = @roundtrip.sample()
  assert_eq(@json.loads(@json.dumps(t)[:]), t)
  assert_eq(@jsonc.loads(@jsonc.dumps(t)[:]), t)
  assert_eq(@json5.loads(@json5.dumps(t)[:]), t)
  assert_eq(@hjson.loads(@hjson.dumps(t)[:]), t)
  assert_eq(@cson.loads(@cson.dumps(t)[:]), t)
  assert_eq(@superjson.loads(@superjson.dumps(t)[:]), t)
  assert_eq(@ntv.loads(@ntv.dumps(t)[:]), t)
  assert_eq(@rjson.loads(@rjson.dumps(t)[:]), t)
  assert_eq(@json11.loads(@json11.dumps(t)[:]), t)
  assert_eq(@jsonz.loads(@jsonz.dumps(t)[:]), t)
  assert_eq(@zson.loads(@zson.dumps(t)[:]), t)
  assert_eq(@zjson.loads(@zjson.dumps(t)[:]), t)
}

///|
/// A format can cross to another: JSON in, CBOR out, SQLite jsonb on, and back.
test "a tree crosses formats" {
  let t = @roundtrip.sample()
  let cbor = @cbor.dump(t)
  let again = @cbor.load(cbor[:])
  let sqlite = @sqlite.dump(again)
  let third = @sqlite.load(sqlite[:])
  let pg = @pg.dump(third)
  let last = @pg.load(pg[:])
  assert_eq(last, t)
}

///|
/// The streaming pair carries a sequence of the sample unchanged.
test "the streaming pair round-trips a sequence" {
  let t = @roundtrip.sample()
  let sink = @sink.Sink::new()
  sink.write(t)
  sink.write(t)
  let src = @source.Source::new(sink.to_bytes()[:])
  assert_eq(src.read(), Some(t))
  assert_eq(src.read(), Some(t))
  assert_eq(src.read(), None)
}

///|
/// The formatter lays the sample out and the reader gets the same tree back.
test "the formatter preserves the tree" {
  let t = @roundtrip.sample()
  let text = @pretty.format(t, style=@pretty.Format::new(indent=4, sort=true))
  assert_eq(@json.loads(text[:]), t)
}

///|
/// The exact snippets the examples page shows, so the page cannot drift from
/// what the library really prints.
test "the examples page outputs" {
  assert_eq(
    @json.dumps(@hjson.loads("{ a: 1, b: [2, 3] }"), sort=true),
    "{\"a\":1,\"b\":[2,3]}",
  )
  assert_eq(
    @json.dumps(@cson.loads("a: 1\nb:\n  - 2\n  - 3\n"), sort=true),
    "{\"a\":1,\"b\":[2,3]}",
  )
  let cfg = @json.loads("{\"tls\":false,\"host\":\"localhost\",\"port\":8080}")
  assert_eq(
    @pretty.format(cfg, style=@pretty.Format::new(indent=4, sort=true)),
    "{\n    \"host\": \"localhost\",\n    \"port\": 8080,\n    \"tls\": false\n}",
  )
  let john = @json.loads("{\"name\":\"John\",\"age\":30}")
  assert_eq(
    @hex.encode(@cbd.dump(john)[:]),
    "cbd1010002046e616d6503616765a1020160044a6f686e02401e",
  )
  assert_eq(@cbd.load(@cbd.dump(john)[:]), john)
  let t = @json.loads("{\"a\":1,\"b\":[true,null]}")
  let cbor = @cbor.dump(t)
  let sqlite = @sqlite.dump(@cbor.load(cbor[:]))
  let pg = @pg.dump(@sqlite.load(sqlite[:]))
  assert_eq(@pg.load(pg[:]), t)
}
