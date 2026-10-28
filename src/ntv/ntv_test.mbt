// JSON-NTV (Named and Typed Value) — https://datatracker.ietf.org/doc/html/draft-thomy-json-ntv-03
//
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A JSON-NTV value: a point tagged with the name `paris` and the type
/// `point`, carried by an object whose single key is `name:type`.
let paris : String =
  #|{"paris:point": [2.3522, 48.8566]}

///|
test "a tagged value is read as an ordinary JSON object" {
  // Because JSON-NTV is valid JSON, `@ntv.loads` must produce the very same
  // tree `@json.loads` does for the same document.
  assert_eq(@ntv.loads(paris[:]), @json.loads(paris[:]))
}

///|
test "the name:type key is preserved, not decoded" {
  let doc = @ntv.loads(paris[:])
  match doc {
    Object(members) =>
      // The key survives verbatim, with its `:` and its `type` suffix.
      assert_eq(
        members.get("paris:point"),
        Some(@json.loads("[2.3522, 48.8566]")),
      )
    _ => fail("expected an object")
  }
}

///|
test "loads to dumps round-trips through the JSON tree" {
  // Reading, writing and reading again must leave the structure unchanged,
  // since the `name:type` key is an honest JSON member key.
  let once = @ntv.loads(paris[:])
  let twice = @json.loads(@ntv.dumps(once))
  assert_eq(once, twice)
}

///|
test "a plain JSON value is also a JSON-NTV value" {
  // JSON-NTV imposes nothing on an untagged value: `1`, `"x"`, `[1,2]` all
  // read and write exactly as strict JSON would.
  let plain =
    #|{"city": "Paris", "coords": [2.3522, 48.8566], "pop": 2148}
  assert_eq(@ntv.loads(plain[:]), @json.loads(plain[:]))
}
