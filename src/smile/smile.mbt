// Smile binary data format — https://github.com/FasterXML/smile-format-specification
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How Smile is read and written.
///
/// The byte layout itself is fixed by the spec; the one knob is how deep a
/// document may nest before it is refused, because a document of a hundred
/// thousand open brackets is a denial of service rather than a document.
pub(all) struct Policy {
  /// The deepest nesting accepted, in levels.
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
/// What a tree becomes when a Smile value has no JSON counterpart.
///
/// JSON has no byte string and no notion of a tag, `undefined` or a non-string
/// key, so those four are carried as objects with one reserved member each,
/// the same markers every other binary package in this family uses, so a value
/// read from Smile and written to CBOR keeps its meaning:
///
/// | Smile | tree |
/// |:--|:--|
/// | `binary` | `{"$bytes": "0102"}` — lowercase hex, no separators |
/// | `tag(n, v)` | `{"$tag": n, "value": v}` |
/// | `{k: v}` with a non-string key | `{"$map": [[k, v], ...]}` |
/// | `simple(n)` | `{"$simple": n}` |
/// | `undefined` | `{"$undefined": true}` |
///
/// Of these, only `$bytes` has a native Smile form: Smile's binary value. So
/// the encoder turns a single-member `{"$bytes": "hex"}` object into a Smile
/// binary, and the decoder turns a Smile binary back into `{"$bytes": "hex"}`.
/// The remaining four markers (`$tag`, `$map`, `$simple`, `$undefined`) have
/// no native Smile encoding; they are written as the plain objects they are
/// and read back as plain objects, so a tree that already carries one
/// round-trips without it being mistaken for something else.
pub fn load(
  input : BytesView,
  policy~ : Policy = policy,
) -> Json raise @moonjson.Refused {
  let r : Reader = { src: input, policy, i: 0, }
  r.header()
  let value = r.value(0)
  if r.i < input.length() {
    if r.byte() != 0x00 {
      raise @moonjson.Extra(at=r.i)
    }
    if r.i < input.length() {
      raise @moonjson.Extra(at=r.i)
    }
  }
  value
}

///|
/// Write a tree as Smile.
pub fn dump(
  value : Json,
  policy~ : Policy = policy,
) -> Bytes raise @moonjson.Refused {
  let buf = Buffer()
  buf.write_byte(0x3A)
  buf.write_byte(0x29)
  buf.write_byte(0x0A)
  buf.write_byte(0x00)
  write(buf, value, policy)
  buf.write_byte(0x00)
  buf.to_bytes()
}
