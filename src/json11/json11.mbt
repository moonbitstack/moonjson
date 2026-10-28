// json11 — the dropbox/json11 C++11 JSON library
// (https://github.com/dropbox/json11).
//
// json11 is a tiny C++11 library providing JSON parsing and serialization; its
// core object is `json11::Json` and its helpers are `Json::dump` and
// `Json::parse`. Its output is standard JSON (RFC 8259) — the library adds no
// syntax of its own. This package therefore delegates to `@moonjson` and
// documents that a json11 payload is exactly JSON.

///|
/// Read one json11 document.
///
/// json11 emits and parses standard JSON, so this delegates to
/// [`@moonjson.loads`]; a json11 payload is ordinary JSON.
pub fn loads(
  input : StringView,
  flavor~ : @moonjson.Flavor = @moonjson.strict,
) -> Json raise @moonjson.Refused {
  @moonjson.loads(input, flavor)
}

///|
/// The same, from the UTF-8 bytes a body arrives as.
///
/// Reads json11 as ordinary JSON, delegating to [`@moonjson.load`]; a json11
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
/// diff wants. A json11 payload IS standard JSON, so this is ordinary output.
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
/// Writes the tree as ordinary JSON, delegating to [`@moonjson.dump`]; a json11
/// payload is standard JSON on the wire.
pub fn dump(
  value : Json,
  indent~ : Int32 = 0,
  ascii~ : Bool = false,
  sort~ : Bool = false,
) -> Bytes {
  @moonjson.dump(value, indent~, ascii~, sort~)
}
