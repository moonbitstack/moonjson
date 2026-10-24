// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The examples from RFC 8949 Appendix A, as the tree this family reads into.
/// The tree is written back as JSON so the expectation can be read, which is
/// also the point of the family: one document, several notations.
let examples : Array[(String, String)] = [
  ("00", "0"),
  ("01", "1"),
  ("0a", "10"),
  ("17", "23"),
  ("1818", "24"),
  ("1903e8", "1000"),
  ("1a000f4240", "1000000"),
  ("1b000000e8d4a51000", "1000000000000"),
  ("1bffffffffffffffff", "18446744073709551615"),
  ("c249010000000000000000", "18446744073709551616"),
  ("3bffffffffffffffff", "-18446744073709551616"),
  ("c349010000000000000000", "-18446744073709551617"),
  ("20", "-1"),
  ("29", "-10"),
  ("3863", "-100"),
  ("3903e7", "-1000"),
  ("f90000", "0.0"),
  ("f98000", "-0.0"),
  ("f93c00", "1.0"),
  ("fb3ff199999999999a", "1.1"),
  ("f93e00", "1.5"),
  ("f97bff", "65504.0"),
  ("fa47c35000", "100000.0"),
  ("fa7f7fffff", "3.4028234663852886e+38"),
  ("fb7e37e43c8800759c", "1e+300"),
  ("f90001", "5.960464477539063e-8"),
  ("f90400", "0.00006103515625"),
  ("f9c400", "-4.0"),
  ("fbc010666666666666", "-4.1"),
  ("f97c00", "null"),
  ("f97e00", "null"),
  ("f9fc00", "null"),
  ("f4", "false"),
  ("f5", "true"),
  ("f6", "null"),
  ("f7", "{\"$undefined\":true}"),
  ("f0", "{\"$simple\":16}"),
  ("f8ff", "{\"$simple\":255}"),
  (
    "c074323031332d30332d32315432303a30343a30305a", "{\"$tag\":0,\"value\":\"2013-03-21T20:04:00Z\"}",
  ),
  ("c11a514b67b0", "{\"$tag\":1,\"value\":1363896240}"),
  ("c1fb41d452d9ec200000", "{\"$tag\":1,\"value\":1363896240.5}"),
  ("d74401020304", "{\"$tag\":23,\"value\":{\"$bytes\":\"01020304\"}}"),
  ("d818456449455446", "{\"$tag\":24,\"value\":{\"$bytes\":\"6449455446\"}}"),
  (
    "d82076687474703a2f2f7777772e6578616d706c652e636f6d", "{\"$tag\":32,\"value\":\"http://www.example.com\"}",
  ),
  ("40", "{\"$bytes\":\"\"}"),
  ("4401020304", "{\"$bytes\":\"01020304\"}"),
  ("60", "\"\""),
  ("6161", "\"a\""),
  ("6449455446", "\"IETF\""),
  ("62225c", "\"\\\"\\\\\""),
  ("62c3bc", "\"ü\""),
  ("63e6b0b4", "\"水\""),
  ("64f0908591", "\"𐅑\""),
  ("80", "[]"),
  ("83010203", "[1,2,3]"),
  ("8301820203820405", "[1,[2,3],[4,5]]"),
  ("a0", "{}"),
  ("a201020304", "{\"$map\":[[1,2],[3,4]]}"),
  ("a26161016162820203", "{\"a\":1,\"b\":[2,3]}"),
  ("826161a161626163", "[\"a\",{\"b\":\"c\"}]"),
  ("5f42010243030405ff", "{\"$bytes\":\"0102030405\"}"),
  ("7f657374726561646d696e67ff", "\"streaming\""),
  ("9fff", "[]"),
  ("9f018202039f0405ffff", "[1,[2,3],[4,5]]"),
  ("bf61610161629f0203ffff", "{\"a\":1,\"b\":[2,3]}"),
  ("826161bf61626163ff", "[\"a\",{\"b\":\"c\"}]"),
  ("bf6346756ef563416d7421ff", "{\"Fun\":true,\"Amt\":-2}"),
]

///|
/// The same examples that are already in the deterministic form, which must
/// come back out byte for byte. The ones left out are not: an indefinite-length
/// item and a double that holds a value a half can hold are both valid CBOR and
/// both written shorter here, and the last three number cases in the table are
/// infinities and a NaN, which the RFC prints twice each.
let stable : Array[String] = [
  "00", "01", "0a", "17", "1818", "1903e8", "1a000f4240", "1b000000e8d4a51000", "1bffffffffffffffff",
  "c249010000000000000000", "3bffffffffffffffff", "c349010000000000000000", "20",
  "29", "3863", "3903e7", "f90000", "f98000", "f93c00", "fb3ff199999999999a", "f93e00",
  "f97bff", "fa47c35000", "fa7f7fffff", "fb7e37e43c8800759c", "f90001", "f90400",
  "f9c400", "fbc010666666666666", "f4", "f5", "f6", "f7", "f0", "f8ff", "c074323031332d30332d32315432303a30343a30305a",
  "c11a514b67b0", "c1fb41d452d9ec200000", "d74401020304", "d818456449455446", "d82076687474703a2f2f7777772e6578616d706c652e636f6d",
  "40", "4401020304", "60", "6161", "6449455446", "62225c", "62c3bc", "63e6b0b4",
  "64f0908591", "80", "83010203", "8301820203820405", "a0", "a201020304", "a26161016162820203",
  "826161a161626163",
]

///|
/// Reading, against the RFC.
test "RFC 8949 appendix A" {
  for row in examples {
    let (hex, want) = row
    let bytes = @hex.decode(hex[:])
    assert_eq(@json.dumps(@cbor.load(bytes[:])), want)
  }
}

///|
/// Writing, byte for byte.
test "the deterministic form is reproduced" {
  for hex in stable {
    let bytes = @hex.decode(hex[:])
    assert_eq(@hex.encode(@cbor.dump(@cbor.load(bytes[:]))[:]), hex)
  }
}

///|
/// The RFC's own example of a nested document, which every implementation has
/// to get right before anything else.
test "a document with everything in it" {
  let hex = "a56161614161626142616361436164614461656145"
  assert_eq(
    @json.dumps(@cbor.load(@hex.decode(hex)[:])),
    "{\"a\":\"A\",\"b\":\"B\",\"c\":\"C\",\"d\":\"D\",\"e\":\"E\"}",
  )
}

///|
/// Bytes keep their bytes: the marker is how a byte string survives a trip
/// through a format that has none.
test "a byte string survives JSON" {
  let bytes = @cbor.dump(@json.loads("{\"$bytes\":\"deadbeef\"}"))
  assert_eq(@hex.encode(bytes[:]), "44deadbeef")
}

///|
/// Reading a truncated document, a document with something after it, and a
/// document that nests past the limit are three different refusals, and none of
/// them is a panic.
test "a document that is not one" {
  let short = @hex.decode("83")
  try @cbor.load(short[:]) |> ignore catch {
    e => assert_true(e is @moonjson.Short(_))
  } noraise {
    _ => fail("a truncated array was read")
  }
  let two = @hex.decode("0001")
  try @cbor.load(two[:]) |> ignore catch {
    e => assert_true(e is @moonjson.Extra(_))
  } noraise {
    _ => fail("two values were read as one")
  }
  let nest = StringBuilder()
  for _ in 0..<502 {
    nest.write_string("81")
  }
  nest.write_string("00")
  let deep = @hex.decode(nest.to_string())
  try @cbor.load(deep[:]) |> ignore catch {
    e => assert_true(e is @moonjson.Bad(..))
  } noraise {
    _ => fail("a document was read past the depth limit")
  }
}

///|
/// The one knob, both sides: a float is written in the shortest width that
/// holds it, and with `deterministic` off it is written as a double.
test "the deterministic knob" {
  let tree = @json.loads("1.5")
  assert_eq(@hex.encode(@cbor.dump(tree)[:]), "f93e00")
  assert_eq(
    @hex.encode(
      @cbor.dump(tree, policy={ ..@cbor.policy, deterministic: false, })[:],
    )[:],
    "fb3ff8000000000000",
  )
}
