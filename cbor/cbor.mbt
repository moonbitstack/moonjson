// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How CBOR is read and written.
///
/// Two knobs, both of them things the RFC leaves open rather than things we
/// invented: whether to write the deterministic form, and how deep a document
/// may nest before it is refused.
pub(all) struct Policy {
  /// Write the deterministic encoding of RFC 8949 §4.2.3: the shortest form for
  /// every length and every number, floats in the shortest width that reads
  /// back as the same value, and map keys in bytewise order of their encodings.
  ///
  /// It is on by default because that is what the RFC §4.2 recommends and what
  /// a signature or a hash over the encoding needs. Turning it off still writes
  /// valid CBOR — every float becomes a double and map keys keep the order the
  /// tree has — which is what a reader that does not care about byte identity
  /// may prefer, because it is cheaper.
  deterministic : Bool
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
/// The defaults: deterministic, five hundred levels deep.
pub let policy : Policy = { deterministic: true, depth: 500, }

///|
pub fn Policy::new(
  deterministic~ : Bool = policy.deterministic,
  depth~ : Int32 = policy.depth,
) -> Policy {
  { deterministic, depth, }
}

///|
/// What a tree becomes when a CBOR value has no JSON counterpart.
///
/// JSON has no byte strings, no tags, no `undefined` and no map keys that are
/// not strings, so those four are carried as objects with one reserved member
/// each. They are the same markers every other binary package in this family
/// uses, so a value read from CBOR and written to MessagePack keeps its bytes:
///
/// | CBOR | tree |
/// |:--|:--|
/// | `h'0102'` | `{"$bytes": "0102"}` — lowercase hex, no separators |
/// | `1(1363896240)` | `{"$tag": 1, "value": 1363896240}` |
/// | `undefined` | `{"$undefined": true}` |
/// | `simple(16)` | `{"$simple": 16}` |
/// | `{1: 2}` | `{"$map": [[1, 2]]}` — any map with a key that is not a string |
///
/// A map whose keys are all strings is written as a plain object, and a plain
/// object is read back as a map. A document that means `{"$bytes": "00"}` as
/// data has to be written in the `$map` form, because the marker is reserved —
/// the same bargain MongoDB's Extended JSON makes, and for the same reason:
/// a tree with one object type needs one reserved name.
///
/// Writing also accepts these markers: an object with exactly one `$bytes`
/// member becomes a byte string, and so on for the rest. What was read from
/// CBOR is therefore written back as the same CBOR, and MessagePack's byte
/// strings, BSON's binary and CBOR's are one thing in the tree.
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
/// The same, from a `Bytes` — how a body arrives.
pub fn loads(
  input : Bytes,
  policy~ : Policy = policy,
) -> Json raise @moonjson.Refused {
  load(input[:], policy~)
}

///|
/// Write a tree as CBOR.
pub fn dump(
  value : Json,
  policy~ : Policy = policy,
) -> Bytes raise @moonjson.Refused {
  let buf = Buffer()
  write(buf, value, policy)
  buf.to_bytes()
}
