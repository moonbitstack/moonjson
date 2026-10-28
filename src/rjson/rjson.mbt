// rjson — the Ruby `json` library
// (https://ruby-doc.org/stdlib/libdoc/json/rdoc/JSON.html).
//
// "rjson" is most often a shorthand for the Ruby `json` standard-library, or the
// `rjson` gem built on it. Both serialize Ruby objects to *standard* JSON and
// parse standard JSON back; there is no separate "rjson" textual grammar. This
// package therefore delegates to `@moonjson` — reading and writing plain JSON —
// and documents that an rjson payload is exactly JSON.

///|
/// Read one rjson document.
///
/// The Ruby `json` library emits and accepts standard JSON (RFC 8259), so this
/// delegates to [`@moonjson.loads`]; an rjson payload is ordinary JSON.
pub fn loads(
  input : StringView,
  flavor~ : @moonjson.Flavor = @moonjson.strict,
) -> Json raise @moonjson.Refused {
  @moonjson.loads(input, flavor)
}

///|
/// The same, from the UTF-8 bytes a body arrives as.
///
/// Reads rjson as ordinary JSON, delegating to [`@moonjson.load`]; an rjson
/// payload is standard JSON regardless of how it is transported.
pub fn load(
  input : BytesView,
  flavor~ : @moonjson.Flavor = @moonjson.strict,
  bom~ : Bool = true,
) -> Json raise @moonjson.Refused {
  @moonjson.load(input, flavor, bom~)
}

///|
/// Write a tree as standard JSON, whatever dialect it was read from.
///
/// `indent` of zero is the compact form. `ascii` escapes everything above
/// U+007E, for a transport that is not eight-bit clean. `sort` writes members
/// in order of name instead of the order they were read in, which is what a
/// diff wants. An rjson payload IS standard JSON, so this is ordinary output.
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
/// Writes the tree as ordinary JSON, delegating to [`@moonjson.dump`]; an rjson
/// payload is standard JSON on the wire.
pub fn dump(
  value : Json,
  indent~ : Int32 = 0,
  ascii~ : Bool = false,
  sort~ : Bool = false,
) -> Bytes {
  @moonjson.dump(value, indent~, ascii~, sort~)
}
