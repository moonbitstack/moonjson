// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a stream of records reads one to a line" {
  let text =
    #|{"name":"ada","born":1815}
    #|{"name":"grace","born":1906}
    #|{"name":"katherine","born":1918}
  let records = @lines.loads_all(text[:])
  assert_eq(records.length(), 3)
  assert_eq(@lines.dumps_all(records[:]), text + "\n")
  match records[1] {
    Object(members) =>
      assert_eq(members.get("name"), Some(Json::string("grace")))
    _ => fail("a record did not parse as an object")
  }
}

///|
/// Every line ends in a line feed, including the last, so a file can be
/// appended to without reading it first — which is the whole point of the
/// format.
test "the last line ends in a newline too" {
  assert_eq(@lines.dumps_all([Json::number(1.0, repr="1")][:]), "1\n")
  assert_eq(@lines.dumps_all([][:]), "")
}

///|
/// Files grown by appending end up with a blank line, and half the tools that
/// write them run on Windows; neither may make the reader fail.
test "blank lines and carriage returns are tolerated" {
  assert_eq(@lines.loads_all("[1]\n\n[2]\n").length(), 2)
  assert_eq(@lines.loads_all("[1]\r\n[2]\r\n").length(), 2)
  assert_eq(@lines.loads_all("").length(), 0)
  assert_eq(@lines.loads_all("\n\n\n").length(), 0)
  assert_eq(@lines.loads_all("   \n\t\n").length(), 0)
  // No trailing newline at all is still a record.
  assert_eq(@lines.loads_all("[1]").length(), 1)
}

///|
/// A record spanning two lines is not one record; each line must stand alone.
test "a record may not span lines" {
  try @lines.loads_all("[1,\n2]") |> ignore catch {
    _ => ()
  } noraise {
    _ => fail("a record split across two lines was accepted")
  }
}

///|
test "bytes in and out" {
  let records = @lines.load_all(b"{\"a\":1}\n{\"b\":2}\n"[:])
  assert_eq(records.length(), 2)
  assert_eq(@lines.dump_all(records[:]), b"{\"a\":1}\n{\"b\":2}\n")
}
