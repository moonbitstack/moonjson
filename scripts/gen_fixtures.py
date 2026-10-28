#!/usr/bin/env python3
"""Regenerate the test vectors that come from somebody else's repository.

The tests hold their vectors as MoonBit literals, because a test that reads a
file cannot run on wasm and js. This script is how those literals are made: it
takes the reference corpora, and writes the table back into the test file
between two markers, so regenerating is a diff of the vectors rather than of the
whole file.

Nothing here runs in CI — it is a maintainer's tool, and it needs the corpora
and, for the binary vectors, three reference implementations:

    pip install cbor2 msgpack pymongo json5

The corpora are not in the repository either; `.ref/` is ignored, and this
script fetches what it needs.

    python scripts/gen_fixtures.py jcs
    python scripts/gen_fixtures.py json-testsuite
    python scripts/gen_fixtures.py jsonpath
    python scripts/gen_fixtures.py json5
    python scripts/gen_fixtures.py binary

The formats whose vectors are printed in a specification (CBOR's appendix A,
MessagePack's format table, BSON's two documents) are transcribed by hand into
their test files, because the specification is prose and HTML and a parser for
it would be more code than the vectors are worth. What this script adds for the
three binary formats is a different thing: values chosen at random, encoded by
a reference implementation, so that the same value has one encoding and not
merely one meaning.
"""

import json
import math
import os
import random
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, ".ref")

CORPORA = {
    "jcs": (
        "cyberphone/json-canonicalization",
        "master",
        "testdata",
    ),
    "json-testsuite": ("nst/JSONTestSuite", "master", "test_parsing"),
    "json-patch": ("json-patch/json-patch-tests", "master", ""),
    "jsonpath": (
        "jsonpath-standard/jsonpath-compliance-test-suite",
        "main",
        "",
    ),
    "json5": ("json5/json5-tests", "master", ""),
}


def fetch(name):
    """Clone a corpus into `.ref/`, if it is not there already."""
    repo, branch, _ = CORPORA[name]
    target = os.path.join(REF, os.path.basename(repo) + "-" + branch)
    if os.path.isdir(target):
        return target
    os.makedirs(REF, exist_ok=True)
    archive = os.path.join(REF, name + ".tar.gz")
    url = f"https://codeload.github.com/{repo}/tar.gz/refs/heads/{branch}"
    subprocess.run(["curl", "-fsSL", "-m", "180", "-o", archive, url], check=True)
    subprocess.run(["tar", "xzf", archive, "-C", REF], check=True)
    os.remove(archive)
    return target


def moonbit_literal(text):
    """A MoonBit string literal: the escapes MoonBit reads, and no raw control
    characters — a source file is text, and a NUL in it is not."""
    out = []
    for ch in text:
        code = ord(ch)
        if ch == '"':
            out.append('\\"')
        elif ch == "\\":
            out.append("\\\\")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif code < 0x20 or 0x7E < code < 0xA0 or code > 0xFFFF:
            out.append("\\u{%04x}" % code)
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def replace_between(path, begin, end, body):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    start = text.index(begin) + len(begin)
    # The closing bracket is a line of its own, which is what keeps a `]` inside
    # a vector from being taken for the end of the table.
    stop = text.index(end, start)
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text[:start] + "\n" + body + "\n" + text[stop:])


def jcs(root):
    """RFC 8785's reference vectors: an input document and the one line it must
    canonicalise to."""
    base = os.path.join(root, "testdata")
    rows = []
    for name in sorted(os.listdir(os.path.join(base, "input"))):
        if not name.endswith(".json"):
            continue
        stem = name[: -len(".json")]
        with open(os.path.join(base, "input", name), encoding="utf-8") as handle:
            source = handle.read()
        with open(os.path.join(base, "output", name), encoding="utf-8") as handle:
            canonical = handle.read()
        rows.append(
            "  // %s.json from the reference vectors RFC 8785 points at.\n"
            "  (\n    %s,\n    %s,\n  ),"
            % (stem, moonbit_literal(source), moonbit_literal(canonical))
        )
    replace_between(
        os.path.join(ROOT, "src", "jcs", "jcs_test.mbt"),
        "let vectors : Array[(String, String)] = [",
        "\n]\n",
        "\n".join(rows),
    )
    print("jcs: %d vectors" % len(rows))


def moonbit_expr(text, limit=512):
    """A literal, split into pieces when it is long.

    A source line has a column limit and the compiler says so; a hundred
    thousand open brackets are one test vector and one line would be a warning.
    The pieces are joined at compile time, so the value is the same string."""
    if len(text) <= limit:
        return moonbit_literal(text)
    parts = [moonbit_literal(text[i : i + limit]) for i in range(0, len(text), limit)]
    return " +\n      ".join(parts)


def hexed(data):
    return data.hex()


# A JSONTestSuite file whose name starts with `i_` may be either accepted or
# refused. These are the choices this family makes, and the test file repeats
# them in prose:
#
#   - a number too large or too small for a double is accepted, because the
#     tree keeps the text it was written as and a document that came in must go
#     back out unchanged (RFC 8259 §6 leaves the magnitude open);
#   - five hundred levels of nesting are accepted, because that is the limit
#     `Flavor::depth` names, and the file is exactly five hundred deep;
#   - a byte-order mark is skipped, so the BOM file is accepted;
#   - a lone surrogate, a UTF-16 document read as UTF-8, and bytes that are not
#     UTF-8 are refused, because `surrogates` is off by default and a text
#     reader has no business guessing an encoding.
def i_verdict(stem):
    if stem.startswith("i_number_"):
        return True
    if stem in ("i_structure_500_nested_arrays", "i_structure_UTF-8_BOM_empty_object"):
        return True
    return False


def json_testsuite(root):
    """Every file of `test_parsing`, and every file of `test_transform`.

    A parsing case is a file and a verdict; a transform case is a file that is
    read, written and read again, so it is only a file."""
    parsing = os.path.join(root, "test_parsing")
    rows = []
    counts = {"y": 0, "n": 0, "i": 0}
    for name in sorted(os.listdir(parsing)):
        if not name.endswith(".json"):
            continue
        stem = name[: -len(".json")]
        kind = stem[0]
        with open(os.path.join(parsing, name), "rb") as handle:
            data = handle.read()
        if kind == "y":
            verdict = True
        elif kind == "n":
            verdict = False
        else:
            verdict = i_verdict(stem)
        counts[kind] += 1
        note = "" if kind != "i" else "  // implementation-defined: %s\n" % (
            "accepted" if verdict else "refused"
        )
        rows.append(
            "%s  (%s, %s, %s),"
            % (note, moonbit_literal(stem), moonbit_expr(hexed(data)),
               "true" if verdict else "false")
        )
    replace_between(
        os.path.join(ROOT, "src", "json", "testsuite_test.mbt"),
        "let parsing : Array[(String, String, Bool)] = [",
        "\n]\n",
        "\n".join(rows),
    )

    transform = os.path.join(root, "test_transform")
    rows = []
    for name in sorted(os.listdir(transform)):
        if not name.endswith(".json"):
            continue
        stem = name[: -len(".json")]
        with open(os.path.join(transform, name), "rb") as handle:
            data = handle.read()
        rows.append(
            "  (%s, %s)," % (moonbit_literal(stem), moonbit_expr(hexed(data)))
        )
    replace_between(
        os.path.join(ROOT, "src", "json", "testsuite_test.mbt"),
        "let transforming : Array[(String, String)] = [",
        "\n]\n",
        "\n".join(rows),
    )
    print(
        "json-testsuite: %d parsing (%d y_, %d n_, %d i_), %d transform"
        % (sum(counts.values()), counts["y"], counts["n"], counts["i"], len(rows))
    )


def jsonpath(root):
    """RFC 9535's compliance suite: a selector, a document, and the nodelist it
    must answer — or the word that the selector is not one.

    A test with `results` instead of `result` allows any of several nodelists,
    because the order of a descendant segment over an object is not fixed by the
    RFC; those are written as every allowed answer, and any one of them passes.
    """
    with open(os.path.join(root, "cts.json"), encoding="utf-8") as handle:
        suite = json.load(handle)
    rows = []
    for case in suite["tests"]:
        name = case["name"]
        selector = case["selector"]
        if case.get("invalid_selector"):
            rows.append(
                "  (%s, %s, \"\", \"\"),"
                % (moonbit_literal(name), moonbit_literal(selector))
            )
            continue
        document = json.dumps(case["document"], ensure_ascii=False, separators=(",", ":"))
        if "result" in case:
            answers = [case["result"]]
        else:
            answers = case["results"]
        expected = json.dumps(answers, ensure_ascii=False, separators=(",", ":"))
        rows.append(
            "  (%s, %s, %s, %s),"
            % (
                moonbit_literal(name),
                moonbit_literal(selector),
                moonbit_literal(document),
                moonbit_literal(expected),
            )
        )
    replace_between(
        os.path.join(ROOT, "src", "path", "cts_test.mbt"),
        "let compliance : Array[(String, String, String, String)] = [",
        "\n]\n",
        "\n".join(rows),
    )
    print("jsonpath: %d cases" % len(rows))


def emit_value(value):
    """A JSON text this family's reader also accepts, so that an expected value
    is written the way a document would be. `NaN` and the infinities are written
    as the words JSON5 uses, and a negative zero keeps its sign — those three
    are the whole reason this is not `json.dumps`."""
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if math.isnan(value):
            return "NaN"
        if math.isinf(value):
            return "Infinity" if value > 0 else "-Infinity"
        if value == 0.0 and math.copysign(1.0, value) < 0:
            return "-0"
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "[" + ",".join(emit_value(item) for item in value) + "]"
    if isinstance(value, dict):
        return (
            "{"
            + ",".join(
                json.dumps(str(key), ensure_ascii=False) + ":" + emit_value(held)
                for key, held in value.items()
            )
            + "}"
        )
    raise TypeError(type(value))


def js_expectations(cases):
    """What the reference implementation holds for each case.

    The corpus is tested in JavaScript — `.json` through `JSON.parse` and
    `.json5` through `eval`, which is what "valid ES5" in its README means — and
    JavaScript is the only reference that can answer `-0`: Python's `json` reads
    `-0` as the integer zero and loses the sign, and a test that cannot tell a
    negative zero from a zero is not testing what the corpus asks.
    """
    script = r"""
const fs = require("fs");
const cases = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
function emit(value) {
  if (value === null) return "null";
  if (value === true) return "true";
  if (value === false) return "false";
  if (typeof value === "number") {
    if (Number.isNaN(value)) return "NaN";
    if (!Number.isFinite(value)) return value > 0 ? "Infinity" : "-Infinity";
    if (Object.is(value, -0)) return "-0";
    return JSON.stringify(value);
  }
  if (typeof value === "string") return JSON.stringify(value);
  if (Array.isArray(value)) return "[" + value.map(emit).join(",") + "]";
  return (
    "{" +
    Object.keys(value)
      .map((key) => JSON.stringify(key) + ":" + emit(value[key]))
      .join(",") +
    "}"
  );
}
const out = cases.map((item) => {
  try {
    let value;
    if (item.kind === "json") {
      try {
        value = JSON.parse(item.source);
      } catch (error) {
        // A `.json` file is one that JSON must accept, and this one is not:
        // `{/**/}` is JSON5 with a comment where JSON has none. The corpus
        // keeps it here anyway, so it is read the other way.
        value = eval("(\n" + item.source + "\n)");
      }
    } else {
      value = eval("(\n" + item.source + "\n)");
    }
    return { value: emit(value) };
  } catch (error) {
    return { error: String(error && error.message) };
  }
});
process.stdout.write(JSON.stringify(out));
"""
    import tempfile

    with tempfile.TemporaryDirectory() as scratch:
        payload = os.path.join(scratch, "cases.json")
        runner = os.path.join(scratch, "emit.js")
        with open(payload, "w", encoding="utf-8") as handle:
            json.dump(cases, handle)
        with open(runner, "w", encoding="utf-8") as handle:
            handle.write(script)
        done = subprocess.run(
            ["node", runner, payload], check=True, capture_output=True, text=True
        )
    return json.loads(done.stdout)


def json5(root):
    """The official JSON5 cases.

    The extension says what the file is for: `.json` and `.json5` must be read
    and hold the value the reference implementation holds, `.js` is valid ES5
    that JSON5 refuses, and `.txt` is not valid ES5 either. A `.errorSpec` is
    not a case at all — it is the error the reference implementation raised for
    the `.txt` beside it, position and message, and reading one as a document
    would be reading the expectation as the input.
    """
    cases = []
    rows = []
    for base, _, names in os.walk(root):
        for name in sorted(names):
            stem, ext = os.path.splitext(name)
            if ext not in (".json", ".json5", ".js", ".txt"):
                continue
            path = os.path.join(base, name)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            with open(path, encoding="utf-8", newline="") as handle:
                source = handle.read()
            cases.append({
                "name": rel,
                "source": source,
                "kind": "json" if ext == ".json" else "json5",
                "valid": ext in (".json", ".json5"),
            })

    read = [case for case in cases if case["valid"]]
    answers = js_expectations([{"source": case["source"], "kind": case["kind"]}
                               for case in read])
    expected = {}
    for case, answer in zip(read, answers):
        if "error" in answer:
            raise SystemExit(
                "%s is valid JSON5 but the reference refused it: %s"
                % (case["name"], answer["error"])
            )
        expected[case["name"]] = answer["value"]

    for case in cases:
        if case["valid"]:
            rows.append(
                "  (%s, %s, %s, true),"
                % (moonbit_literal(case["name"]), moonbit_expr(case["source"]),
                   moonbit_expr(expected[case["name"]]))
            )
        else:
            rows.append(
                "  (%s, %s, \"\", false),"
                % (moonbit_literal(case["name"]), moonbit_expr(case["source"]))
            )
    replace_between(
        os.path.join(ROOT, "src", "json5", "official_test.mbt"),
        "let official : Array[(String, String, String, Bool)] = [",
        "\n]\n",
        "\n".join(rows),
    )
    print("json5: %d cases (%d read, %d refused)" % (len(rows), len(read), len(cases) - len(read)))


# The random values the binary vectors are made of. Only the part of the tree
# every three formats can carry without a marker: null, booleans, strings,
# numbers and the two containers. Integers stay inside the range BSON's `int32`
# and `int64` cover, and one in five is negative, so the widths are exercised.
def random_value(rng, depth=0):
    kinds = ["null", "bool", "int", "float", "string"]
    if depth < 3:
        kinds += ["array", "object"]
    kind = rng.choice(kinds)
    if kind == "null":
        return None
    if kind == "bool":
        return rng.choice([True, False])
    if kind == "int":
        width = rng.choice([7, 15, 31, 53, 62])
        magnitude = rng.getrandbits(width)
        return -magnitude if rng.random() < 0.2 else magnitude
    if kind == "float":
        while True:
            value = rng.uniform(-1e6, 1e6) * (10 ** rng.randint(-12, 12))
            if value == value and value not in (float("inf"), float("-inf")):
                return value
    if kind == "string":
        alphabet = "abcXYZ 0123-_/.éß☺中😀\u0000\u001f\"\\\n\t"
        return "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 12)))
    if kind == "array":
        return [random_value(rng, depth + 1) for _ in range(rng.randint(0, 4))]
    keys = ["a", "b", "id", "name", "值", "", "x y"]
    rng.shuffle(keys)
    return {key: random_value(rng, depth + 1) for key in keys[: rng.randint(0, 4)]}


# The general categories, in the order the table in `src/path/category.mbt`
# uses. `Cn` is "unassigned", which is what a code point outside every range is;
# `Cs` never appears in a MoonBit string, because a surrogate is half of a
# character rather than one.
CATEGORIES = [
    "Lu", "Ll", "Lt", "Lm", "Lo",
    "Mn", "Mc", "Me",
    "Nd", "Nl", "No",
    "Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po",
    "Sm", "Sc", "Sk", "So",
    "Zs", "Zl", "Zp",
    "Cc", "Cf", "Co", "Cs", "Cn",
]


def categories():
    r"""The Unicode general categories, as ranges, for I-Regexp's `\p{...}`.

    RFC 9485 requires full support for the Unicode property set, and the
    alternative to a table is a regular expression engine that answers `\p{Lu}`
    by guessing. The data is Python's `unicodedata`, which is the Unicode
    Character Database; the file it writes is part of the library rather than a
    test, because a pattern is checked against it at run time.
    """
    import unicodedata

    index = {name: i for i, name in enumerate(CATEGORIES)}
    rows = []
    start = None
    previous = None
    current = None
    for cp in range(0x110000):
        name = unicodedata.category(chr(cp))
        if name in ("Cn", "Cs"):
            name = "Cn"
        if name != current or (previous is not None and cp != previous + 1):
            if current is not None and current != "Cn":
                rows.append((start, previous, index[current]))
            start = cp
            current = name
        previous = cp
    if current is not None and current != "Cn":
        rows.append((start, previous, index[current]))

    body = "\n".join(
        "  (0x%04x, 0x%04x, %d)," % (low, high, cat)
        for low, high, cat in rows
    )
    path = os.path.join(ROOT, "src", "path", "category.mbt")
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    start_at = text.index("let ranges : Array[(Int32, Int32, Int32)] = [")
    begin = start_at + len("let ranges : Array[(Int32, Int32, Int32)] = [")
    stop = text.index("\n]\n", begin)
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text[:begin] + "\n" + body + "\n" + text[stop:])
    print("categories: %d ranges, Unicode %s" % (len(rows), unicodedata.unidata_version))


def binary(seed=20261028, count=32):
    """Values chosen at random and encoded by the reference implementation of
    each binary format, so that the tests can ask two questions of every vector:
    does this tree encode to exactly these bytes, and does those bytes decode
    back to this tree."""
    import bson
    import cbor2
    import msgpack

    rng = random.Random(seed)
    vectors = []
    while len(vectors) < count:
        value = random_value(rng)
        # A BSON document is an object at the top, and one of the three formats
        # refusing a value would leave the others without a vector.
        if not isinstance(value, dict):
            continue
        try:
            encoded = {
                "cbor": cbor2.dumps(value, canonical=True),
                "msgpack": msgpack.packb(value, use_bin_type=True),
                "bson": bson.BSON.encode(value),
            }
        except (OverflowError, ValueError, bson.errors.InvalidDocument):
            continue
        vectors.append((value, encoded))

    for name, encode in (
        ("cbor", lambda v: cbor2.dumps(v, canonical=True)),
        ("msgpack", lambda v: msgpack.packb(v, use_bin_type=True)),
        ("bson", lambda v: bson.BSON.encode(v)),
    ):
        rows = []
        for value, encoded in vectors:
            rows.append(
                "  (%s, %s),"
                % (moonbit_literal(emit_value(value)),
                   moonbit_literal(encoded[name].hex()))
            )
        replace_between(
            os.path.join(ROOT, "src", name, "vectors_test.mbt"),
            "let vectors : Array[(String, String)] = [",
            "\n]\n",
            "\n".join(rows),
        )
    print("binary: %d values per format" % len(vectors))


def main(argv):
    if len(argv) != 2 or argv[1] not in (
        "jcs",
        "json-testsuite",
        "jsonpath",
        "json5",
        "binary",
        "categories",
    ):
        print(__doc__)
        print("corpora known to this script:", ", ".join(sorted(CORPORA)))
        return 2
    if argv[1] == "binary":
        binary()
        return 0
    if argv[1] == "categories":
        categories()
        return 0
    root = fetch(argv[1])
    globals()[argv[1].replace("-", "_")](root)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
