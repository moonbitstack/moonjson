// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The examples the MessagePack specification prints for each format, read
/// into the tree this family uses.
let examples : Array[(String, String)] = [
  ("c0", "null"),
  ("c2", "false"),
  ("c3", "true"),
  ("00", "0"),
  ("7f", "127"),
  ("cc80", "128"),
  ("cd0100", "256"),
  ("ce00010000", "65536"),
  ("cf0000000100000000", "4294967296"),
  ("ff", "-1"),
  ("e0", "-32"),
  ("d0df", "-33"),
  ("d080", "-128"),
  ("d1ff7f", "-129"),
  ("d18000", "-32768"),
  ("d2ffff7fff", "-32769"),
  ("d280000000", "-2147483648"),
  ("d3ffffffff7fffffff", "-2147483649"),
  ("ca3f000000", "0.5"),
  ("ca3f800000", "1.0"),
  ("cb3fe0000000000000", "0.5"),
  ("a568656c6c6f", "\"hello\""),
  ("a0", "\"\""),
  ("c403010203", "{\"$bytes\":\"010203\"}"),
  ("d40102", "{\"$ext\":1,\"data\":\"02\"}"),
  ("90", "[]"),
  ("93010203", "[1,2,3]"),
  ("80", "{}"),
  ("81a16101", "{\"a\":1}"),
  ("81a161a568656c6c6f", "{\"a\":\"hello\"}"),
]

///|
/// The same examples must come back out byte for byte: every one of them is
/// already in the shortest form the spec names.
let stable : Array[String] = [
  "c0", "c2", "c3", "00", "7f", "cc80", "cd0100", "ce00010000", "cf0000000100000000",
  "ff", "e0", "d0df", "d080", "d1ff7f", "d18000", "d2ffff7fff", "d280000000", "d3ffffffff7fffffff",
  "ca3f000000", "ca3f800000", "a568656c6c6f", "a0", "c403010203", "d40102", "90",
  "93010203", "80", "81a16101", "81a161a568656c6c6f",
]

///|
test "the specification's examples" {
  for row in examples {
    let (hex, want) = row
    let bytes = @hex.decode(hex[:])
    assert_eq(@json.dumps(@msgpack.load(bytes[:])), want)
  }
}

///|
/// Writing, byte for byte, with the float knob set so a 32-bit float stays one.
test "the shortest form is reproduced" {
  let policy = @msgpack.Policy::new(floats=@msgpack.Shortest)
  for hex in stable {
    let bytes = @hex.decode(hex[:])
    assert_eq(
      @hex.encode(@msgpack.dump(@msgpack.load(bytes[:]), policy~)[:]),
      hex,
    )
  }
}

///|
/// The float knob, both sides: a double by default, a single when asked for.
test "the float knob" {
  let tree = @json.loads("0.5")
  assert_eq(@hex.encode(@msgpack.dump(tree)[:]), "cb3fe0000000000000")
  assert_eq(
    @hex.encode(
      @msgpack.dump(tree, policy=@msgpack.Policy::new(floats=Shortest))[:],
    ),
    "ca3f000000",
  )
}

///|
/// A byte string and an extension survive a trip through the tree, which is how
/// a MessagePack document reaches JSON and comes back.
test "markers round trip" {
  let tree = @json.loads("{\"$bytes\":\"deadbeef\"}")
  assert_eq(@hex.encode(@msgpack.dump(tree)[:]), "c404deadbeef")
  let ext = @json.loads("{\"$ext\":-1,\"data\":\"00ff\"}")
  assert_eq(@hex.encode(@msgpack.dump(ext)[:]), "c702ff00ff")
}

///|
/// Nothing is guessed: a truncated document, a trailing byte and the one
/// reserved head byte are three refusals.
test "a document that is not one" {
  let short = @hex.decode("93")
  try @msgpack.load(short[:]) |> ignore catch {
    e => assert_true(e is @moonjson.Short(_))
  } noraise {
    _ => fail("a truncated array was read")
  }
  let two = @hex.decode("0001")
  try @msgpack.load(two[:]) |> ignore catch {
    e => assert_true(e is @moonjson.Extra(_))
  } noraise {
    _ => fail("two values were read as one")
  }
  let reserved = @hex.decode("c1")
  try @msgpack.load(reserved[:]) |> ignore catch {
    e => assert_true(e is @moonjson.Bad(..))
  } noraise {
    _ => fail("0xc1 was read as a value")
  }
}
