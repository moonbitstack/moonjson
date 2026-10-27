// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How BSON is read and written.
pub(all) struct Policy {
  /// How deep a document may nest. BSON documents nest inside documents, and a
  /// chain of them is as good a way to exhaust a stack as a chain of brackets.
  depth : Int32
} derive(Eq, Debug)

///|
pub extend Policy with Eq::{equal, not_equal}

///|
pub extend Policy with Debug::{to_repr}

///|
/// The defaults: five hundred levels.
pub let policy : Policy = { depth: 500, }

///|
/// BSON writes `int32` and `int64` as two types and the tree holds one number,
/// so a number is written in the narrowest width that holds it — the same
/// choice the reference implementations make when they are handed a language
/// integer rather than a typed one. The value is the same; only the width
/// differs, and `int32` is what MongoDB itself uses below two billion.
pub fn Policy::new(depth~ : Int32 = policy.depth) -> Policy {
  { depth, }
}

///|
/// Read one BSON document.
///
/// A BSON document is always an object at the top, and the types JSON has no
/// syntax for come back as markers:
///
/// | BSON | tree |
/// |:--|:--|
/// | binary, subtype 0 | `{"$bytes": "0102"}` |
/// | binary, any other subtype | `{"$binary": {"kind": 4, "data": "0102"}}` |
/// | ObjectId | `{"$oid": "507f1f77bcf86cd799439011"}` |
/// | UTC datetime | `{"$date": 1356350400000}` — milliseconds |
/// | regular expression | `{"$regex": "^a", "options": "i"}` |
/// | DBPointer | `{"$dbpointer": {"ns": "db.c", "oid": "…"}}` |
/// | JavaScript | `{"$code": "…"}` |
/// | JavaScript with scope | `{"$code": "…", "$scope": {…}}` |
/// | symbol | `{"$symbol": "…"}` |
/// | timestamp | `{"$timestamp": {"t": 1, "i": 2}}` |
/// | decimal128 | `{"$decimal128": "…32 hex digits…"}` |
/// | undefined | `{"$undefined": true}` |
/// | MinKey / MaxKey | `{"$minKey": true}` / `{"$maxKey": true}` |
///
/// Writing reads the same markers back, so a document that goes through the
/// tree comes out as it went in. A marker is a reserved name: an object whose
/// only member is `$oid` is an ObjectId, not a document that happens to have
/// that member.
pub fn load(
  input : BytesView,
  policy~ : Policy = policy,
) -> Json raise @moonjson.Refused {
  let r : Reader = { src: input, policy, i: 0, }
  let value = r.document(0)
  if r.i < input.length() {
    raise @moonjson.Extra(at=r.i)
  }
  value
}

///|
/// Write a tree as a BSON document.
pub fn dump(
  value : Json,
  policy~ : Policy = policy,
) -> Bytes raise @moonjson.Refused {
  match value {
    Object(_) => {
      let buf = Buffer()
      document(buf, value, policy)
      buf.to_bytes()
    }
    _ =>
      raise @moonjson.Unwritable(why="a BSON document is an object at the top")
  }
}
