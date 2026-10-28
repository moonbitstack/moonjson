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
  println("cbor   " + @hex.encode(@cbor.dump(doc)[:]))
  println("cbd    " + @hex.encode(@cbd.dump(doc)[:]))
  println("sqlite " + @hex.encode(@sqlite.dump(doc)[:]))
  println("pg     " + @hex.encode(@pg.dump(doc)[:]))
}
