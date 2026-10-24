// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The vectors published with RFC 8785: an input document and the one line it
/// must canonicalise to. They come from the reference test data the RFC points
/// at, not from this implementation, which is what makes them a criterion
/// rather than a record of what we happen to do.
let vectors : Array[(String, String)] = [
  // arrays.json from the reference vectors RFC 8785 points at.
  (
    "[\n  56,\n  {\n    \"d\": true,\n    \"10\": null,\n    \"1\": [ ]\n  }\n]\n",
    "[56,{\"1\":[],\"10\":null,\"d\":true}]",
  ),
  // french.json from the reference vectors RFC 8785 points at.
  (
    "{\n  \"peach\": \"This sorting order\",\n  \"péché\": \"is wrong according to French\",\n  \"pêche\": \"but canonicalization MUST\",\n  \"sin\":   \"ignore locale\"\n}\n",
    "{\"peach\":\"This sorting order\",\"péché\":\"is wrong according to French\",\"pêche\":\"but canonicalization MUST\",\"sin\":\"ignore locale\"}",
  ),
  // structures.json from the reference vectors RFC 8785 points at.
  (
    "{\n  \"1\": {\"f\": {\"f\": \"hi\",\"F\": 5} ,\"\\n\": 56.0},\n  \"10\": { },\n  \"\": \"empty\",\n  \"a\": { },\n  \"111\": [ {\"e\": \"yes\",\"E\": \"no\" } ],\n  \"A\": { }\n}",
    "{\"\":\"empty\",\"1\":{\"\\n\":56,\"f\":{\"F\":5,\"f\":\"hi\"}},\"10\":{},\"111\":[{\"E\":\"no\",\"e\":\"yes\"}],\"A\":{},\"a\":{}}",
  ),
  // unicode.json from the reference vectors RFC 8785 points at.
  (
    "{\n  \"Unnormalized Unicode\":\"A\\u030a\"\n}\n", "{\"Unnormalized Unicode\":\"Å\"}",
  ),
  // values.json from the reference vectors RFC 8785 points at.
  (
    "{\n  \"numbers\": [333333333.33333329, 1E30, 4.50, 2e-3, 0.000000000000000000000000001],\n  \"string\": \"\\u20ac$\\u000F\\u000aA'\\u0042\\u0022\\u005c\\\\\\\"\\/\",\n  \"literals\": [null, true, false]\n}",
    "{\"literals\":[null,true,false],\"numbers\":[333333333.3333333,1e+30,4.5,0.002,1e-27],\"string\":\"€$\\u000f\\nA'B\\\"\\\\\\\\\\\"/\"}",
  ),
  // weird.json from the reference vectors RFC 8785 points at.
  (
    "{\n  \"\\u20ac\": \"Euro Sign\",\n  \"\\r\": \"Carriage Return\",\n  \"\\u000a\": \"Newline\",\n  \"1\": \"One\",\n  \"\\u0080\": \"Control\\u007f\",\n  \"\\ud83d\\ude02\": \"Smiley\",\n  \"\\u00f6\": \"Latin Small Letter O With Diaeresis\",\n  \"\\ufb33\": \"Hebrew Letter Dalet With Dagesh\",\n  \"</script>\": \"Browser Challenge\"\n}\n",
    "{\"\\n\":\"Newline\",\"\\r\":\"Carriage Return\",\"1\":\"One\",\"</script>\":\"Browser Challenge\",\"\u{0080}\":\"Control\u{007f}\",\"ö\":\"Latin Small Letter O With Diaeresis\",\"€\":\"Euro Sign\",\"\u{1f602}\":\"Smiley\",\"דּ\":\"Hebrew Letter Dalet With Dagesh\"}",
  ),
]

///|
/// Every published vector, canonicalised and compared as bytes.
test "the RFC 8785 vectors" {
  for row in vectors {
    let (input, want) = row
    assert_eq(@jcs.dumps(@json.loads(input[:])), want)
  }
}

///|
/// The RFC's own sample document, which is the one everybody quotes.
test "the RFC's sample document" {
  let input = "{\n  \"numbers\": [333333333.33333329, 1E30, 4.50, 2e-3, 0.000000000000000000000000001],\n  \"string\": \"\\u20ac$\\u000F\\u000aA'\\u0042\\u0022\\u005c\\\\\\\"\\/\",\n  \"literals\": [null, true, false]\n}"
  assert_eq(
    @jcs.dumps(@json.loads(input)),
    "{\"literals\":[null,true,false],\"numbers\":[333333333.3333333,1e+30,4.5,0.002,1e-27],\"string\":\"€$\\u000f\\nA'B\\\"\\\\\\\\\\\"/\"}",
  )
}

///|
/// A number is canonicalised by value, so the text it arrived as is gone.
test "number forms collapse" {
  let cases : Array[(String, String)] = [
    ("1e2", "100"),
    ("100.0", "100"),
    ("1.0e2", "100"),
    ("-0.0", "0"),
    ("-0", "0"),
    ("0.000001", "0.000001"),
    ("0.0000001", "1e-7"),
    ("1e20", "100000000000000000000"),
    ("1e21", "1e+21"),
    ("1.7976931348623157e308", "1.7976931348623157e+308"),
    ("5e-324", "5e-324"),
    ("2.5e-10", "2.5e-10"),
    ("12345678901234567890", "12345678901234567000"),
  ]
  for row in cases {
    let (input, want) = row
    assert_eq(@jcs.dumps(@json.loads(input)), want)
  }
}

///|
/// Sorting is by UTF-16 code unit, not by code point and not by locale. A
/// surrogate pair starts at U+D83D, so it sorts below U+E000 even though the
/// character it stands for is above it; an accented letter sorts after an
/// unaccented one because that is what the code units say.
test "names sort as UTF-16 units" {
  let doc = @json.loads(
    "{\"\\ud83d\\ude02\":1,\"\\u00f6\":2,\"\\ue000\":3,\"a\":4,\"A\":5,\"\\u20ac\":6}",
  )
  assert_eq(
    @jcs.dumps(doc),
    "{\"A\":5,\"a\":4,\"\u{00f6}\":2,\"\u{20ac}\":6,\"\u{1f602}\":1,\"\u{e000}\":3}",
  )
}

///|
/// A number that is not finite has no canonical form; signing `null` in its
/// place would sign something the document does not say.
test "a non-finite number is refused" {
  let cases = [
    Json::number(@double.infinity),
    Json::number(@double.not_a_number),
  ]
  for value in cases {
    try @jcs.dumps(value) |> ignore catch {
      e => assert_true(e is Unwritable(_))
    } noraise {
      _ => fail("a number with no canonical form was written")
    }
  }
}

///|
/// `dump` is the same text as bytes, which is what a signature is taken over.
test "bytes and text agree" {
  let tree = @json.loads("{\"b\":1,\"a\":[true,null]}")
  assert_eq(@utf8.decode(@jcs.dump(tree)), @jcs.dumps(tree))
  assert_eq(@jcs.dumps(tree), "{\"a\":[true,null],\"b\":1}")
}
