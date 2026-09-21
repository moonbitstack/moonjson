// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read one JSON document.
///
/// Strictly RFC 8259: a leading zero, a trailing comma, a comment or a control
/// character inside a string is an error naming the line and column it is on,
/// not something quietly accepted.
pub fn parse(
  input : StringView,
  flavor? : @moonjson.Flavor = @moonjson.strict,
) -> Json raise @moonjson.Malformed {
  @moonjson.read(input, flavor)
}

///|
/// The same, from the UTF-8 bytes a body arrives as.
pub fn parse_bytes(
  input : BytesView,
  flavor? : @moonjson.Flavor = @moonjson.strict,
  bom? : Bool = true,
) -> Json raise @moonjson.Malformed {
  @moonjson.read_bytes(input, flavor, bom~)
}

///|
/// Write a tree as strict JSON, whatever dialect it was read from.
///
/// `indent` of zero is the compact form. `ascii` escapes everything above
/// U+007E, for a transport that is not eight-bit clean — what Python's
/// `ensure_ascii` does, though unlike Python's it is off by default, because a
/// UTF-8 body is the normal case now. `sort` writes members in order of name
/// instead of the order they were read in, which is what a diff wants.
pub fn write(
  value : Json,
  indent? : Int = 0,
  ascii? : Bool = false,
  sort? : Bool = false,
) -> String {
  @moonjson.write(value, indent~, ascii~, sort~)
}

///|
/// The same, as the UTF-8 bytes a body goes out as.
pub fn write_bytes(
  value : Json,
  indent? : Int = 0,
  ascii? : Bool = false,
  sort? : Bool = false,
) -> Bytes {
  @moonjson.write_bytes(value, indent~, ascii~, sort~)
}
