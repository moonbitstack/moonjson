// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How wide a float is written.
pub(all) enum Floats {
  /// 32 bits when the value comes back unchanged, 64 when it does not.
  Shortest
  /// Always 64 bits.
  Double
} derive(Eq, Debug)

///|
pub extend Floats with Eq::{equal, not_equal}

///|
pub extend Floats with Debug::{to_repr}

///|
/// How MessagePack is read and written.
pub(all) struct Policy {
  /// The reference implementation, Python's `msgpack`, writes every float as a
  /// double unless it is told otherwise, so that is the default: a 32-bit float
  /// that reads back the same is smaller but is not what the other side
  /// expects to see.
  floats : Floats
  /// How deep nesting may go before the document is refused.
  depth : Int32
} derive(Eq, Debug)

///|
pub extend Policy with Eq::{equal, not_equal}

///|
pub extend Policy with Debug::{to_repr}

///|
/// The defaults: doubles, five hundred levels.
pub let policy : Policy = { floats: Double, depth: 500, }

///|
/// Build a policy by naming the parts that differ from the defaults.
pub fn Policy::new(
  floats~ : Floats = policy.floats,
  depth~ : Int32 = policy.depth,
) -> Policy {
  { floats, depth, }
}

///|
/// Read one MessagePack document.
///
/// What JSON cannot hold comes back as the family's markers:
///
/// | MessagePack | tree |
/// |:--|:--|
/// | `bin` | `{"$bytes": "0102"}` — lowercase hex |
/// | `ext` | `{"$ext": 1, "data": "0102"}` — the type as a number |
/// | an integer above 2^53 | a number that keeps its digits as text |
///
/// The same markers are read back as extensions and byte strings, so a
/// document survives a round trip through this package.
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
/// Write a tree as MessagePack.
pub fn dump(
  value : Json,
  policy~ : Policy = policy,
) -> Bytes raise @moonjson.Refused {
  let buf = Buffer()
  write(buf, value, policy)
  buf.to_bytes()
}
