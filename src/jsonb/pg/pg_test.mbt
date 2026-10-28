// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Small trees, checked byte for byte in both directions.
test "scalar and empty vectors" {
  let cases : Array[(Json, String)] = [
    (Json::null(), "0000001406"),
    (Json::boolean(true), "0000001401"),
    (Json::boolean(false), "0000001402"),
    (Json::number(1.0), "00000034043ff0000000000000"),
    (Json::number(-2.5), "0000003404c004000000000000"),
    (Json::string("hi"), "0000002c05000000026869"),
    (Json::string(""), "000000240500000000"),
    (Json::array([]), "0000002200000000"),
    (Json::object(Map([])), "0000002100000000"),
    (Json::array([Json::null()]), "000000320000000380000000"),
  ]
  for pair in cases {
    let (tree, hex) = pair
    assert_eq(@pg.dump(tree), @hex.decode(hex[:]))
    assert_eq(@pg.load(@hex.decode(hex[:])[:]), tree)
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
    let bytes = @pg.dump(tree)
    assert_eq(@pg.load(bytes[:]), tree)
    assert_eq(@pg.dump(@pg.load(bytes[:])), bytes)
  }
}
