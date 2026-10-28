// jsonz — JSON-Z, "JSON for Everyone"
// (https://www.npmjs.com/package/json-z; grammar/spec tracked alongside JSON5
// at https://github.com/GerHobbelt/json5 under the JSON-Z section).
//
// JSON-Z is a superset of JSON (and of JSON5) that adds comments, single and
// backtick quotes, unquoted object keys, trailing commas, hexadecimal/octal/
// binary numbers, `+`-prefixed and `Infinity`/`-Infinity`/`NaN` numbers, and
// more. This package reads and writes the JSON-representable subset by
// delegating to `@moonjson`'s relaxed reader; see `loads` for the limits.

///|
/// Read one JSON-Z document.
///
/// JSON-Z shares its JSON5-compatible surface — comments, single and backtick
/// quotes, unquoted object keys, trailing commas, hexadecimal and signed
/// numbers, `Infinity` and `NaN` — with the relaxed reader, so those are parsed
/// here by delegating to [`@moonjson.loads`] with `flavor = relaxed`.
///
/// LIMITATION — JSON-Z adds values the shared `Json` tree cannot hold: BigInt
/// (the `n` suffix), arbitrary-precision decimals (`m`) and IEEE-754 Decimal128
/// (`d`), sparse arrays, `undefined`, and extended typed containers (Date, Map,
/// Set, RegExp, Uint8Array). These are out of scope for a `Json` tree that has
/// none of those types, exactly as superjson and ntv are out of scope for the
/// types they cannot rebuild. A document that uses them is not accepted here.
pub fn loads(
  input : StringView,
  flavor~ : @moonjson.Flavor = @moonjson.relaxed,
) -> Json raise @moonjson.Refused {
  @moonjson.loads(input, flavor)
}

///|
/// The same, from the UTF-8 bytes a body arrives as.
///
/// Reads JSON-Z as ordinary JSON-Z (the JSON5-compatible subset), delegating to
/// [`@moonjson.load`]; see [`loads`] for the JSON-Z features this package keeps
/// and the ones it cannot represent in a `Json` tree.
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
/// U+007E, for a transport that is not eight-bit clean. `sort` writes members in
/// order of name instead of the order they were read in, which is what a diff
/// wants. The JSON-Z representable subset round-trips as JSON here; the
/// JSON-Z-exclusive numeric and container extensions cannot be reconstructed.
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
/// Writes the tree as ordinary JSON, delegating to [`@moonjson.dump`]; a value
/// read from JSON-Z's representable subset is written back as JSON.
pub fn dump(
  value : Json,
  indent~ : Int32 = 0,
  ascii~ : Bool = false,
  sort~ : Bool = false,
) -> Bytes {
  @moonjson.dump(value, indent~, ascii~, sort~)
}
