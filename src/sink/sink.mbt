// Streaming JSON sink — newline-delimited JSON (NDJSON): https://github.com/ndjson/ndjson-spec
//
// A sink writes a sequence of documents one after another without holding the
// whole sequence as an array. Each document goes out in the compact form and is
// followed by a line feed, which is exactly the shape `@lines.loads_all` reads
// and the shape `@lines.dumps_all` writes — so a sequence written here is
// byte-for-byte the same as one written by the batch API.

///|
/// A sink that accumulates a sequence of JSON documents, one to a line.
///
/// The documents are buffered in memory; the value of the type is that it is
/// written one document at a time, so a caller that produces them lazily never
/// builds the whole array first.
pub struct Sink {
  /// The bytes written so far.
  buffer : StringBuilder
  /// How many documents have been written.
  mut count : Int32
}

///|
/// A new, empty sink.
pub fn Sink::new() -> Sink {
  { buffer: StringBuilder(), count: 0, }
}

///|
/// Write one document, in the compact form, followed by a line feed.
///
/// Every record ends in its own line feed, including the last, which is what
/// makes the output appendable — the format's whole purpose.
pub fn Sink::write(self : Sink, value : Json) -> Unit {
  self.buffer.write_string(@moonjson.dumps(value))
  self.buffer.write_char('\n')
  self.count += 1
}

///|
/// How many documents have been written.
pub fn Sink::length(self : Sink) -> Int32 {
  self.count
}

///|
/// Everything written so far, as text.
pub fn Sink::to_string(self : Sink) -> String {
  self.buffer.to_string()
}

///|
/// Everything written so far, as the UTF-8 bytes a body goes out as.
pub fn Sink::to_bytes(self : Sink) -> Bytes {
  @utf8.encode(self.buffer.to_string()[:])
}
