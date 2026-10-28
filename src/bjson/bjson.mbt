// bjson — "Binary JSON".
//
// No finalized, canonical, portable BJSON specification exists. `bjson.org`
// publishes a *draft* (v0.5) explicitly marked subject to change, and at least
// two other incompatible "Binary JSON" formats exist: the `bjson` npm library
// (belteshazzar/bjson) and QuickJS's internal Binary JSON. This package
// therefore implements a small, self-consistent *minimal* reader/writer in the
// spirit of the bjson.org draft (little-endian, one-byte type tags,
// length-prefixed containers) and documents it as such rather than claiming
// conformance to a stable standard. The `Json` tree carries the one value JSON
// has no syntax for — raw bytes — through the shared markers documented on
// `load`.

///|
/// How bjson is read and written.
pub(all) struct Policy {
  /// How deep nesting may go, shared with the rest of the family. A document of
  /// a hundred thousand open containers is a denial of service rather than a
  /// document, so the same five hundred the text reader allows is the default.
  depth : Int32
} derive(Eq, Debug)

///|
pub extend Policy with Eq::{equal, not_equal}

///|
pub extend Policy with Debug::{to_repr}

///|
/// The default: five hundred levels deep.
pub let policy : Policy = { depth: 500, }

///|
/// Build a policy naming the depth that differs from the default.
pub fn Policy::new(depth~ : Int32 = policy.depth) -> Policy {
  { depth, }
}

///|
/// Read one bjson document from its bytes.
///
/// bjson is binary JSON, so the one type JSON has no syntax for — raw bytes —
/// comes back through the same markers every binary package in this family uses,
/// so a value read here and written to CBOR or BSON keeps its bytes:
///
/// | bjson | tree |
/// |:--|:--|
/// | `0x0B`–`0x0D` binary | `{"$bytes": "0102"}` — lowercase hex, no separators |
/// | `0x10` undefined | `{"$undefined": true}` |
///
/// (The full marker set used across the family is `$bytes`, `$tag`, `$map`,
/// `$simple`, `$undefined`; this minimal reader accepts `$bytes` and
/// `$undefined`, which are the ones a binary-JSON round trip needs.)
pub fn load(
  input : BytesView,
  policy~ : Policy = policy,
) -> Json raise @moonjson.Refused {
  let r : Reader = { src: input, policy, i: 0, }
  let value = r.value(0)
  if r.i < input.length() {
    raise @moonjson.Extra(at=r.i)
  }
  value
}

///|
/// Write a tree as bjson.
///
/// A value of any shape is accepted at the top level. The types JSON has no
/// syntax for are written through the `$bytes` and `$undefined` markers
/// documented on [`load`], so a tree read from another binary package survives
/// the round trip.
pub fn dump(
  value : Json,
  policy~ : Policy = policy,
) -> Bytes raise @moonjson.Refused {
  let buf = Buffer()
  write(buf, value, policy, 0)
  buf.to_bytes()
}
