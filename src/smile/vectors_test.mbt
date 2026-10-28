// Smile binary data format — https://github.com/FasterXML/smile-format-specification
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Known bytes, read back as the tree they mean. Each row is a hex document
/// (header, value, `0x00` terminator) and the JSON text it decodes to; the
/// encoding is spec-shaped but not byte-validated against an external library.
let decode_cases : Array[(String, String)] = [
  ("3a290a002d00", "null"),
  ("3a290a002f00", "true"),
  ("3a290a002e00", "false"),
  ("3a290a003600", "0"),
  ("3a290a003700", "1"),
  ("3a290a002202686900", "\"hi\""),
  ("3a290a002402010200", "{\"$bytes\":\"0102\"}"),
  ("3a290a003801363900", "[0]"),
  ("3a290a003b01220161373c00", "{\"a\":1}"),
  ("3a290a00380226373900", "[-16,1]"),
]

///|
/// Reading, against the encoding this package writes.
test "known bytes decode to the expected tree" {
  for row in decode_cases {
    let (hex, want) = row
    let bytes = @hex.decode(hex[:])
    let tree = @smile.load(bytes[:])
    assert_eq(@json.dumps(tree, sort=true), want)
  }
}

///|
/// Known trees, written back as the bytes they mean. The hex is worked out by
/// hand from the marker choices documented in `write.mbt`.
let encode_cases : Array[(Json, String)] = [
  (Json::null(), "3a290a002d00"),
  (Json::boolean(true), "3a290a002f00"),
  (Json::boolean(false), "3a290a002e00"),
  (Json::number(0.0, repr="0"), "3a290a003600"),
  (Json::number(1.0, repr="1"), "3a290a003700"),
  (Json::number(123.0, repr="123"), "3a290a0027000000f600"),
  (Json::string("hi"), "3a290a002202686900"),
  (Json::object({ "$bytes": Json::string("0102") }), "3a290a002402010200"),
  (Json::array([Json::number(0.0, repr="0")]), "3a290a003801363900"),
  (
    Json::object({ "a": Json::number(1.0, repr="1") }),
    "3a290a003b01220161373c00",
  ),
  (
    Json::object({ "a": Json::number(1.0, repr="1"), "b": Json::string("y") }),
    "3a290a003b02220161372201622201793c00",
  ),
]

///|
/// Writing, byte for byte.
test "known trees encode to the expected bytes" {
  for row in encode_cases {
    let (tree, want) = row
    let bytes = @smile.dump(tree)
    assert_eq(@hex.encode(bytes[:]), want)
  }
}

///|
/// Trees survive a trip through the bytes and back, compared as JSON text so
/// that an integer and its float twin, or a re-ordered object, do not count as
/// a difference.
test "round trip through bytes" {
  let trees : Array[Json] = [
    Json::null(),
    Json::boolean(true),
    Json::boolean(false),
    Json::number(0.0, repr="0"),
    Json::number(123.0, repr="123"),
    Json::number(2.0, repr="2"),
    Json::number(-16.0, repr="-16"),
    Json::number(-6.0, repr="-6"),
    Json::number(1.5, repr="1.5"),
    Json::number(-3.25, repr="-3.25"),
    Json::number(100.5, repr="100.5"),
    Json::string("hi"),
    Json::string("值 ☺"),
    Json::array([Json::number(1.0, repr="1"), Json::string("x"), Json::null()]),
    Json::object({
      "a": Json::number(1.0, repr="1"),
      "b": Json::string("y"),
      "c": Json::array([]),
    }),
    Json::object({ "$bytes": Json::string("deadbeef") }),
    Json::object({ "nested": Json::object({ "deep": Json::boolean(true) }) }),
  ]
  for tree in trees {
    let bytes = @smile.dump(tree)
    let back = @smile.load(bytes[:])
    assert_eq(@json.dumps(back, sort=true), @json.dumps(tree, sort=true))
  }
}

///|
/// The `$bytes` marker is the one JSON-only form Smile carries natively: a
/// single-member `{"$bytes": ...}` object becomes a Smile binary on the wire
/// and comes back as the same object.
test "a byte string survives as native binary" {
  let bytes = @smile.dump(@json.loads("{\"$bytes\":\"deadbeef\"}"))
  assert_eq(@hex.encode(bytes[:]), "3a290a002404deadbeef00")
  assert_eq(
    @json.dumps(@smile.load(bytes[:]), sort=true),
    "{\"$bytes\":\"deadbeef\"}",
  )
}

///|
/// A truncated document, a document with something after the terminator, and a
/// document that nests past the limit are three different refusals.
test "a document that is not one" {
  let short = @hex.decode("3a290a0022")
  try @smile.load(short[:]) |> ignore catch {
    e => assert_true(e is @moonjson.Short(_))
  } noraise {
    _ => fail("a truncated string was read")
  }
  let two = @hex.decode("3a290a002d003a290a002d00")
  try @smile.load(two[:]) |> ignore catch {
    e => assert_true(e is @moonjson.Extra(_))
  } noraise {
    _ => fail("two values were read as one")
  }
  let nest = StringBuilder()
  for _ in 0..<502 {
    nest.write_string("38")
    nest.write_string("01")
  }
  nest.write_string("39")
  nest.write_string("00")
  let deep = @hex.decode(nest.to_string())
  try @smile.load(deep[:]) |> ignore catch {
    e => assert_true(e is @moonjson.Bad(..))
  } noraise {
    _ => fail("a document was read past the depth limit")
  }
}
