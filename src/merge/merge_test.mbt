// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Every case RFC 7396 Appendix A prints, as an array of triples: the target,
/// the patch, and the document that results. A `null` in the patch is an
/// instruction and one already in the target is data, which is the
/// distinction the whole format turns on.
let appendix : String =
  #|[
  #|  [{"a":"b"}, {"a":"c"}, {"a":"c"}],
  #|  [{"a":"b"}, {"b":"c"}, {"a":"b","b":"c"}],
  #|  [{"a":"b"}, {"a":null}, {}],
  #|  [{"a":"b","b":"c"}, {"a":null}, {"b":"c"}],
  #|  [{"a":["b"]}, {"a":"c"}, {"a":"c"}],
  #|  [{"a":"c"}, {"a":["b"]}, {"a":["b"]}],
  #|  [{"a":{"b":"c"}}, {"a":{"b":"d","c":null}}, {"a":{"b":"d"}}],
  #|  [{"a":[{"b":"c"}]}, {"a":[1]}, {"a":[1]}],
  #|  [["a","b"], ["c","d"], ["c","d"]],
  #|  [{"a":"b"}, ["c"], ["c"]],
  #|  [{"a":"foo"}, null, null],
  #|  [{"a":"foo"}, "bar", "bar"],
  #|  [{"e":null}, {"a":1}, {"e":null,"a":1}],
  #|  [[1,2], {"a":"b","c":null}, {"a":"b"}],
  #|  [{}, {"a":{"bb":{"ccc":null}}}, {"a":{"bb":{}}}]
  #|]

///|
/// The appendix, merged. The result is compared as text, because a member's
/// position in its object is part of the answer: one that was there stays
/// where it was, and one that is added goes on the end.
test "the RFC 7396 appendix A cases" {
  match @json.loads(appendix) {
    Array(cases) =>
      for case in cases {
        match case {
          Array(parts) => {
            let merged = @merge.merge(parts[0], parts[1])
            assert_eq(@json.dumps(merged), @json.dumps(parts[2]))
          }
          _ => fail("a case is a triple")
        }
      }
    _ => fail("the appendix is an array of cases")
  }
}

///|
/// The example RFC 7396 §3 walks through, member by member: the title changes,
/// a phone number appears, the family name goes, the tags are replaced whole,
/// and the content nobody mentioned is untouched.
test "the RFC 7396 section 3 example" {
  let target = @json.loads(
    "{\"title\":\"Goodbye!\",\"author\":{\"givenName\":\"John\",\"familyName\":\"Doe\"},\"tags\":[\"example\",\"sample\"],\"content\":\"This will be unchanged\"}",
  )
  let patch = @json.loads(
    "{\"title\":\"Hello!\",\"phoneNumber\":\"+01-123-456-7890\",\"author\":{\"familyName\":null},\"tags\":[\"example\"]}",
  )
  assert_eq(
    @json.dumps(@merge.merge(target, patch)),
    "{\"title\":\"Hello!\",\"author\":{\"givenName\":\"John\"},\"tags\":[\"example\"],\"content\":\"This will be unchanged\",\"phoneNumber\":\"+01-123-456-7890\"}",
  )
}

///|
/// The document it was given is the document it was given.
test "merging leaves the target alone" {
  let target = @json.loads("{\"a\":{\"b\":\"c\"},\"d\":1}")
  let patch = @json.loads("{\"a\":{\"b\":\"z\"},\"e\":2}")
  let merged = @merge.merge(target, patch)
  assert_eq(@json.dumps(merged), "{\"a\":{\"b\":\"z\"},\"d\":1,\"e\":2}")
  assert_eq(@json.dumps(target), "{\"a\":{\"b\":\"c\"},\"d\":1}")
}

///|
/// An empty patch object changes nothing, and a patch that is not an object
/// replaces the whole document — `null` itself among them. A target that is
/// not an object is started again from an empty one.
test "the shapes a patch can take" {
  let target = @json.loads("{\"a\":1}")
  assert_eq(@merge.merge(target, @json.loads("{}")), target)
  assert_eq(@merge.merge(target, @json.loads("[]")), @json.loads("[]"))
  assert_eq(@merge.merge(target, @json.loads("null")), Json::null())
  assert_eq(
    @json.dumps(
      @merge.merge(@json.loads("[1,2]"), @json.loads("{\"a\":\"b\"}")),
    ),
    "{\"a\":\"b\"}",
  )
  // A null that is already in the target is data, and a patch member that is
  // an object replaces the scalar or the array it was.
  assert_eq(
    @json.dumps(
      @merge.merge(@json.loads("{\"a\":null}"), @json.loads("{\"a\":1}")),
    ),
    "{\"a\":1}",
  )
  assert_eq(
    @json.dumps(
      @merge.merge(
        @json.loads("{\"a\":[1,2]}"),
        @json.loads("{\"a\":{\"b\":1}}"),
      ),
    ),
    "{\"a\":{\"b\":1}}",
  )
}
