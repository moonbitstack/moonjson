# moonjson

The JSON family for MoonBit: one tree, several ways of writing it.

```moonbit
let config = @json.parse("{\"host\":\"localhost\",\"port\":8080}")
@json.write(config)              // {"host":"localhost","port":8080}
@json.write(config, indent=2)    // over several lines

// The same document, written the way a settings file is written.
@jsonc.parse("{\"port\": 8080,  // the one we bound\n}")

// One place in a document, named (RFC 6901).
@pointer.get(config, "/host")    // "localhost"
```

Run `moon run examples/tour` for the whole surface in one go.

## Packages

| Package | What | Specification |
|:--:|:--|:--|
| `json` | JSON, exactly | RFC 8259, ECMA-404 |
| `jsonc` | JSON with comments and trailing commas | what VS Code accepts |
| `json5` | JSON5: unquoted names, single quotes, hexadecimal, `Infinity` | spec.json5.org |
| `lines` | JSON Lines / NDJSON: one document to a line | jsonlines.org |
| `pointer` | JSON Pointer | RFC 6901 |
| `moonjson` | The scanner the dialects share, the writer, and `Flavor` | — |

Each has the same four faces — `parse`, `parse_bytes`, `write`, `write_bytes` —
so learning one is learning all of them. Writing is always strict JSON, whatever
the document was written in.

## Configuration

How to read is a value. `Flavor` carries both what syntax a dialect accepts and
what it does at the edges — how deep the nesting may go, what a lone surrogate
means, what a repeated member name means — and every reader takes one:

```moonbit
@json.parse(text)                                    // strict JSON
@jsonc.parse(text)                                   // the same, plus comments
@json.parse(text, flavor=@moonjson.Flavor::new(depth=100))
@json.parse(text, flavor={ ..@moonjson.strict, duplicates: Reject })
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
@json.write(value)                      // compact
@json.write(value, indent=2)            // over several lines
@json.write(value, ascii=true)          // escape everything above U+007E
@json.write(value, sort=true)           // members in order of name
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

## The tree

The data model is core's `Json`, not one of our own. Anything that already
speaks `@json.Json` speaks this, with no conversion.

A number keeps the text it was written as, so a document read and written again
comes back unchanged — including a twenty-digit integer and `1e400`, which a
double cannot hold and which a parser that goes through one silently rewrites.
A number JSON has no syntax for, which JSON5 can produce, is written as `null`,
as every JavaScript implementation writes it.

Members keep their order.

## Failures

Reading raises `Malformed`, which says what went wrong and where — offset, line
and column:

```moonbit
try @json.parse(source) catch {
  e => println("line \{e.at().line}, column \{e.at().column}")
}
```

Nesting is refused past 500 levels rather than taken to the stack: a document of
a hundred thousand open brackets is a denial of service, not a document.

A lone half of a surrogate pair is refused. It is not a character, it cannot be
written back out, and any value put in its place would be a guess.

## What is checked

The strict parser is measured against cases drawn from JSONTestSuite, with every
verdict taken from a third-party parser rather than asserted from memory — 95
documents that must be accepted or refused, and are. JSON5 is measured against
the document json5.org puts on its front page, and JSON Pointer against every
example RFC 6901 §5 prints.

## What is not here yet

Hjson and the other text dialects; CBOR, MessagePack, BSON and the other binary
encodings; PostgreSQL's and SQLite's `jsonb`; JSON Patch, JSONPath, JSON Schema
and canonical serialisation. They are planned in that order; the tracking list
lives with the project.

YAML and TOML are their own repositories. HOCON and HCL belong with
configuration, because their substitutions and merges are evaluation, not syntax.

## Install

```bash
moon add moonbitstack/moonjson
```

## Licence

Apache-2.0.
