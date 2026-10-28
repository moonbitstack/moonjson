// ZJSON (Zed JSON) — https://github.com/brimdata/zed/blob/main/docs/formats/zjson.md
//
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read one ZJSON document.
///
/// ZJSON is the JSON encoding of the Zed data model: a stream of JSON objects,
/// each of the form `{"type": <zed-type>, "value": <json-value>}`, where `type`
/// describes the rich Zed type (a primitive name like `"int64"`, or a complex
/// type built from `record`/`array`/`map`/`union`/`enum`/`error`/`ref` nodes)
/// and `value` is the value rendered in plain JSON. It is, underneath, valid
/// JSON — the type lives in a member alongside the value.
///
/// That is the same situation as superjson's envelope: the `Json` tree in this
/// library has no Zed type system to rebuild into, so the faithful, honest
/// reading is a delegation. This call parses the document as ordinary JSON with
/// the shared reader, keeping `type` and `value` verbatim. A caller that needs
/// real Zed typed values must interpret `type` against the Zed type model in a
/// Zed-aware client — there is nothing here to lose by reading it as JSON, only
/// the type annotation, which survives as the preserved `type` member.
///
/// (Do not confuse this with *ZSON*, the PostgreSQL JSONB-compression extension
/// — a different format, implemented in `moonbitstack/moonjson/zson`.)
pub fn loads(
  input : StringView,
  flavor~ : @moonjson.Flavor = @moonjson.relaxed,
) -> Json raise @moonjson.Refused {
  @moonjson.loads(input, flavor)
}

///|
/// The same, from the UTF-8 bytes a body arrives as.
///
/// See [`loads`] for the design note: a ZJSON document is valid JSON, so the
/// bytes are read with the shared reader and the `type`/`value` members are kept
/// exactly as written.
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
/// A ZJSON value leaves here still a JSON object carrying `type` and `value`,
/// because this delegates to [`@moonjson.dumps`] and does not rewrite members.
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
/// See [`dumps`] for the design note: the `type`/`value` envelope is written
/// back as the JSON object it is, delegating to [`@moonjson.dump`].
pub fn dump(
  value : Json,
  indent~ : Int32 = 0,
  ascii~ : Bool = false,
  sort~ : Bool = false,
) -> Bytes {
  @moonjson.dump(value, indent~, ascii~, sort~)
}
