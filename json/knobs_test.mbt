// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The two ways to describe a dialect must describe the same dialect.
test "the constructor and the record update agree" {
  let built = @moonjson.Flavor::new(depth=100, duplicates=Reject)
  let updated : @moonjson.Flavor = {
    ..@moonjson.strict,
    depth: 100,
    duplicates: Reject,
  }
  assert_eq(built, updated)
  // And the presets are what the constructor's defaults are taken from.
  assert_eq(@moonjson.Flavor::new(), @moonjson.strict)
}

///|
/// The nesting bound is a number somebody should be able to choose. The
/// mainstream disagrees on which number — Jackson refuses past 1000, serde_json
/// past 128 — so ours is a default, not a law.
test "the depth bound is a knob" {
  let deep = StringBuilder()
  for _ in 0..<200 {
    deep.write_char('[')
  }
  for _ in 0..<200 {
    deep.write_char(']')
  }
  let text = deep.to_string()
  // The default admits it.
  @json.loads(text[:]) |> ignore
  // A tighter dialect does not.
  try
    @json.loads(text[:], flavor={ ..@moonjson.strict, depth: 100, }) |> ignore
  catch {
    e => assert_true(e is TooDeep(_))
  } noraise {
    _ => fail("two hundred levels passed a bound of one hundred")
  }
  // And a looser one admits what the default refuses.
  let deeper = StringBuilder()
  for _ in 0..<600 {
    deeper.write_char('[')
  }
  for _ in 0..<600 {
    deeper.write_char(']')
  }
  try @json.loads(deeper.to_string()[:]) |> ignore catch {
    e => assert_true(e is TooDeep(_))
  } noraise {
    _ => fail("six hundred levels passed the default bound")
  }
  @json.loads(deeper.to_string()[:], flavor=@moonjson.Flavor::new(depth=1000))
  |> ignore
}

///|
/// A lone half of a surrogate pair: refused by default because it cannot be
/// written back out, tolerated on request because JavaScript tolerates it and
/// somebody has to read what JavaScript wrote.
test "lone surrogates are a knob" {
  let text = "[\"\\uD800\"]"
  try @json.loads(text[:]) |> ignore catch {
    e => assert_true(e is BadEscape(_))
  } noraise {
    _ => fail("a lone surrogate passed by default")
  }
  let lenient : @moonjson.Flavor = { ..@moonjson.strict, surrogates: true, }
  assert_eq(@json.dumps(@json.loads(text[:], flavor=lenient)), "[\"\u{FFFD}\"]")
  // A whole pair is a character either way.
  let pair = "[\"\\uD834\\uDD1E\"]"
  assert_eq(@json.loads(pair[:]), @json.loads(pair[:], flavor=lenient))
}

///|
/// A repeated member name: the last one wins, as everywhere else, unless the
/// caller wants to hear about it.
test "repeated names are a knob" {
  let text = "{\"a\":1,\"a\":2}"
  assert_eq(@json.dumps(@json.loads(text[:])), "{\"a\":2}")
  assert_eq(
    @json.dumps(
      @json.loads(text[:], flavor={ ..@moonjson.strict, duplicates: First, }),
    ),
    "{\"a\":1}",
  )
  try
    @json.loads(text[:], flavor={ ..@moonjson.strict, duplicates: Reject, })
    |> ignore
  catch {
    e => assert_true(e is Repeated(_, _))
  } noraise {
    _ => fail("a repeated name passed a dialect that refuses them")
  }
  // A name that is not repeated is fine under all three.
  for how in [@moonjson.Last, @moonjson.First, @moonjson.Reject] {
    @json.loads("{\"a\":1,\"b\":2}", flavor={
      ..@moonjson.strict,
      duplicates: how,
    })
    |> ignore
  }
}

///|
/// A byte-order mark: skipped by default, because refusing it would mean
/// refusing half the files Windows tooling produces.
test "the byte-order mark is a knob" {
  let marked = b"\xEF\xBB\xBF[1,2]"
  assert_eq(@json.load(marked[:]), @json.loads("[1,2]"))
  try @json.load(marked[:], bom=false) |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("a byte-order mark passed with bom=false")
  }
}

///|
/// Writing: the compact form, the indented form, the ASCII-safe form and the
/// sorted form are four answers to four different questions.
test "the writer's three knobs" {
  let value = @json.loads("{\"b\":1,\"a\":\"\u{9AC7}\u{5154}\",\"c\":[1,2]}")
  assert_eq(
    @json.dumps(value),
    "{\"b\":1,\"a\":\"\u{9AC7}\u{5154}\",\"c\":[1,2]}",
  )
  assert_eq(
    @json.dumps(value, ascii=true),
    "{\"b\":1,\"a\":\"\\u9ac7\\u5154\",\"c\":[1,2]}",
  )
  assert_eq(
    @json.dumps(value, sort=true),
    "{\"a\":\"\u{9AC7}\u{5154}\",\"b\":1,\"c\":[1,2]}",
  )
  assert_eq(
    @json.dumps(value, ascii=true, sort=true),
    "{\"a\":\"\\u9ac7\\u5154\",\"b\":1,\"c\":[1,2]}",
  )
  // The escaped form reads back as the same tree.
  assert_eq(@json.loads(@json.dumps(value, ascii=true)[:]), value)
  // Control characters are escaped whether or not `ascii` is on.
  let control = @json.loads("[\"\\u0007\"]")
  assert_eq(@json.dumps(control), "[\"\\u0007\"]")
  assert_eq(@json.dumps(control, ascii=true), "[\"\\u0007\"]")
}

///|
/// A dialect is a value: a caller can build one that is in no preset and hand
/// it to any of the four readers.
test "a dialect of one's own" {
  // JSON with comments and nothing else — not one of the three presets.
  let mine : @moonjson.Flavor = { ..@moonjson.strict, comments: true, }
  assert_eq(@json.dumps(@json.loads("/* hi */ [1]", flavor=mine)), "[1]")
  try @json.loads("[1,]", flavor=mine) |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("a trailing comma passed a dialect that only adds comments")
  }
}
