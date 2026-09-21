// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read one JSONC document: JSON, plus comments and a trailing comma.
///
/// This is what `tsconfig.json` and `settings.json` are written in. Comments are
/// discarded — the tree has nowhere to put them — so writing the result back out
/// loses them.
pub fn loads(
  input : StringView,
  flavor? : @moonjson.Flavor = @moonjson.commented,
) -> Json raise @moonjson.Malformed {
  @moonjson.loads(input, flavor)
}

///|
/// The same, from the UTF-8 bytes a body arrives as.
pub fn load(
  input : BytesView,
  flavor? : @moonjson.Flavor = @moonjson.commented,
  bom? : Bool = true,
) -> Json raise @moonjson.Malformed {
  @moonjson.load(input, flavor, bom~)
}

///|
/// Write a tree as strict JSON, whatever dialect it was read from.
///
/// `indent` of zero is the compact form. `ascii` escapes everything above
/// U+007E, for a transport that is not eight-bit clean — what Python's
/// `ensure_ascii` does, though unlike Python's it is off by default, because a
/// UTF-8 body is the normal case now. `sort` writes members in order of name
/// instead of the order they were read in, which is what a diff wants.
pub fn dumps(
  value : Json,
  indent? : Int = 0,
  ascii? : Bool = false,
  sort? : Bool = false,
) -> String {
  @moonjson.dumps(value, indent~, ascii~, sort~)
}

///|
/// The same, as the UTF-8 bytes a body goes out as.
pub fn dump(
  value : Json,
  indent? : Int = 0,
  ascii? : Bool = false,
  sort? : Bool = false,
) -> Bytes {
  @moonjson.dump(value, indent~, ascii~, sort~)
}
