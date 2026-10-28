// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The four dialects and the pointer, in one run.
///
///     moon run src/examples/tour
#coverage.skip
fn main raise {
  // One document, three ways of writing it. They read to the same tree.
  let plain = @json.loads(
    "{\"host\":\"localhost\",\"port\":8080,\"tls\":false}",
  )
  let source =
    #|{
    #|  "host": "localhost",  // where to bind
    #|  "port": 8080,
    #|  "tls": false,         // a certificate is not set up yet
    #|}
  let commented = @jsonc.loads(source[:])
  let loose = @json5.loads("{host:'localhost',port:8080,tls:false,}")
  println("jsonc == json -> \{commented == plain}")
  println("json5 == json -> \{loose == plain}")

  // Writing is always strict JSON, whatever the document was written in.
  println("compact       -> \{@json.dumps(plain)}")
  println("indented      -> \{@json.dumps(plain, indent=2)}")

  // A number keeps the digits it came with, so a document round-trips.
  let wide = "[1e400,12345678901234567890,0.1]"
  println("round trip    -> \{@json.dumps(@json.loads(wide)) == wide}")

  // JSON5 carries values JSON has no syntax for; they go out as null.
  println(
    "json5 extras  -> \{@json5.dumps(@json5.loads("[Infinity,NaN,0xFF]"))}",
  )

  // A stream of records, one to a line.
  let records = @lines.loads_all("{\"n\":1}\n{\"n\":2}\n{\"n\":3}\n")
  println("records       -> \{records.length()}")

  // One place in a document, named.
  let tree = @json.loads("{\"a\":{\"b\":[10,20,30]}}")
  println("pointer       -> \{@json.dumps(@pointer.get(tree, "/a/b/1"))}")
  println("missing       -> \{@pointer.has(tree, "/a/b/9")}")

  // A patch is a list of operations, applied in order or not at all.
  let ops = @patch.loads(
    "[{\"op\":\"replace\",\"path\":\"/port\",\"value\":9090},{\"op\":\"add\",\"path\":\"/tls\",\"value\":true}]",
  )
  println("patch         -> \{@json.dumps(@patch.apply(plain, ops))}")

  // A merge patch looks like the document: a member that is not there is
  // added, one that is there is replaced, and a null takes one away.
  let patch_text = "{\"port\":9090,\"tls\":null}"
  println(
    "merge         -> \{@json.dumps(@merge.merge(plain, @json.loads(patch_text)))}",
  )

  // A query rather than a pointer: every book under ten, wherever it is.
  let shelf = @json.loads(
    "{\"store\":{\"book\":[{\"title\":\"A\",\"price\":8.95},{\"title\":\"B\",\"price\":12.99},{\"title\":\"C\",\"price\":8.99}]}}",
  )
  let cheap = @path.select(shelf, "$..book[?@.price<10].title")
  println("jsonpath      -> \{@json.dumps(Json::array(cheap))}")

  // The same tree as bytes, and back. Nothing about the document changed with
  // the notation.
  let body = @cbor.dump(plain)
  println("cbor          -> \{@hex.encode(body[:])}")
  println("cbor == json  -> \{@cbor.load(body[:]) == plain}")

  // One document, one sequence of bytes — what a signature is taken over.
  println("canonical     -> \{@jcs.dumps(plain)}")

  // A lenient dialect reads what JSON would refuse; a compact binary one
  // carries the same tree in fewer bytes. Both come back to the same tree.
  let loose2 = @hjson.loads("{ host: localhost, port: 8080, tls: false }")
  println("hjson == json -> \{loose2 == plain}")
  let packed = @cbd.dump(plain)
  println("cbd == json   -> \{@cbd.load(packed[:]) == plain}")

  // A stream of records, written one at a time.
  let sink = @sink.Sink::new()
  sink.write(plain)
  sink.write(plain)
  println("sink records  -> \{sink.length()}")

  // The same stream read back, one at a time.
  let src = @source.Source::new(sink.to_bytes()[:])
  match src.read() {
    Some(one) => println("source first  -> \{@json.dumps(one)}")
    None => println("source first  -> none")
  }

  // A formatter rather than a dialect: four spaces a level, names sorted.
  println(
    "pretty        -> \{@pretty.format(plain, style=@pretty.Format::new(indent=4, sort=true))}",
  )

  // A failure says where it happened.
  try @json.loads("{\n  \"a\": 1,\n  \"b\": ?\n}") |> ignore catch {
    e => {
      let spot = e.at().unwrap()
      println("failure       -> line \{spot.line}, column \{spot.column}")
    }
  } noraise {
    _ => println("failure       -> none, which cannot happen")
  }
}
