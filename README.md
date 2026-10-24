# moonjson

The JSON family for MoonBit: one tree, several ways of writing it.

```moonbit
let config = @json.loads("{\"host\":\"localhost\",\"port\":8080}")
@json.dumps(config)              // {"host":"localhost","port":8080}
@json.dumps(config, indent=2)    // over several lines

// The same document, written the way a settings file is written.
@jsonc.loads("{\"port\": 8080,  // the one we bound\n}")

// One place in a document, named (RFC 6901).
@pointer.get(config, "/host")    // "localhost"
```

Run `moon run examples/tour` for the whole surface in one go.

## The surface

One set of verbs, the ones Python's `json`, PyYAML and `tomllib` share:

|  | text → tree | bytes → tree | tree → text | tree → bytes |
|:--:|:--:|:--:|:--:|:--:|
| one document | `loads` | `load` | `dumps` | `dump` |
| a stream of them | `loads_all` | `load_all` | `dumps_all` | `dump_all` |

The `s` is on the form that takes or answers a string, as it is in Python. The
plural set exists **exactly where the format defines a stream** — `lines` is a
stream and has only those; `json`, `jsonc` and `json5` define one document and
have only the singular set. `moonyaml` follows the same rule and has both,
because `---` makes both meaningful.

Not `from_str` and `to_string`: `to_string` already means `Show::to_string` in
MoonBit, and `@json.to_string(x)` beside `x.to_string()` is a sentence that
reads two ways.

```moonbit
// Read a document, change one field, write it back.
let cfg = @jsonc.loads(text[:])
let cfg = @pointer.set(cfg, "/spec/replicas", Json::number(5))
@json.dumps(cfg, indent=2)
```

## Packages

| Package | What | Specification |
|:--:|:--|:--|
| `json` | JSON, exactly | RFC 8259, ECMA-404 |
| `jsonc` | JSON with comments and trailing commas | what VS Code accepts |
| `json5` | JSON5: unquoted names, single quotes, hexadecimal, `Infinity` | spec.json5.org |
| `lines` | JSON Lines / NDJSON: one document to a line | jsonlines.org |
| `pointer` | JSON Pointer | RFC 6901 |
| `patch` | JSON Patch: add, remove, replace, move, copy, test | RFC 6902 |
| `merge` | JSON Merge Patch | RFC 7396 |
| `path` | JSONPath: a query language over the tree, filters and all | RFC 9535 |
| `jcs` | Canonical JSON: one document, one sequence of bytes | RFC 8785 |
| `cbor` | CBOR, the binary encoding JSON's own working group wrote | RFC 8949 |
| `msgpack` | MessagePack | msgpack.org |
| `bson` | BSON, what MongoDB stores and sends | bsonspec.org |
| `moonjson` | The scanner the dialects share, the writer, and `Refused` | — |

Each text dialect has the same four faces — `loads`, `load`, `dumps`, `dump` —
so learning one is learning all of them. Writing is always strict JSON, whatever
the document was written in. A binary format has the two that take bytes: `load`
and `dump`.

`merge` is the one without them: a merge patch has no syntax of its own — the
patch document is a JSON document, read with `@json.loads` — so the package
holds the evaluation and nothing else.

## One tree, every notation

A document read from JSON5 can be written as CBOR, read back from CBOR, and
written as JSON again, because all of them read into the same tree. That is the
whole design: the formats are notations, and `Json` is what they all say.

Four things JSON has no syntax for are carried in markers, so that a value that
came from BSON or CBOR survives a trip through JSON:

| Value | Marker |
|:--|:--|
| a byte string | `{"$bytes": "0102"}` — lowercase hex, no separators |
| a tag or an extension type | `{"$tag": 1, "value": …}`, `{"$ext": 1, "data": "0102"}` |
| `undefined` | `{"$undefined": true}` |
| a map whose keys are not strings | `{"$map": [[1, 2]]}` |

BSON's own types have markers of their own — `{"$oid": …}`, `{"$date": …}`,
`{"$decimal128": …}` and the rest — because a date is not a number and an
ObjectId is not a string. Writing reads the same markers back, so nothing is
lost in either direction. A marker name is reserved: an object whose only member
is `$oid` is an ObjectId, not a document that happens to have that member.

```moonbit
let doc = @json5.loads("{host:'localhost',port:8080,tls:false}")
let body = @cbor.dump(doc)                    // the same tree, as bytes
let doc = @cbor.load(body)                    // and back
@json.dumps(doc)                              // {"host":"localhost","port":8080,"tls":false}
```

## Configuration

How to read is a value. `Flavor` carries both what syntax a dialect accepts and
what it does at the edges — how deep the nesting may go, what a lone surrogate
means, what a repeated member name means — and every reader takes one:

```moonbit
@json.loads(text)                                    // strict JSON
@jsonc.loads(text)                                   // the same, plus comments
@json.loads(text, flavor=@moonjson.Flavor::new(depth=100))
@json.loads(text, flavor={ ..@moonjson.strict, duplicates: Reject })
```

Two layers, the later overriding the earlier: **the dialect's preset < the
`flavor` you pass**. The two ways of building one — the constructor and the
record update — are the same thing, and a test asserts it.

There are no per-call mirrors of the individual settings here, and the reason is
the arithmetic: four dialects times four entry points is sixteen signatures, and
a setting mirrored into all of them costs sixteen lines every time one is added.
A dialect is chosen per use site rather than per call, so the record is where it
belongs. Writing is the other way round, so its three settings are arguments:

```moonbit
@json.dumps(value)                      // compact
@json.dumps(value, indent=2)            // over several lines
@json.dumps(value, ascii=true)          // escape everything above U+007E
@json.dumps(value, sort=true)           // members in order of name
```

### The defaults, and where they come from

| Setting | Default | Why that one |
|:--:|:--:|:--|
| `depth` | 500 | Everyone bounds it and nobody agrees on the number — Jackson refuses past 1000, serde_json past 128. A hundred thousand open brackets is a denial of service, not a document |
| `surrogates` | refuse | Implementations disagree and JSONTestSuite files these cases as implementation-defined, so the safer side is the default: a lone half cannot be written back out |
| `duplicates` | `Last` | JavaScript, Python, Go and serde all keep the last one |
| `bom` | skipped | RFC 8259 §8.1 forbids writing one and says nothing about reading one; refusing would reject half of what Windows tooling produces |
| `ascii` | off | A UTF-8 body is the normal case now. Python's `ensure_ascii` defaults the other way because it predates that |
| `sort` | off | The order a document was written in is information; a diff is the reason to discard it, and a diff can ask |
| CBOR `deterministic` | on | RFC 8949 §4.2 recommends it, and a hash or a signature over an encoding needs it. Off still writes valid CBOR, only longer |
| CBOR `depth` | 500 | The same as the text reader, for the same reason |
| MessagePack `floats` | `Double` | Python's `msgpack`, the reference implementation, writes doubles unless it is told otherwise |
| BSON `depth` | 500 | Documents nest inside documents exactly as brackets nest inside brackets |

## The tree

The data model is core's `Json`, not one of our own. Anything that already
speaks `@json.Json` speaks this, with no conversion.

A number keeps the text it was written as, so a document read and written again
comes back unchanged — including a twenty-digit integer and `1e400`, which a
double cannot hold and which a parser that goes through one silently rewrites.
A number JSON has no syntax for, which JSON5 can produce, is written as `null`,
as every JavaScript implementation writes it.

Members keep their order.

## Changing a document

Three ways, for three kinds of change. One place is named with a pointer
(RFC 6901); a set of changes that must all hold or none is a patch (RFC 6902);
and a change that looks like the document itself is a merge patch (RFC 7396).

```moonbit
// One field, and nothing else changes.
let cfg = @pointer.set(cfg, "/spec/replicas", Json::number(5))

// Six operations, applied in order — or, if one fails, not at all.
let ops = @patch.loads(
  "[{\"op\":\"test\",\"path\":\"/spec/replicas\",\"value\":1},{\"op\":\"replace\",\"path\":\"/spec/replicas\",\"value\":5}]"
)
@patch.apply(cfg, ops)

// A patch that looks like the document: a member that is not there is added,
// one that is there is replaced, and a null takes one away.
@merge.merge(cfg, @json.loads("{\"spec\":{\"replicas\":5,\"image\":null}}"))
```

A patch is read into `Operation`s rather than left as a tree of objects, so a
misspelled `op` is an error rather than a document that quietly does nothing,
and the pointers inside it are the same ones `@pointer` reads.

## Failures

Reading raises `Refused`, which says what went wrong and where — offset, line
and column:

```moonbit
try @json.loads(source) catch {
  e => match e.at() {
    Some(spot) => println("line \{spot.line}, column \{spot.column}")
    None => println(e)          // a pointer or a patch, which has a path instead
  }
}
```

One type for the whole family, so there is one thing to catch: the scanner's
refusals, the pointer's `Missing` and `BadIndex`, the patch's `TestFailed` and
`IntoChild`, and `Unwritable` for a value a writer cannot put on paper. A
failure in a binary format answers `None` from `at()` and carries a byte offset
in its variant instead, because a line number invented for a byte string would
be worse than none.

Nesting is refused past 500 levels rather than taken to the stack: a document of
a hundred thousand open brackets is a denial of service, not a document.

A lone half of a surrogate pair is refused. It is not a character, it cannot be
written back out, and any value put in its place would be a guess.

## What is checked

Each package is measured against the document that defines it, not against
itself:

| Package | Criterion |
|:--|:--|
| `json` | JSONTestSuite, ninety-five cases whose verdicts come from a third-party parser |
| `json5` | the document json5.org puts on its front page |
| `pointer` | every example RFC 6901 §5 prints |
| `patch` | every example RFC 6902 Appendix A prints, plus the error cases §5 names |
| `merge` | every case RFC 7396 Appendix A prints |
| `jcs` | the six published vectors of RFC 8785, byte for byte |
| `cbor` | RFC 8949 Appendix A, read and written back byte for byte |
| `msgpack` | the examples the MessagePack specification prints for each format |
| `bson` | the two documents bsonspec.org prints, byte for byte |
| `path` | RFC 9535 table 12, every query and every answer |

Where a case is implementation-defined — a lone surrogate, a number too large
for a double — the choice is written down above rather than left to be
discovered.

## What is not here yet

PostgreSQL's and SQLite's `jsonb` — two incompatible binary layouts that each
need their own package; Hjson, CSON, SuperJSON, NTV, UBJSON and Smile; and the
streaming `Sink`/`Source` that moonbase uses. JSONTestSuite is run over the
cases it was run over when this was written, not the whole corpus, and the
JSONPath compliance suite is next: the RFC's own table passes, the suite's
hundreds of cases have not been run yet. JSON Schema is `moonschema`'s.

Each of these is a package of its own when it lands, because each is a notation
and none of them changes the tree.

YAML and TOML are their own repositories. HOCON and HCL belong with
configuration, because their substitutions and merges are evaluation, not syntax.

## Install

```bash
moon add moonbitstack/moonjson
```

## Licence

Apache-2.0.
