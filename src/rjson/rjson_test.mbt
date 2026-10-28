// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "an rjson payload is plain JSON" {
  let doc = @rjson.loads("{\"a\":1,\"b\":[true,null,\"x\"]}")
  assert_eq(@json.dumps(doc), "{\"a\":1,\"b\":[true,null,\"x\"]}")
}

///|
test "round-trip through UTF-8 bytes" {
  let doc = @rjson.load(@utf8.encode("{\"n\":42}")[:])
  assert_eq(@json.dumps(doc), "{\"n\":42}")
}
