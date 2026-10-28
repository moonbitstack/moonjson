// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Small trees, checked byte for byte in both directions. The header is
/// `CB D1 01` then the dictionary size, which is zero for a document with no
/// object keys.
test "scalar and empty vectors" {
  let cases : Array[(Json, String)] = [
    (Json::null(), "cbd101000000"),
    (Json::boolean(true), "cbd101000021"),
    (Json::boolean(false), "cbd101000020"),
    (Json::number(30.0), "cbd1010000401e"),
    (Json::number(1.0), "cbd10100004001"),
    (Json::number(3.5), "cbd101000046400c000000000000"),
    (Json::number(-2.5), "cbd101000046c004000000000000"),
    (Json::string("hi"), "cbd101000060026869"),
    (Json::array([]), "cbd10100008100"),
    (Json::object(Map([])), "cbd1010000a100"),
  ]
  for pair in cases {
    let (tree, hex) = pair
    assert_eq(@cbd.dump(tree), @hex.decode(hex[:]))
    assert_eq(@cbd.load(@hex.decode(hex[:])[:]), tree)
  }
}

///|
/// The specification's own example, decoded byte for byte: an object with
/// `name` = "John" and `age` = 30, its dictionary `name`, `age`.
test "the specification example decodes" {
  let hex = "cbd1010002046e616d6503616765a1020160044a6f686e02401e"
  let tree = @cbd.load(@hex.decode(hex[:])[:])
  let want = Json::object(
    Map::from_array([
      ("name", Json::string("John")),
      ("age", Json::number(30.0)),
    ]),
  )
  assert_eq(tree, want)
  assert_eq(@cbd.dump(want), @hex.decode(hex[:]))
}

///|
/// Every kind of value survives a round trip, and a re-dump is the same bytes.
test "round trips" {
  let trees = [
    Json::null(),
    Json::boolean(true),
    Json::number(3.14159),
    Json::number(-2.5),
    Json::string("héllo"),
    Json::array([
      Json::number(1.0),
      Json::string("two"),
      Json::null(),
      Json::boolean(false),
    ]),
    Json::object(
      Map::from_array([
        ("b", Json::number(2.0)),
        ("a", Json::array([Json::number(1.0)])),
        ("n", Json::null()),
      ]),
    ),
    Json::object(Map::from_array([("$bytes", Json::string("deadbeef"))])),
  ]
  for tree in trees {
    let bytes = @cbd.dump(tree)
    assert_eq(@cbd.load(bytes[:]), tree)
    assert_eq(@cbd.dump(@cbd.load(bytes[:])), bytes)
  }
}
