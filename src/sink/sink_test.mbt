// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Each document is written in the compact form, then a line feed.
test "one compact document per line" {
  let sink = @sink.Sink::new()
  sink.write(@json.loads("{\"a\":1}"))
  sink.write(@json.loads("[1,2]"))
  assert_eq(sink.length(), 2)
  assert_eq(sink.to_string(), "{\"a\":1}\n[1,2]\n")
}

///|
/// What the sink writes is what the batch writer writes, byte for byte.
test "agrees with lines.dumps_all" {
  let values = [@json.loads("{\"a\":1}"), @json.loads("[true,null]")]
  let sink = @sink.Sink::new()
  for value in values {
    sink.write(value)
  }
  assert_eq(sink.to_string(), @lines.dumps_all(values))
}
