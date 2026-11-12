// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Two documents in one buffer, read one at a time; `loads` would have refused
/// the second as trailing input.
test "a decoder reads value after value" {
  let decoder = @moonjson.Decoder::new(
    "{\"a\":1}{\"b\":2}"[:],
    @moonjson.strict,
  )
  assert_eq(
    decoder.read(),
    Some(Json::object(Map::from_array([("a", Json::number(1.0))]))),
  )
  assert_eq(
    decoder.read(),
    Some(Json::object(Map::from_array([("b", Json::number(2.0))]))),
  )
  assert_eq(decoder.read(), None)
  assert_eq(decoder.count(), 2)
  assert_eq(decoder.offset(), 14)
  assert_eq(decoder.is_done(), true)
}

///|
/// Whitespace between values is skipped; the offset stays on the end of the
/// value it answered, so the caller can resume at the first byte it owns.
test "whitespace between values is skipped" {
  let decoder = @moonjson.Decoder::new(" 1 \n\t 2 ", @moonjson.strict)
  assert_eq(decoder.read(), Some(Json::number(1.0)))
  assert_eq(decoder.offset(), 2)
  assert_eq(decoder.read(), Some(Json::number(2.0)))
  assert_eq(decoder.read(), None)
  assert_eq(decoder.is_done(), true)
}

///|
/// Comments are skipped where the dialect allows them, and nowhere else.
test "comments are skipped only where the dialect allows them" {
  let decoder = @moonjson.Decoder::new("1 // one\n2", @moonjson.commented)
  assert_eq(decoder.read(), Some(Json::number(1.0)))
  assert_eq(decoder.read(), Some(Json::number(2.0)))
  assert_eq(decoder.read(), None)

  let strict_decoder = @moonjson.Decoder::new("1 // one\n2", @moonjson.strict)
  assert_eq(strict_decoder.read(), Some(Json::number(1.0)))
  try strict_decoder.read() |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("a comment was skipped by a dialect that has none")
  }
}

///|
/// An empty buffer is no value at all, not an error: a socket that has not been
/// written to yet is not a broken document.
test "an empty buffer holds no values" {
  let decoder = @moonjson.Decoder::new("", @moonjson.strict)
  assert_eq(decoder.read(), None)
  assert_eq(decoder.count(), 0)
  assert_eq(decoder.is_done(), true)
}

///|
/// A value that is not finished is refused where it stops, and the values before
/// it are still answered.
test "a truncated value is refused at its end" {
  let decoder = @moonjson.Decoder::new("1 {\"a\":", @moonjson.strict)
  assert_eq(decoder.read(), Some(Json::number(1.0)))
  try decoder.read() |> ignore catch {
    e =>
      if e is Truncated(at) {
        assert_eq(at.at, 7)
      } else {
        fail("a truncated object was another refusal")
      }
  } noraise {
    _ => fail("a truncated object was accepted")
  }
}
