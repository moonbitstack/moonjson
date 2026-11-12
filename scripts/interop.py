#!/usr/bin/env python3
"""Interoperability: this library against the reference implementation of each
format, in both directions, on one corpus.

The bench is `integration/`, a module of its own so that neither `moonbitlang/x`
nor a Python package becomes a dependency of the library. It answers two
questions per format:

    our writer -> their reader      does the reference implementation read what
                                    this library writes, as the same value?
    their writer -> our reader      does this library read what the reference
                                    implementation writes, as the same value?

Both directions matter and they fail differently. A writer that is subtly wrong
still round-trips through its own reader; only a foreign reader catches it.

Reference implementations:

    pip install cbor2 msgpack pymongo json5 hjson

Usage:

    python scripts/interop.py            # every format
    python scripts/interop.py cbor bson  # only these
"""

import json
import math
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BENCH = os.path.join("integration", "src")

# One corpus for every format: the values that a JSON tree can hold, and the
# corners of each — an empty container, a character outside the BMP, a control
# character, a number that is not an integer, both signed zeros, the edges of
# what a double holds.
#
# A line feed and not a carriage return: Hjson writes a string that spans lines
# as a multiline string, and the reference writer folds a bare CR into that line
# break, so a CR in the corpus would compare a value against what their writer
# lost rather than against what either side read.
CORPUS = [
    None,
    True,
    False,
    0,
    -1,
    255,
    65536,
    9007199254740991,
    -9007199254740991,
    0.5,
    -2.5,
    0.0,
    -0.0,
    3.141592653589793,
    1e-300,
    1.7976931348623157e308,
    "",
    "a",
    "héllo wörld",
    "中文测试",
    "😀🎉",
    "line\nbreak\nend",
    "tab\there",
    "quote \" and ' and \\",
    "control \x00\x01\x1f",
    [],
    {},
    [1, 2, 3],
    [[[]]],
    [0.0, -0.0, 1],
    {"a": 1, "b": [True, None], "c": {"d": "e"}},
    {"": "empty key"},
    {"key with space": "value", "ключ": "значение", "日本": "語"},
    {"n": 1234567890, "f": 2.5, "s": "x"},
    {"deep": {"deeper": {"deepest": [1, {"end": True}]}}},
]


def reference():
    """The reference implementations, imported lazily so that running one
    format does not need the packages of the others."""
    import bson
    import cbor2
    import hjson
    import json5
    import msgpack

    def bson_write(value):
        # A BSON document is an object at the top, so the driver hands this one
        # the wrapper it already made.
        return bson.BSON.encode(value)

    def bson_read(data):
        return bson.BSON(data).decode()

    def msgpack_read(data):
        return msgpack.unpackb(data, strict_map_key=False, raw=False)

    return {
        "json": {
            "binary": False,
            "write": lambda v: json.dumps(v, ensure_ascii=False),
            "read": json.loads,
        },
        "json5": {
            "binary": False,
            "write": lambda v: json5.dumps(v),
            "read": json5.loads,
        },
        "hjson": {
            "binary": False,
            "write": lambda v: hjson.dumps(v),
            "read": hjson.loads,
        },
        "cbor": {
            "binary": True,
            "write": cbor2.dumps,
            "read": cbor2.loads,
        },
        "msgpack": {
            "binary": True,
            "write": msgpack.packb,
            "read": msgpack_read,
        },
        "bson": {
            "binary": True,
            # A BSON document is an object at the top, so a value travels inside one.
            "write": bson_write,
            "read": bson_read,
            "wrap": True,
        },
    }


def same(left, right):
    """Equal as values, which is not `==` in Python: `True == 1` and
    `0.0 == -0.0` there, and neither is the same value here."""
    if isinstance(left, bool) or isinstance(right, bool):
        return isinstance(left, bool) and isinstance(right, bool) and left == right
    if left is None or right is None:
        return left is None and right is None
    if isinstance(left, (int, float)) and isinstance(right, (int, float)):
        if left != right:
            return False
        if isinstance(left, float) and isinstance(right, float):
            return math.copysign(1.0, left) == math.copysign(1.0, right)
        return True
    if isinstance(left, str) and isinstance(right, str):
        return left == right
    if isinstance(left, list) and isinstance(right, list):
        return len(left) == len(right) and all(same(a, b) for a, b in zip(left, right))
    if isinstance(left, dict) and isinstance(right, dict):
        return left.keys() == right.keys() and all(
            same(left[key], right[key]) for key in left
        )
    return False


def call(command, fmt, cases, workdir):
    """Run the bench on one case file, and answer what it wrote."""
    source = os.path.join(workdir, "cases.json")
    answer = os.path.join(workdir, "answer.json")
    with open(source, "w", encoding="utf-8") as handle:
        json.dump(cases, handle, ensure_ascii=False)
    result = subprocess.run(
        ["moon", "run", BENCH, "--target", "native", "--", command, fmt, source, answer],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "the bench failed on %s %s:\n%s%s" % (command, fmt, result.stdout, result.stderr)
        )
    with open(answer, encoding="utf-8") as handle:
        return json.load(handle)


def check(fmt, spec, workdir):
    """Both directions for one format, and the mismatches that were found."""
    failures = []
    wrapped = [{"v": value} for value in CORPUS] if spec.get("wrap") else CORPUS
    plain = [value["v"] for value in wrapped] if spec.get("wrap") else CORPUS

    # Ours written, theirs read.
    ours = call("encode", fmt, wrapped, workdir)
    for index, written in enumerate(ours):
        if not isinstance(written, str):
            failures.append("case %d: our writer refused: %s" % (index, written))
            continue
        data = bytes.fromhex(written) if spec["binary"] else written
        try:
            theirs = spec["read"](data)
        except Exception as error:  # noqa: BLE001 — any refusal is a finding
            failures.append("case %d: their reader refused ours: %s" % (index, error))
            continue
        want = wrapped[index] if spec.get("wrap") else plain[index]
        if not same(theirs, want):
            failures.append(
                "case %d: their reader got %r from ours, wanted %r"
                % (index, theirs, want)
            )

    # Theirs written, ours read.
    theirs = []
    for value in wrapped:
        data = spec["write"](value)
        theirs.append(data.hex() if spec["binary"] else data)
    answers = call("decode", fmt, theirs, workdir)
    for index, answer in enumerate(answers):
        if not isinstance(answer, str):
            failures.append("case %d: our reader refused theirs: %s" % (index, answer))
            continue
        read = json.loads(answer)
        if spec.get("wrap"):
            read = read["v"]
        if not same(read, plain[index]):
            failures.append(
                "case %d: our reader got %r from theirs, wanted %r"
                % (index, read, plain[index])
            )
    return failures


def main(argv):
    formats = reference()
    chosen = argv[1:] or list(formats)
    unknown = [name for name in chosen if name not in formats]
    if unknown:
        print("no such format: %s" % ", ".join(unknown))
        return 2
    checked = 0
    broken = 0
    for fmt in chosen:
        with tempfile.TemporaryDirectory() as workdir:
            failures = check(fmt, formats[fmt], workdir)
        checked += len(CORPUS)
        broken += len(failures)
        print(
            "%-8s %3d cases, two directions: %s"
            % (fmt, len(CORPUS), "ok" if not failures else "%d mismatches" % len(failures))
        )
        for line in failures:
            print("    " + line)
    print(
        "%d cases over %d formats, %d directions: %s"
        % (
            checked,
            len(chosen),
            len(chosen) * 2,
            "interoperable" if broken == 0 else "%d mismatches" % broken,
        )
    )
    return 0 if broken == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
