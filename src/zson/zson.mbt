// ZSON — https://github.com/postgrespro/zson
//
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read one ZSON document.
///
/// ZSON is a PostgreSQL extension that compresses `jsonb` transparently, using a
/// shared dictionary trained on the data a deployment actually stores. That
/// makes it a *server-side* compression, not a portable wire format: the bytes
/// on disk depend on a per-database dictionary that is not part of the document,
/// so no standalone decoder can turn them back into a value. What travels between
/// systems — the `jsonb` a column holds, the text a client sends or receives —
/// is ordinary JSON, and that is the only part this library can faithfully
/// handle. The honest reading is therefore a delegation: parse the value as
/// JSON with the shared reader. A caller that needs real ZSON storage must use
/// PostgreSQL with the extension installed; this package only understands the
/// JSON a ZSON column carries.
///
/// (Do not confuse this with *ZJSON*, the Zed JSON encoding — a different
/// format, implemented in `moonbitstack/moonjson/zjson`.)
pub fn loads(
  input : StringView,
  flavor~ : @moonjson.Flavor = @moonjson.relaxed,
) -> Json raise @moonjson.Refused {
  @moonjson.loads(input, flavor)
}

///|
/// The same, from the UTF-8 bytes a body arrives as.
///
/// See [`loads`] for the design note: a ZSON value is `jsonb` — that is, JSON —
/// so the bytes are read with the shared reader and the compression itself is
/// out of scope for a portable library.
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
/// The result is the JSON a ZSON column accepts: the compression step that
/// follows is PostgreSQL's, not this package's.
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
/// See [`dumps`] for the design note: the output is plain JSON ready to be
/// stored into (or sent to) a ZSON column, which then compresses it with its
/// trained dictionary.
pub fn dump(
  value : Json,
  indent~ : Int32 = 0,
  ascii~ : Bool = false,
  sort~ : Bool = false,
) -> Bytes {
  @moonjson.dump(value, indent~, ascii~, sort~)
}
