// Streaming JSON source — newline-delimited JSON (NDJSON): https://github.com/ndjson/ndjson-spec
//
// A source reads a sequence of documents one at a time from a buffer, without
// parsing the whole stream into an array up front. It reads a line, parses that
// line, and hands back one value; the next call continues where the last left
// off. A blank line is skipped rather than refused, and a carriage return before
// the line feed is tolerated, so a file written on Windows reads here.

///|
/// A source that hands back a sequence of JSON documents, one at a time.
pub struct Source {
  /// The stream as decoded text.
  text : StringView
  /// How far into the stream the reader has come.
  mut offset : Int32
  /// How many documents have been read.
  mut count : Int32
}

///|
/// A source over the UTF-8 bytes of a stream.
///
/// A leading byte-order mark is skipped. Bytes that are not UTF-8 are a
/// `BadUtf8` refusal at the start of the stream.
pub fn Source::new(input : BytesView) -> Source raise @moonjson.Refused {
  let text = @utf8.decode(input, ignore_bom=true) catch {
    _ => raise @moonjson.BadUtf8({ at: 0, line: 1, column: 1, })
  }
  { text: text[:], offset: 0, count: 0, }
}

///|
/// The next document, or `None` once the stream is exhausted.
///
/// A blank line is skipped. A line that is not a value is refused with the
/// position of the failure in that line.
pub fn Source::read(self : Source) -> Json? raise @moonjson.Refused {
  while self.offset <= self.text.length() {
    if self.offset == self.text.length() {
      return None
    }
    let mut end = self.offset
    while end < self.text.length() && self.text.at(end).to_int() != 0x0A {
      end += 1
    }
    let mut line_end = end
    if line_end > self.offset && self.text.at(line_end - 1).to_int() == 0x0D {
      line_end -= 1
    }
    let line = self.text[self.offset:line_end]
    self.offset = end + 1
    if !line.is_blank() {
      self.count += 1
      return Some(@moonjson.loads(line, @moonjson.strict))
    }
  }
  None
}

///|
/// How many documents have been read so far.
pub fn Source::length(self : Source) -> Int32 {
  self.count
}

///|
/// Whether the stream has been fully read.
pub fn Source::is_done(self : Source) -> Bool {
  self.offset >= self.text.length()
}
