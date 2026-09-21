// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read one JSON5 document.
///
/// JSON5 admits values JSON cannot write — `Infinity`, `NaN`, a hexadecimal
/// integer — so a document read here and written as strict JSON is not always
/// the same document. `write` says what becomes of each.
pub fn parse(input : StringView) -> Json raise @moonjson.Malformed {
  @moonjson.read(input, @moonjson.relaxed)
}

///|
/// The same, from the UTF-8 bytes a body arrives as.
pub fn parse_bytes(input : BytesView) -> Json raise @moonjson.Malformed {
  @moonjson.read_bytes(input, @moonjson.relaxed)
}

///|
/// Write a tree as strict JSON. `indent` of zero is the compact form.
pub fn write(value : Json, indent? : Int = 0) -> String {
  @moonjson.write(value, indent~)
}

///|
/// The same, as the UTF-8 bytes a body goes out as.
pub fn write_bytes(value : Json, indent? : Int = 0) -> Bytes {
  @moonjson.write_bytes(value, indent~)
}
