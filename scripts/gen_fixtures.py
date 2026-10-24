#!/usr/bin/env python3
"""Regenerate the test vectors that come from somebody else's repository.

The tests hold their vectors as MoonBit literals, because a test that reads a
file cannot run on wasm and js. This script is how those literals are made: it
takes the reference corpora, and writes the table back into the test file
between two markers, so regenerating is a diff of the vectors rather than of the
whole file.

Nothing here runs in CI — it is a maintainer's tool. The corpora are not in the
repository either; `.ref/` is ignored, and this script fetches what it needs.

    python scripts/gen_fixtures.py jcs

The formats whose vectors are printed in a specification (CBOR's appendix A,
MessagePack's format table, BSON's two documents) are transcribed by hand into
their test files, because the specification is prose and HTML and a parser for
it would be more code than the vectors are worth. The script says so rather than
pretending to do it.
"""

import json
import os
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
        os.path.join(ROOT, "jcs", "jcs_test.mbt"),
        "let vectors : Array[(String, String)] = [",
        "\n]\n",
        "\n".join(rows),
    )
    print("jcs: %d vectors" % len(rows))


def main(argv):
    if len(argv) != 2 or argv[1] not in ("jcs",):
        print(__doc__)
        print("corpora known to this script:", ", ".join(sorted(CORPORA)))
        return 2
    root = fetch(argv[1])
    globals()[argv[1]](root)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
