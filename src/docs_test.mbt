// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The document the front page and the guide both work on: read, change one
/// field, and query.
let spec : String =
  #|{
  #|  "spec": { "replicas": 1, "image": "app:1" }
  #|}

///|
/// Every value the README and the skill print, asserted against the library.
/// A page shows a result; if the library moves one, this fails here rather than
/// in front of a reader.
test "the front page" {
  let config = @json.loads("{\"host\":\"localhost\",\"port\":8080}")
  assert_eq(@json.dumps(config), "{\"host\":\"localhost\",\"port\":8080}")
  assert_eq(
    @json.dumps(config, indent=2),
    "{\n  \"host\": \"localhost\",\n  \"port\": 8080\n}",
  )
  let source =
    #|{
    #|  "port": 8080,  // the one we bound
    #|}
  assert_eq(@jsonc.loads(source[:]), @json.loads("{\"port\":8080}"))
  assert_eq(@json.dumps(@pointer.get(config, "/port")), "8080")
}

///|
/// The guide's first task: a document read, one field changed, the document
/// written back.
test "one field changed and written back" {
  let cfg = @jsonc.loads(spec[:])
  let wanted = @pointer.set(cfg, "/spec/replicas", Json::number(5))
  assert_eq(
    @json.dumps(wanted),
    "{\"spec\":{\"replicas\":5,\"image\":\"app:1\"}}",
  )
}

///|
/// The same tree under another notation: JSON5 in, CBOR out, CBOR back in, and
/// the tree that comes out is the one that went in. The members are in the
/// canonical order rather than the order they were read in, because that is
/// what deterministic encoding is.
test "a tree crosses notations unchanged" {
  let doc = @json5.loads("{host:'localhost',port:8080,tls:false}")
  let body = @cbor.dump(doc)
  assert_eq(@cbor.load(body[:]), doc)
  assert_eq(
    @json.dumps(@cbor.load(body[:])),
    "{\"tls\":false,\"host\":\"localhost\",\"port\":8080}",
  )
  let loose = @cbor.Policy::new(deterministic=false)
  assert_eq(
    @json.dumps(@cbor.load(@cbor.dump(doc, policy=loose)[:])),
    "{\"host\":\"localhost\",\"port\":8080,\"tls\":false}",
  )
}

///|
/// How to read is a value, and the two ways of building one agree: the
/// constructor and the record update both lie over the dialect's preset.
test "the flavor is one record, built two ways" {
  let same = @jsonc.loads(spec[:])
  assert_eq(same, @json.loads(spec[:]))
  assert_eq(@json.loads(spec[:], flavor=@moonjson.Flavor::new(depth=100)), same)
  assert_eq(
    @json.loads(spec[:], flavor={
      ..@moonjson.strict,
      duplicates: @moonjson.Duplicates::First,
    }),
    same,
  )
}

///|
/// Two of the three settings a writer takes, on documents that show what they
/// do.
test "writing escapes and sorts" {
  assert_eq(
    @json.dumps(
      @json.loads("{\"city\":\"\u{5965}\u{514b}\u{5170}\"}"),
      ascii=true,
    ),
    "{\"city\":\"\\u5965\\u514b\\u5170\"}",
  )
  assert_eq(
    @json.dumps(
      @json.loads("{\"port\":8080,\"host\":\"localhost\"}"),
      sort=true,
    ),
    "{\"host\":\"localhost\",\"port\":8080}",
  )
}

///|
/// A number keeps the text it was written as, including one a double cannot
/// hold, so the document comes back byte for byte.
test "a number keeps its digits" {
  let wide = "[1e400,12345678901234567890,0.1]"
  assert_eq(@json.dumps(@json.loads(wide)), wide)
}

///|
/// The three ways of changing a document, on the one document: a pointer names
/// a place, a patch is a list of operations that all hold or none does, and a
/// merge patch looks like the document.
test "a pointer, a patch and a merge patch" {
  let cfg = @jsonc.loads(spec[:])
  let patched = @pointer.set(cfg, "/spec/replicas", Json::number(5))
  let ops = @patch.loads(
    "[{\"op\":\"test\",\"path\":\"/spec/replicas\",\"value\":5},{\"op\":\"replace\",\"path\":\"/spec/image\",\"value\":\"app:2\"}]",
  )
  assert_eq(
    @json.dumps(@patch.apply(patched, ops)),
    "{\"spec\":{\"replicas\":5,\"image\":\"app:2\"}}",
  )
  assert_eq(
    @json.dumps(
      @merge.merge(patched, @json.loads("{\"spec\":{\"image\":null}}")),
    ),
    "{\"spec\":{\"replicas\":5}}",
  )
}

///|
/// A query rather than a pointer: the same answer whether the pattern is given
/// once or compiled and kept.
test "a query names a set of places" {
  let shelf = @json.loads(
    "{\"store\":{\"book\":[{\"title\":\"A\",\"price\":8.95},{\"title\":\"B\",\"price\":12.99},{\"title\":\"C\",\"price\":8.99}]}}",
  )
  let cheap = @path.select(shelf, "$..book[?@.price < 10].title")
  assert_eq(@json.dumps(Json::array(cheap)), "[\"A\",\"C\"]")
  let query = @path.compile("$.store.book[*].title")
  assert_eq(
    @json.dumps(Json::array(query.select(shelf))),
    "[\"A\",\"B\",\"C\"]",
  )
}

///|
/// A refusal says what and where, and `message` writes the same sentence with
/// the character that was found.
test "a refusal carries a line and a column" {
  let broken =
    #|{
    #|  "a": 1,
    #|  "b": ?
    #|}
  let refused = try @json.loads(broken[:]) catch {
    error => error
  } noraise {
    _ => fail("an unquoted value was accepted")
  }
  let spot = refused.at().unwrap()
  assert_eq(spot.line, 3)
  assert_eq(spot.column, 8)
  assert_eq(refused.message(), "line 3, column 8: unexpected '?'")
}

///|
/// The stream the `lines` package defines, and the count the guide prints for
/// it.
test "a stream of documents is one per line" {
  let records = @lines.loads_all("{\"n\":1}\n{\"n\":2}\n{\"n\":3}\n")
  assert_eq(records.length(), 3)
  assert_eq(@lines.dumps_all(records), "{\"n\":1}\n{\"n\":2}\n{\"n\":3}\n")
}
