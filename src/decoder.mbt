// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A reader of a buffer that holds more than one document.
///
/// A JSON document is one value, and [`loads`] refuses anything after it — a
/// truncated file must not read as a plausible one. But a log, a socket or a
/// batch file often holds value after value, and cutting it into lines is not
/// the same thing: a value is allowed to span lines, and a line is allowed to
/// hold several where the dialect has no line rule. A decoder answers the next
/// value and where it ended, so the caller decides what the buffer means.
///
/// ```moonbit norecheck
/// let stream = @moonjson.Decoder::new("{\"a\":1}{\"b\":2}"[:], @moonjson.strict)
///
/// let first = stream.read() // Some({"a": 1})
///
/// let second = stream.read() // Some({"b": 2})
///
/// let end = stream.read() // None
/// ```
///
/// A dialect that defines a stream of its own — JSON Lines — has its own
/// package, because there a line *is* the rule; this one only stops where a
/// value stops.
pub struct Decoder {
  /// The buffer being read.
  text : StringView
  /// How to read it.
  flavor : Flavor
  /// Where the next value starts looking.
  mut offset : Int32
  /// How many values have been read.
  mut count : Int32
}

///|
/// A decoder over a buffer, in the given dialect.
pub fn Decoder::new(text : StringView, flavor : Flavor) -> Decoder {
  { text, flavor, offset: 0, count: 0, }
}

///|
/// The next value, or `None` when nothing but whitespace — and, where the
/// dialect allows them, comments — is left.
///
/// Whitespace between values is consumed; whitespace after a value is not, so
/// [`offset`](Decoder::offset) is the end of the value and a caller can resume
/// there with its own rule.
pub fn Decoder::read(self : Decoder) -> Json? raise Refused {
  let reader = { src: self.text, flavor: self.flavor, i: self.offset, }
  reader.space()
  if reader.i >= self.text.length() {
    self.offset = reader.i
    return None
  }
  let value = reader.value(0)
  self.offset = reader.i
  self.count += 1
  Some(value)
}

///|
/// How far into the buffer the decoder has come: the end of the last value read.
pub fn Decoder::offset(self : Decoder) -> Int32 {
  self.offset
}

///|
/// How many values have been read.
pub fn Decoder::count(self : Decoder) -> Int32 {
  self.count
}

///|
/// Whether nothing but whitespace is left.
pub fn Decoder::is_done(self : Decoder) -> Bool raise Refused {
  let reader = { src: self.text, flavor: self.flavor, i: self.offset, }
  reader.space()
  reader.i >= self.text.length()
}
