// Superjson — https://github.com/blitz-js/superjson
//
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read one superjson document.
///
/// Superjson's wire form is plain JSON shaped as
/// `{"json": <value>, "meta": { "values": { "<path>": "<type>" }, ... }}`.
/// The `Json` tree in this library has no `Date`, `BigInt`, `Map` or `Set`
/// type, so there is nothing here to rebuild a JavaScript value into — and
/// inventing one would not be faithful, because the whole point of the
/// envelope is that those types live in JavaScript, not on the wire. The
/// honest thing to do is therefore the simplest: parse the envelope as an
/// ordinary JSON object (delegating to `@moonjson.loads`) and keep `json` and
/// `meta` verbatim. The typed values survive as the plain JSON they decode to;
/// the type table survives as the preserved `meta` object.
///
/// Full JavaScript-type reconstruction is out of scope for this `Json` tree.
/// A caller that needs real `Date`/`BigInt`/`Map`/`Set` objects must rebuild
/// them from the `meta` on the JavaScript side, where those types exist.
pub fn loads(
  input : StringView,
  flavor~ : @moonjson.Flavor = @moonjson.relaxed,
) -> Json raise @moonjson.Refused {
  @moonjson.loads(input, flavor)
}

///|
/// The same, from the UTF-8 bytes a body arrives as.
///
/// Reads the superjson envelope as ordinary JSON, preserving both the `json`
/// payload and the `meta` type table verbatim. See [`loads`] for why this
/// package does not itself reconstruct JavaScript types: the `Json` tree has
/// none to reconstruct into, and the wire form is plain JSON regardless.
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
/// A superjson payload is JSON, so writing one is just ordinary JSON output
/// (delegating to `@moonjson.dumps`). The envelope — `json` and `meta` — is
/// emitted exactly as read. `indent` of zero is the compact form. `ascii`
/// escapes everything above U+007E, for a transport that is not eight-bit
/// clean. `sort` writes members in order of name instead of the order they
/// were read in, which is what a diff wants.
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
/// Writes the tree — including any superjson `json`/`meta` envelope — as
/// ordinary JSON, delegating to `@moonjson.dump`.
pub fn dump(
  value : Json,
  indent~ : Int32 = 0,
  ascii~ : Bool = false,
  sort~ : Bool = false,
) -> Bytes {
  @moonjson.dump(value, indent~, ascii~, sort~)
}
