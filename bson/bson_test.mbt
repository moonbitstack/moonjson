// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The two documents bsonspec.org prints, byte for byte.
let examples : Array[(String, String)] = [
  ("160000000268656c6c6f0006000000776f726c640000", "{\"hello\":\"world\"}"),
  (
    "310000000442534f4e002600000002300008000000617765736f6d65000131003333333333331440103200c20700000000",
    "{\"BSON\":[\"awesome\",5.05,1986]}",
  ),
]

///|
test "the specification's examples" {
  for row in examples {
    let (hex, want) = row
    let bytes = @hex.decode(hex[:])
    assert_eq(@json.dumps(@bson.load(bytes[:])), want)
    assert_eq(@hex.encode(@bson.dump(@bson.load(bytes[:]))[:]), hex)
  }
}

///|
/// Every type BSON has and JSON has not: each one is a marker, and each one
/// comes back as the type it was.
test "the types JSON has no syntax for" {
  let cases : Array[String] = [
    "{\"$oid\":\"507f1f77bcf86cd799439011\"}", "{\"$bytes\":\"deadbeef\"}", "{\"$binary\":{\"kind\":4,\"data\":\"0102\"}}",
    "{\"$date\":1356350400000}", "{\"$regex\":\"^a.*z$\",\"options\":\"i\"}", "{\"$dbpointer\":{\"ns\":\"db.col\",\"oid\":\"507f1f77bcf86cd799439011\"}}",
    "{\"$code\":\"function(){}\"}", "{\"$code\":\"function(){}\",\"$scope\":{\"x\":1}}",
    "{\"$symbol\":\"sym\"}", "{\"$timestamp\":{\"t\":1132432976,\"i\":4294967295}}",
    "{\"$decimal128\":\"01000000000000000000000000003c30\"}", "{\"$minkey\":true}",
    "{\"$maxkey\":true}", "{\"$undefined\":true}",
  ]
  for text in cases {
    let doc = @json.loads("{\"v\":" + text + "}")
    let bytes = @bson.dump(doc)
    assert_eq(@json.dumps(@bson.load(bytes[:])), @json.dumps(doc))
  }
}

///|
/// An array is a document whose names are numbers, and it comes back an array.
test "an array is a document with numbered names" {
  let doc = @json.loads("{\"a\":[1,[2,3],{\"b\":null}]}")
  assert_eq(@json.dumps(@bson.load(@bson.dump(doc)[:])), @json.dumps(doc))
}

///|
/// A document is one object; anything else has no encoding.
test "a document is an object" {
  try @bson.dump(Json::number(1)) |> ignore catch {
    e => assert_true(e is @moonjson.Unwritable(_))
  } noraise {
    _ => fail("a number was written as a document")
  }
}

///|
/// The length in the header is checked against the terminators.
test "a document whose length is not its own" {
  let lying = @hex.decode("120000000268656c6c6f0006000000776f726c640000")
  try @bson.load(lying[:]) |> ignore catch {
    e => assert_true(e is @moonjson.Short(_) || e is @moonjson.Bad(..))
  } noraise {
    _ => fail("a document shorter than its header claims was read")
  }
}
