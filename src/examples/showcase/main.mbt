// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The same document in every notation the showcase page shows, so the page's
/// bytes can be checked against the library:
///
///     moon run src/examples/showcase
#coverage.skip
fn main raise {
  let doc = @json.loads("{\"name\":\"John\",\"age\":30}")
  println("json   " + @json.dumps(doc))
  println("cbor   " + @base16.encode(@cbor.dump(doc)[:]))
  println("cbd    " + @base16.encode(@cbd.dump(doc)[:]))
  println("sqlite " + @base16.encode(@sqlite.dump(doc)[:]))
  println("pg     " + @base16.encode(@pg.dump(doc)[:]))
}
