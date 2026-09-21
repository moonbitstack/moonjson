// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read one JSONC document: JSON, plus comments and a trailing comma.
///
/// This is what `tsconfig.json` and `settings.json` are written in. Comments are
/// discarded — the tree has nowhere to put them — so writing the result back out
/// loses them.
pub fn parse(input : StringView) -> Json raise @moonjson.Malformed {
  @moonjson.read(input, @moonjson.commented)
}

///|
/// The same, from the UTF-8 bytes a body arrives as.
pub fn parse_bytes(input : BytesView) -> Json raise @moonjson.Malformed {
  @moonjson.read_bytes(input, @moonjson.commented)
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
