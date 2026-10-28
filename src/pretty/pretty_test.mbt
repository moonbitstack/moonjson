// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Two spaces a level by default.
test "two spaces by default" {
  let text = @pretty.format(@json.loads("{\"a\":1,\"b\":[1,2]}"))
  assert_eq(text, "{\n  \"a\": 1,\n  \"b\": [\n    1,\n    2\n  ]\n}")
}

///|
/// Zero indent writes the compact form, whatever else is set.
test "compact when indent is zero" {
  let text = @pretty.format(
    @json.loads("{ \"a\": 1 }"),
    style=@pretty.Format::new(indent=0),
  )
  assert_eq(text, "{\"a\":1}")
}

///|
/// Tabs stand one to a level.
test "tabs" {
  let text = @pretty.format(
    @json.loads("{\"a\":1}"),
    style=@pretty.Format::new(tabs=true),
  )
  assert_eq(text, "{\n\t\"a\": 1\n}")
}

///|
/// CRLF puts a carriage return before every line feed.
test "crlf" {
  let text = @pretty.format(
    @json.loads("{\"a\":1}"),
    style=@pretty.Format::new(crlf=true),
  )
  assert_eq(text, "{\r\n  \"a\": 1\r\n}")
}

///|
/// Sorting orders the members, four spaces to a level.
test "reformat sorts and indents by four" {
  let text = @pretty.reformat(
    "{ \"b\":2, \"a\":1 }",
    style=@pretty.Format::new(indent=4, sort=true),
  )
  assert_eq(text, "{\n    \"a\": 1,\n    \"b\": 2\n}")
}

///|
/// The text-to-text entry point reads UTF-8 bytes too.
test "reformat bytes" {
  let bytes = @utf8.encode("{ \"a\":1 }"[:])
  let text = @pretty.reformat_bytes(bytes)
  assert_eq(@utf8.decode(text), "{\n  \"a\": 1\n}")
}

///|
/// Sorting orders three members, not only two.
test "sort three members" {
  let text = @pretty.format(
    @json.loads("{\"tls\":1,\"host\":2,\"port\":3}"),
    style=@pretty.Format::new(indent=0, sort=true),
  )
  assert_eq(text, "{\"host\":2,\"port\":3,\"tls\":1}")
}

///|
/// A document a formatter rewrote still parses to the same tree.
test "reformat preserves the tree" {
  let tree = @json.loads("{\"n\":[1,2,3],\"ok\":true}")
  let text = @pretty.format(tree)
  assert_eq(@json.loads(text[:]), tree)
}
