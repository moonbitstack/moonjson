// Universal Binary JSON (UBJSON) — https://ubjson.org/
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How UBJSON is read and written.
///
/// The one knob the format leaves open is how deep a document may nest before it
/// is refused, because a document of a hundred thousand open brackets is a
/// denial of service rather than a document.
pub(all) struct Policy {
  /// How deep nesting may go. The same five hundred the text reader allows, and
  /// for the same reason: a document of a hundred thousand open brackets is a
  /// denial of service rather than a document.
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
/// Build a policy by naming the parts that differ from the default.
pub fn Policy::new(depth~ : Int32 = policy.depth) -> Policy {
  { depth, }
}

///|
/// What a tree becomes when a UBJSON value has no JSON counterpart.
///
/// UBJSON *is* JSON's data model — null, true, false, numbers, strings, arrays
/// and objects, with no byte strings, no tags, no `undefined` and no non-string
/// map keys — so most of the markers the rest of this family uses have no
/// UBJSON form. They are documented here, and what UBJSON cannot carry is either
/// written as the closest plain thing or, for bytes, as an array:
///
/// | UBJSON | tree |
/// |:--|:--|
/// | `blob` | `{"$bytes": "0102"}` — written as a UBJSON array `[U 01, U 02]` of uint8; reading that array back yields a plain array, not the marker — UBJSON has no byte string, so the marker is one-way (documented, not round-tripped) |
/// | `1(1363896240)` | `{"$tag": 1, "value": 1363896240}` — written as a plain object with those members |
/// | `{1: 2}` | `{"$map": [[1, 2]]}` — written as a plain object |
/// | `simple(16)` | `{"$simple": 16}` — written as a plain object |
/// | `undefined` | `{"$undefined": true}` — written as a plain object |
///
/// A document that means `{"$bytes": "00"}` as data therefore has to be written
/// in the `$map` form, because the marker is reserved — the same bargain every
/// other package in this family makes, here reduced to a single marker that has
/// only a one-way encoding. The other four markers (`$tag`, `$map`, `$simple`,
/// `$undefined`) are written as plain objects with those member names, because
/// UBJSON has no native form for them at all.
///
/// Writing also accepts these markers: an object with exactly one `$bytes`
/// member becomes a UBJSON array of uint8, so a byte string read elsewhere and
/// written here is carried as closely as UBJSON allows. What a real UBJSON
/// document needs — numbers, strings, arrays, objects — needs no marker in the
/// tree at all, and the non-JSON markers above are only round-tripped between
/// the other packages of this family, never through UBJSON itself.
///
/// Encoding is the canonical, length-free "simple" form of the spec: containers
/// are opened with `[`/`{` and closed with `]`/`}` with a per-element type
/// marker, never the optimized `#` (count) or `$` (type) prefixes. It is
/// spec-based and is not byte-validated against an external UBJSON library,
/// because none is available in this workspace.
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
/// Write a tree as UBJSON, in the simple (no length-prefix) form.
pub fn dump(
  value : Json,
  policy~ : Policy = policy,
) -> Bytes raise @moonjson.Refused {
  let buf = Buffer()
  write(buf, value, policy)
  buf.to_bytes()
}
