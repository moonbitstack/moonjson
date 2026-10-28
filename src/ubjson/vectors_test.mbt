// Universal Binary JSON (UBJSON) — https://ubjson.org/
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read a hex string as UBJSON and render the tree as JSON, for a readable
/// expectation.
fn show(hex : String) -> String raise @moonjson.Refused {
  let bytes = @hex.decode(hex[:]) catch {
    _ => raise @moonjson.Bad(at=0, why="bad hex in test")
  }
  @json.dumps(@ubjson.load(bytes[:]), sort=true)
}

///|
/// Known byte sequences, read as the tree this family reads into.
test "known bytes read into a tree" {
  // Z / T / F
  assert_eq(show("5a"), "null")
  assert_eq(show("54"), "true")
  assert_eq(show("46"), "false")
  // i int8, including the sign bit
  assert_eq(show("6905"), "5")
  assert_eq(show("6985"), "-123")
  // I int16 and U uint8
  assert_eq(show("490100"), "256")
  assert_eq(show("55ff"), "255")
  // D float64 and d float32
  assert_eq(show("443ff8000000000000"), "1.5")
  assert_eq(show("643f800000"), "1.0")
  // S string
  assert_eq(show("53690161"), "\"a\"")
  // a simple array and object
  assert_eq(show("5b6901690269035d"), "[1,2,3]")
  assert_eq(show("7b5369016169015369016269027d"), "{\"a\":1,\"b\":2}")
  // a high-precision number keeps its decimal text
  assert_eq(
    show("4869143132333435363738393031323334353637383930"),
    "12345678901234567890",
  )
}

///|
/// Known trees, written as the bytes this package produces — the simple form, no
/// length prefixes.
test "known trees write into bytes" {
  assert_eq(@hex.encode(@ubjson.dump(Json::null())[:]), "5a")
  assert_eq(@hex.encode(@ubjson.dump(Json::boolean(true))[:]), "54")
  assert_eq(@hex.encode(@ubjson.dump(Json::boolean(false))[:]), "46")
  // the smallest width that holds the integer
  assert_eq(@hex.encode(@ubjson.dump(Json::number(5.0, repr="5"))[:]), "6905")
  assert_eq(
    @hex.encode(@ubjson.dump(Json::number(200.0, repr="200"))[:]),
    "4900c8",
  )
  // a float is a float even at an integral value
  assert_eq(
    @hex.encode(@ubjson.dump(Json::number(1.5, repr="1.5"))[:]),
    "443ff8000000000000",
  )
  assert_eq(
    @hex.encode(@ubjson.dump(Json::number(0.0, repr="0.0"))[:]),
    "440000000000000000",
  )
  // a string: S, then the length as the smallest int, then the bytes
  assert_eq(@hex.encode(@ubjson.dump(Json::string("a"))[:]), "53690161")
  // containers open and close, every element marked
  assert_eq(
    @hex.encode(
      @ubjson.dump(
        Json::array([Json::number(5.0, repr="5"), Json::number(6.0, repr="6")]),
      )[:],
    ),
    "5b690569065d",
  )
  assert_eq(
    @hex.encode(
      @ubjson.dump(Json::object({ "a": Json::number(1.0, repr="1") }))[:],
    ),
    "7b5369016169017d",
  )
  assert_eq(@hex.encode(@ubjson.dump(Json::array([]))[:]), "5b5d")
  assert_eq(@hex.encode(@ubjson.dump(Json::object(Map([])))), "7b7d")
}

///|
/// The one non-JSON marker UBJSON can carry: a byte string is spelled as an array
/// of uint8, because UBJSON has no byte string of its own. Reading that array
/// back yields a plain array — the mapping is one-way, by design.
test "a byte string becomes an array of uint8" {
  let bytes = @hex.encode(
    @ubjson.dump(Json::object({ "$bytes": Json::string("0102") }))[:],
  )
  assert_eq(bytes, "5b550155025d")
}

///|
/// Reading a truncated document, a document with something after it, and a
/// document that nests past the limit are three different refusals, and none of
/// them is a panic.
test "a document that is not one" {
  // a string that promises two bytes but has none
  try @ubjson.load(@hex.decode("53690261")[:]) |> ignore catch {
    e => assert_true(e is @moonjson.Short(_))
  } noraise {
    _ => fail("a truncated string was read")
  }
  // two values where one was expected
  try @ubjson.load(@hex.decode("5a54")[:]) |> ignore catch {
    e => assert_true(e is @moonjson.Extra(_))
  } noraise {
    _ => fail("two values were read as one")
  }
  // an unknown marker
  try @ubjson.load(@hex.decode("00")[:]) |> ignore catch {
    e => assert_true(e is @moonjson.Bad(..))
  } noraise {
    _ => fail("an unknown marker was read")
  }
  // nesting past the depth limit
  let nest = StringBuilder()
  for _ in 0..<502 {
    nest.write_string("5b")
  }
  nest.write_string("6900")
  for _ in 0..<502 {
    nest.write_string("5d")
  }
  try @ubjson.load(@hex.decode(nest.to_string())[:]) |> ignore catch {
    e => assert_true(e is @moonjson.Bad(..))
  } noraise {
    _ => fail("a document was read past the depth limit")
  }
}

///|
/// A varied set of trees, each loaded back from its own bytes into a tree that
/// renders to the same JSON. The comparison sorts members so key order — which
/// the writer fixes — does not matter.
test "a round trip over varied trees" {
  let trees : Array[Json] = [
    Json::null(),
    Json::boolean(true),
    Json::boolean(false),
    Json::number(0.0, repr="0"),
    Json::number(0.0, repr="0.0"),
    Json::number(1.0, repr="1"),
    Json::number(1.0, repr="1.0"),
    Json::number(-128.0, repr="-128"),
    Json::number(127.0, repr="127"),
    Json::number(128.0, repr="128"),
    Json::number(300.0, repr="300"),
    Json::number(100000.0, repr="100000"),
    Json::number(2147483648.0, repr="2147483648"),
    Json::number(1.5, repr="1.5"),
    Json::number(-2.5, repr="-2.5"),
    Json::number(0.1, repr="0.1"),
    Json::string(""),
    Json::string("hello"),
    Json::string("ü"),
    Json::array([Json::number(1.0, repr="1"), Json::boolean(true), Json::null()]),
    Json::object({
      "x": Json::number(1.0, repr="1"),
      "y": Json::number(2.0, repr="2"),
    }),
    Json::object({
      "a": Json::array([
        Json::number(1.0, repr="1"),
        Json::number(2.0, repr="2"),
      ]),
    }),
    // a high-precision decimal — wider than int64 — survives as text
    Json::number(0.0, repr="123456789012345678901234567890"),
  ]
  for tree in trees {
    let back = @ubjson.load(@ubjson.dump(tree))
    assert_eq(@json.dumps(back, sort=true), @json.dumps(tree, sort=true))
  }
}
