// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a json11 payload is plain JSON" {
  let doc = @json11.loads(
    "{\"key1\":\"value1\",\"key2\":false,\"key3\":[1,2,3]}",
  )
  assert_eq(
    @json.dumps(doc),
    "{\"key1\":\"value1\",\"key2\":false,\"key3\":[1,2,3]}",
  )
}

///|
test "round-trip through UTF-8 bytes" {
  let doc = @json11.load(@utf8.encode("{\"point\":[1,2]}")[:])
  assert_eq(@json.dumps(doc), "{\"point\":[1,2]}")
}
