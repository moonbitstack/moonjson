// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Documents come back one at a time, in order, and then the stream ends.
test "reads documents one at a time" {
  let src = @source.Source::new(@utf8.encode("{\"a\":1}\n[1,2]\n"[:]))
  assert_eq(src.read(), Some(@json.loads("{\"a\":1}")))
  assert_eq(src.read(), Some(@json.loads("[1,2]")))
  assert_eq(src.read(), None)
  assert_eq(src.length(), 2)
}

///|
/// A sequence written by the sink reads back unchanged.
test "round trips a sequence written by the sink" {
  let values = [
    @json.loads("{\"a\":1}"),
    @json.loads("[true,null]"),
    @json.loads("\"x\""),
  ]
  let sink = @sink.Sink::new()
  for value in values {
    sink.write(value)
  }
  let src = @source.Source::new(sink.to_bytes()[:])
  let back : Array[Json] = []
  let mut going = true
  while going {
    match src.read() {
      Some(value) => back.push(value)
      None => going = false
    }
  }
  assert_eq(back, values)
}
