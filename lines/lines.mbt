// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read a stream of documents, one to a line.
///
/// A blank line is skipped rather than refused: files grown by appending end up
/// with one, and refusing it would make a reader fail on its own writer's
/// output. A carriage return before the line feed is also tolerated, because
/// half the tools that produce these files run on Windows.
pub fn loads_all(
  input : StringView,
  flavor? : @moonjson.Flavor = @moonjson.strict,
) -> Array[Json] raise @moonjson.Malformed {
  let out : Array[Json] = []
  let mut start = 0
  let mut i = 0
  while i <= input.length() {
    let done = i == input.length()
    if done || input.at(i).to_int() == 0x0A {
      let mut end = i
      if end > start && input.at(end - 1).to_int() == 0x0D {
        end -= 1
      }
      let line = input[start:end]
      if !line.is_blank() {
        out.push(@moonjson.loads(line, flavor))
      }
      start = i + 1
    }
    i += 1
  }
  out
}

///|
/// The same, from bytes.
pub fn load_all(
  input : BytesView,
  flavor? : @moonjson.Flavor = @moonjson.strict,
  bom? : Bool = true,
) -> Array[Json] raise @moonjson.Malformed {
  let text = @utf8.decode(input, ignore_bom=bom) catch {
    _ => raise @moonjson.BadUtf8({ at: 0, line: 1, column: 1, })
  }
  loads_all(text[:], flavor~)
}

///|
/// Write documents one to a line, each ending in a line feed.
///
/// Every line ends in one, including the last: a file that ends without it
/// cannot be appended to safely, which is the format's whole purpose.
pub fn dumps_all(
  values : ArrayView[Json],
  ascii? : Bool = false,
  sort? : Bool = false,
) -> String {
  let out = StringBuilder()
  for value in values {
    out.write_string(@moonjson.dumps(value, ascii~, sort~))
    out.write_char('\n')
  }
  out.to_string()
}

///|
/// The same, as UTF-8 bytes.
pub fn dump_all(
  values : ArrayView[Json],
  ascii? : Bool = false,
  sort? : Bool = false,
) -> Bytes {
  @utf8.encode(dumps_all(values, ascii~, sort~)[:])
}
