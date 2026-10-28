// KRSON — https://crates.io/crates/krson-core (Rust core), https://www.npmjs.com/package/krson-js (JS SDK)
//
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A representative mixed document, kept as a `let` so the `#|` literal is a
/// binding rather than a raw argument.
let mixed : String =
  #|{"name": "krson", "version": 2, "ratio": 0.5, "tags": ["a", "b"], "ok": true, "n": null}

///|
/// A nested document exercising arrays of objects, negative integers and floats.
let nested : String =
  #|{"points": [{"x": -3, "y": 2.5}, {"x": 0, "y": -1.25}], "label": "hi"}

///|
/// A single member, used where a one-line literal would otherwise be a raw arg.
let single : String =
  #|{"x": 1}

///|
/// Two orderings of the same object, used to show deterministic output stability.
let abc : String =
  #|{"a": 1, "b": 2, "c": 3}

///|
let cba : String =
  #|{"c": 3, "a": 1, "b": 2}

///|
/// A KRSON schemaless document must round-trip: a tree written and read back is
/// the same tree, compared through canonical (sorted, strict) JSON text so the
/// internal integer/string representation does not matter.
test "a mixed tree round-trips through dump and load" {
  let tree = @json.loads(mixed)
  let back = @krson.load(@krson.dump(tree))
  assert_eq(@json.dumps(back, sort=true), @json.dumps(tree, sort=true))
}

///|
/// Nested arrays of objects, negative integers and negative floats all survive the
/// round trip.
test "nested arrays, objects, negatives and floats round-trip" {
  let tree = @json.loads(nested)
  let back = @krson.load(@krson.dump(tree))
  assert_eq(@json.dumps(back, sort=true), @json.dumps(tree, sort=true))
}

///|
/// A KRSON buffer is identified by its `KR` magic, written at the first two bytes.
test "the buffer begins with the 'KR' magic" {
  let bytes = @krson.dump(@json.loads(single))
  assert_eq(bytes.at(0), 0x4B)
  assert_eq(bytes.at(1), 0x52)
}

///|
/// A document nested deeper than the policy's depth limit is refused on load,
/// which is what keeps a hostile document from exhausting the stack.
test "nesting past the depth limit is refused" {
  let mut doc = "0"
  for _ in 0..<50 {
    doc = "[" + doc + "]"
  }
  let tree = @json.loads(doc)
  let bytes = @krson.dump(tree)
  try @krson.load(bytes, policy=@krson.Policy::new(depth=10)) |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("the depth limit was not enforced on load")
  }
}

///|
/// Bytes that do not start with the `KR` magic are not a KRSON document and are
/// refused rather than misread.
test "a non-KRSON buffer is refused" {
  let bad = @utf8.encode(single)
  try @krson.load(bad) |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("a non-KRSON buffer was accepted")
  }
}

///|
/// With `deterministic` on, the same value reached through a different key order
/// yields byte-identical output, because both the string table and the object
/// keys are sorted.
test "deterministic mode is stable under key reordering" {
  let pa = @krson.dump(
    @json.loads(abc),
    policy=@krson.Policy::new(deterministic=true),
  )
  let pb = @krson.dump(
    @json.loads(cba),
    policy=@krson.Policy::new(deterministic=true),
  )
  assert_eq(pa, pb)
}
