// JSON-NTV (Named and Typed Value) — https://datatracker.ietf.org/doc/html/draft-thomy-json-ntv-03
//
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read one JSON-NTV document.
///
/// DESIGN — JSON-NTV is JSON. A tagged value such as `{"paris:point":
/// [2.35, 48.85]}` is a perfectly ordinary JSON object with one member whose
/// key happens to read `name:type`. There is therefore no separate tree to
/// parse into: this call delegates to [`@moonjson.loads`], so the `name:type`
/// key is kept verbatim as the member key it is.
///
/// LIMITATION — because the shared `Json` tree has no notion of a typed name,
/// the `name` and `type` parts of the key are not split apart or interpreted;
/// they survive only as a plain object key. A reader that needs the name or the
/// type must read the key string and divide it on the last `:`. This is the
/// faithful and honest reading: a tagged value is valid JSON, and nothing here
/// pretends otherwise.
pub fn loads(
  input : StringView,
  flavor~ : @moonjson.Flavor = @moonjson.relaxed,
) -> Json raise @moonjson.Refused {
  @moonjson.loads(input, flavor)
}

///|
/// The same, from the UTF-8 bytes a body arrives as.
///
/// See [`loads`] for the design note: a JSON-NTV document is valid JSON, so the
/// bytes are read with the shared reader and any `name:type` key is preserved
/// as a plain object key.
pub fn load(
  input : BytesView,
  flavor~ : @moonjson.Flavor = @moonjson.relaxed,
  bom~ : Bool = true,
) -> Json raise @moonjson.Refused {
  @moonjson.load(input, flavor, bom~)
}

///|
/// Write a tree as strict JSON, whatever dialect it was read from.
///
/// `indent` of zero is the compact form. `ascii` escapes everything above
/// U+007E, for a transport that is not eight-bit clean — what is sometimes
/// called `ensure_ascii`, except that it is off by default here, because a
/// UTF-8 body is the normal case now. `sort` writes members in order of name
/// instead of the order they were read in, which is what a diff wants.
///
/// A JSON-NTV value leaves here still a JSON object with a `name:type` key,
/// because this delegates to [`@moonjson.dumps`] and does not rewrite keys.
pub fn dumps(
  value : Json,
  indent~ : Int32 = 0,
  ascii~ : Bool = false,
  sort~ : Bool = false,
) -> String {
  @moonjson.dumps(value, indent~, ascii~, sort~)
}

///|
/// The same, as the UTF-8 bytes a body goes out as.
///
/// See [`dumps`] for the design note: a tagged value is written back as the
/// JSON object with its `name:type` key intact.
pub fn dump(
  value : Json,
  indent~ : Int32 = 0,
  ascii~ : Bool = false,
  sort~ : Bool = false,
) -> Bytes {
  @moonjson.dump(value, indent~, ascii~, sort~)
}
