// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Small trees, checked byte for byte in both directions.
test "scalar and empty vectors" {
  let cases : Array[(Json, String)] = [
    (Json::null(), "c10100000000"),
    (Json::boolean(true), "c10100000002"),
    (Json::boolean(false), "c10100000001"),
    (Json::number(1.0), "c101000000033ff0000000000000"),
    (Json::string("hi"), "c101000000146869"),
    (Json::string(""), "c10100000004"),
    (Json::array([]), "c10100000006"),
    (Json::object(Map([])), "c10100000007"),
    (Json::array([Json::null()]), "c1010000000e00"),
  ]
  for pair in cases {
    let (tree, hex) = pair
    assert_eq(@cbd.dump(tree), @hex.decode(hex[:]))
    assert_eq(@cbd.load(@hex.decode(hex[:])[:]), tree)
  }
}

///|
/// Every kind of value survives a round trip, and a re-dump is the same bytes.
test "round trips" {
  let trees = [
    Json::null(),
    Json::boolean(true),
    Json::number(3.14159),
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
