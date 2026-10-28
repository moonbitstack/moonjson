// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a small document round-trips" {
  let doc = @json.loads(
    "{\"a\":1,\"b\":[true,null,\"hi\"],\"c\":-42,\"pi\":3.14159}",
  )
  let bytes = @bjson.dump(doc)
  assert_eq(@json.dumps(@bjson.load(bytes[:])), @json.dumps(doc))
}

///|
test "binary bytes survive as $bytes" {
  let doc = @json.loads("{\"blob\":{\"$bytes\":\"deadbeef\"}}")
  let bytes = @bjson.dump(doc)
  assert_eq(@json.dumps(@bjson.load(bytes[:])), @json.dumps(doc))
}

///|
test "undefined survives" {
  let doc = @json.loads("{\"x\":{\"$undefined\":true}}")
  let bytes = @bjson.dump(doc)
  assert_eq(@json.dumps(@bjson.load(bytes[:])), @json.dumps(doc))
}

///|
test "nested objects and arrays round-trip" {
  let doc = @json.loads("{\"m\":{\"k\":[1,[2,3],{\"z\":null}]},\"flag\":false}")
  let bytes = @bjson.dump(doc)
  assert_eq(@json.dumps(@bjson.load(bytes[:])), @json.dumps(doc))
}
