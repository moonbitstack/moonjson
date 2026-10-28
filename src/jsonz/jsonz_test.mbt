// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "json5-style features parse" {
  let doc = @jsonz.loads("{a: 1, /* a comment */ b: 'two'}")
  assert_eq(@json.dumps(doc), "{\"a\":1,\"b\":\"two\"}")
}

///|
test "round-trip through UTF-8 bytes" {
  let doc = @jsonz.load(@utf8.encode("{\"x\": [1, 2, 3], y: true}")[:])
  assert_eq(@json.dumps(doc), "{\"x\":[1,2,3],\"y\":true}")
}
