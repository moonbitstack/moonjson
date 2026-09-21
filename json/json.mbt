// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read one JSON document.
///
/// Strictly RFC 8259: a leading zero, a trailing comma, a comment or a control
/// character inside a string is an error naming the line and column it is on,
/// not something quietly accepted.
pub fn parse(input : StringView) -> Json raise @moonjson.Malformed {
  @moonjson.read(input, @moonjson.strict)
}

///|
/// The same, from the UTF-8 bytes a body arrives as.
pub fn parse_bytes(input : BytesView) -> Json raise @moonjson.Malformed {
  @moonjson.read_bytes(input, @moonjson.strict)
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
