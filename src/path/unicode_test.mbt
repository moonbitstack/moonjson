// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A character above U+FFFF is one character. The compliance suite does not
/// hold a length case over one, and a reader that counted UTF-16 code units
/// would answer two.
test "length counts characters, not code units" {
  let doc = @json.loads("[\"😀\",\"é\",\"a😀b\"]")
  assert_eq(
    @json.dumps(Json::array(@path.select(doc, "$[?length(@)==1]"[:]))),
    "[\"😀\",\"é\"]",
  )
  assert_eq(
    @json.dumps(Json::array(@path.select(doc, "$[?length(@)==3]"[:]))),
    "[\"a😀b\"]",
  )
}

///|
/// Strings compare by code point (RFC 9535 §2.3.5.2.2), and code point order
/// is not code unit order: U+1D11E is greater than U+FFFF, though its first
/// code unit is less than it.
test "strings compare by code point" {
  let doc = @json.loads("[\"𝄞\"]")
  assert_eq(
    @json.dumps(Json::array(@path.select(doc, "$[?@ > \"\\uFFFF\"]"[:]))),
    "[\"𝄞\"]",
  )
}
