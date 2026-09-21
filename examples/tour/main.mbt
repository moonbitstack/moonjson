// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The four dialects and the pointer, in one run.
///
///     moon run examples/tour
#coverage.skip
fn main raise {
  // One document, three ways of writing it. They read to the same tree.
  let plain = @json.parse(
    "{\"host\":\"localhost\",\"port\":8080,\"tls\":false}",
  )
  let source =
    #|{
    #|  "host": "localhost",  // where to bind
    #|  "port": 8080,
    #|  "tls": false,         // a certificate is not set up yet
    #|}
  let commented = @jsonc.parse(source[:])
  let loose = @json5.parse("{host:'localhost',port:8080,tls:false,}")
  println("jsonc == json -> \{commented == plain}")
  println("json5 == json -> \{loose == plain}")

  // Writing is always strict JSON, whatever the document was written in.
  println("compact       -> \{@json.write(plain)}")
  println("indented      -> \{@json.write(plain, indent=2)}")

  // A number keeps the digits it came with, so a document round-trips.
  let wide = "[1e400,12345678901234567890,0.1]"
  println("round trip    -> \{@json.write(@json.parse(wide)) == wide}")

  // JSON5 carries values JSON has no syntax for; they go out as null.
  println(
    "json5 extras  -> \{@json5.write(@json5.parse("[Infinity,NaN,0xFF]"))}",
  )

  // A stream of records, one to a line.
  let records = @lines.parse("{\"n\":1}\n{\"n\":2}\n{\"n\":3}\n")
  println("records       -> \{records.length()}")

  // One place in a document, named.
  let tree = @json.parse("{\"a\":{\"b\":[10,20,30]}}")
  println("pointer       -> \{@json.write(@pointer.get(tree, "/a/b/1"))}")
  println("missing       -> \{@pointer.has(tree, "/a/b/9")}")

  // A failure says where it happened.
  try @json.parse("{\n  \"a\": 1,\n  \"b\": ?\n}") |> ignore catch {
    e => {
      let spot = e.at()
      println("failure       -> line \{spot.line}, column \{spot.column}")
    }
  } noraise {
    _ => println("failure       -> none, which cannot happen")
  }
}
