// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A refusal in text says which line and column, counting from one, because
/// that is how an editor counts and a message a person cannot find in their
/// file is half a message.
test "the message names the line and the column" {
  let refused = try
    @moonjson.loads("{\n  \"a\": 1,\n}"[:], @moonjson.strict)
  catch {
    error => error
  } noraise {
    _ => fail("a trailing comma was accepted")
  }
  assert_eq(refused.message(), "line 3, column 1: unexpected '}'")
}

///|
/// The first thing wrong with the document is the thing named — the comma
/// before the bracket, not something further along.
test "a trailing comma is refused where the bracket is" {
  let refused = try @moonjson.loads("{\"a\":1,}"[:], @moonjson.strict) catch {
    error => error
  } noraise {
    _ => fail("a trailing comma was accepted")
  }
  assert_eq(refused.message(), "line 1, column 8: unexpected '}'")
}

///|
/// A comment is not part of JSON, so the solidus begins a second value, and
/// the message says which line that second value is on.
test "a comment is a second value, and says where" {
  let refused = try
    @moonjson.loads("{\"a\":1} //x"[:], @moonjson.strict)
  catch {
    error => error
  } noraise {
    _ => fail("a comment was accepted")
  }
  assert_eq(
    refused.message(),
    "line 1, column 9: a second value follows the first, and a document is one value",
  )
}

///|
test "a document that ends inside a value says so" {
  let refused = try @moonjson.loads("{\"a\":"[:], @moonjson.strict) catch {
    error => error
  } noraise {
    _ => fail("an unfinished object was accepted")
  }
  assert_eq(
    refused.message(),
    "line 1, column 6: the document ends inside a value",
  )
}

///|
/// A character that would end the quoting is escaped, so the message stays
/// readable instead of turning into three quotes in a row.
test "a quote in the message is escaped" {
  let refused = try @moonjson.loads("'x'"[:], @moonjson.strict) catch {
    error => error
  } noraise {
    _ => fail("a single-quoted string was accepted")
  }
  assert_eq(refused.message(), "line 1, column 1: unexpected '\\''")
}

///|
/// A binary format has no lines, so it names the byte offset instead of
/// inventing one.
test "a byte offset stands in where there are no lines" {
  let short : @moonjson.Refused = @moonjson.Short(at=3)
  assert_eq(short.message(), "byte 3: the document ends inside a value")
  let extra : @moonjson.Refused = @moonjson.Extra(at=9)
  assert_eq(extra.message(), "byte 9: something follows the value")
  let bad : @moonjson.Refused = @moonjson.Bad(at=1, why="a reserved length")
  assert_eq(bad.message(), "byte 1: a reserved length")
}

///|
/// A value a format cannot carry has no position at all, and the message does
/// not pretend otherwise.
test "an unwritable value names the reason only" {
  let refused : @moonjson.Refused = @moonjson.Unwritable(
    why="a byte string has no JSON form",
  )
  assert_eq(
    refused.message(),
    "this value cannot be written: a byte string has no JSON form",
  )
}

///|
/// A pointer and a patch are about paths, so their messages name the path.
test "a pointer error names the pointer" {
  let syntax : @moonjson.Refused = @moonjson.Syntax(path="/a~2", at=3)
  assert_eq(
    syntax.message(),
    "the pointer \"/a~2\" is not a pointer, at offset 3",
  )
  let missing : @moonjson.Refused = @moonjson.Missing(path="/a", token="b")
  assert_eq(missing.message(), "the pointer \"/a\" names no \"b\"")
}

///|
/// Every variant answers, so a caller never has to special-case one.
test "every refusal has a message" {
  let all : Array[@moonjson.Refused] = [
    @moonjson.Truncated({ at: 0, line: 1, column: 1, }),
    @moonjson.BadEscape({ at: 0, line: 1, column: 1, }),
    @moonjson.BadNumber({ at: 0, line: 1, column: 1, }),
    @moonjson.TooDeep({ at: 0, line: 1, column: 1, }),
    @moonjson.BadUtf8({ at: 0, line: 1, column: 1, }),
    @moonjson.Repeated({ at: 0, line: 1, column: 1, }, "a"),
    @moonjson.Document(why="not an array"),
    @moonjson.Operation(at=0, why="no op member"),
    @moonjson.TestFailed(path="/a"),
    @moonjson.IntoChild(from="/a", path="/a/b"),
    @moonjson.Root(path="/a"),
    @moonjson.BadIndex(path="/a", token="01"),
    @moonjson.NotContainer(path="/a", token="b"),
  ]
  for refused in all {
    assert_true(refused.message().length() > 0)
  }
}

///|
/// The sentence the guide prints, so the page and the library cannot drift.
test "the guide's example prints this sentence" {
  let refused = try
    @moonjson.loads("{\n  \"a\": 1,\n  \"b\": ?\n}"[:], @moonjson.strict)
  catch {
    error => error
  } noraise {
    _ => fail("a question mark was accepted as a value")
  }
  assert_eq(refused.message(), "line 3, column 8: unexpected '?'")
}
