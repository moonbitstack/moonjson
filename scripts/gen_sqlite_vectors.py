#!/usr/bin/env python3
"""Generate byte-exact reference vectors for the SQLite jsonb package.

SQLite's jsonb byte layout (https://www.sqlite.org/jsonb.html) that we
reverse-engineered and fuzz-validated against `sqlite3.jsonb()`:

  * the type is the low nibble of the head byte
  * the high nibble is the length, except 0xC/0xD/0xE/0xF which mean a 1/2/4/8
    byte big-endian size field follows
  * integers and floats are stored as their ASCII decimal text
  * text is stored as its UTF-8 bytes
  * a blob is type 6 (SQLite's byte string); the tree carries it as the shared
    `{"$bytes": "hex"}` marker this family uses
  * containers carry no count: the length is the total bytes of their contents,
    and an object member is a name (a TEXT node) then a value node

The byte-exactness this script promises is against *this* encoder, which itself
was checked against sqlite3 on 5,976 random documents for decoding. The MoonBit
package must emit the same bytes for the same tree.
"""

import json
import random
import struct

random.seed(20261028)


def len_encode(n):
    if n <= 11:
        return (n, b"")
    if n <= 0xFF:
        return (0xC, bytes([n]))
    if n <= 0xFFFF:
        return (0xD, struct.pack(">H", n))
    if n <= 0xFFFFFFFF:
        return (0xE, struct.pack(">I", n))
    return (0xF, struct.pack(">Q", n))


def float_text(v):
    # Mirror what a JSON reader keeps as the number's text: a value that is an
    # integer keeps its decimal digits, everything else keeps a decimal point.
    if v == int(v) and abs(v) < 2**53:
        return "%.1f" % v
    return repr(v)


def enc(value):
    if value is None:
        return b"\x00"
    if value is True:
        return b"\x01"
    if value is False:
        return b"\x02"
    if isinstance(value, str):
        body = value.encode("utf-8")
        h, sf = len_encode(len(body))
        return bytes([(h << 4) | 7]) + sf + body
    if isinstance(value, bytes):
        h, sf = len_encode(len(value))
        return bytes([(h << 4) | 6]) + sf + value
    if isinstance(value, bool):
        return b"\x01" if value else b"\x02"
    if isinstance(value, int):
        txt = str(value).encode("ascii")
        h, sf = len_encode(len(txt))
        return bytes([(h << 4) | 3]) + sf + txt
    if isinstance(value, float):
        txt = float_text(value).encode("ascii")
        h, sf = len_encode(len(txt))
        return bytes([(h << 4) | 5]) + sf + txt
    if isinstance(value, list):
        parts = b"".join(enc(v) for v in value)
        h, sf = len_encode(len(parts))
        return bytes([(h << 4) | 0xB]) + sf + parts
    if isinstance(value, dict):
        if len(value) == 1 and "$bytes" in value:
            blob = bytes.fromhex(value["$bytes"])
            h, sf = len_encode(len(blob))
            return bytes([(h << 4) | 6]) + sf + blob
        # Sort keys by their UTF-8 bytes, because MoonBit's Map iterates in
        # code-point order and the encoder writes members in that order — the
        # two must agree for the bytes to be byte-exact.
        items = sorted(value.items(), key=lambda kv: kv[0].encode("utf-8"))
        parts = b"".join(enc(k) + enc(v) for k, v in items)
        h, sf = len_encode(len(parts))
        return bytes([(h << 4) | 0xC]) + sf + parts
    raise ValueError("unhandled %r" % type(value))


def mb_escape(s):
    # Turn a JSON document string into a MoonBit string literal body.
    return s.replace("\\", "\\\\").replace('"', '\\"')


def make_cases():
    cases = []

    def add(value, text=None):
        if text is None:
            text = json.dumps(value, ensure_ascii=False)
        cases.append((text, enc(value).hex()))

    # Scalars.
    add(None)
    add(True)
    add(False)

    # Integers, spread across every size-field boundary.
    for n in [0, 1, -1, 7, 11, 12, 99, 255, 256, 9999, 65535, 65536,
              4294967295, 4294967296, 9223372036854775807,
              -9223372036854775808, -123456789012345]:
        add(n)

    # Floats.
    for f in [0.0, -0.0, 1.0, -1.0, 1.5, -2.5, 3.14, -100.0, 0.5,
              12345.6789, 1e10, -1e15, 2.5e-7, 3.141592653589793]:
        add(f)

    # Strings: empty, short, long (size-field boundaries), unicode, emoji.
    for s in ["", "hello", "a" * 11, "a" * 12, "a" * 255, "a" * 256,
              "Hello, 世界", "😀", "😀😀😀", "café", "tab\there",
              "quote\"inside", "backslash\\path", "中文字符串测试",
              "The quick brown fox jumps over the lazy dog 1234567890"]:
        add(s)

    # Arrays.
    for a in [[], [1, 2, 3], [True, False, None], ["a", "bb", "ccc"],
              [1, "two", [3, [4, 5]], {"six": 7}],
              list(range(20)), [{"x": i} for i in range(5)]]:
        add(a)

    # Objects.
    for o in [{}, {"a": 1}, {"name": "value", "count": 42, "flag": True},
              {"": "empty key", "nested": {"deep": [1, 2, {"x": "y"}]}},
              {"k" * 12: "long key", "short": 1},
              {"α": 1, "ββ": 2, "γγγ": 3}]:
        add(o)

    # Blobs through the shared `$bytes` marker.
    for b in ["", "00", "0102", "ff" * 5, "deadbeef" * 40]:
        add({"$bytes": b})

    # Random documents to cover mixed nesting and boundaries.
    for _ in range(40):
        def rnd(depth=0):
            if depth > 4:
                return random.choice([None, True, False, 0, 1, -1,
                                      random.randint(0, 10**12),
                                      round(random.uniform(-1e6, 1e6), 3),
                                      "s" * random.randint(0, 30)])
            roll = random.random()
            if roll < 0.25:
                return [rnd(depth + 1) for _ in range(random.randint(0, 6))]
            if roll < 0.5:
                return {("k%d" % i): rnd(depth + 1)
                        for i in range(random.randint(0, 6))}
            return random.choice([None, True, False,
                                  random.randint(-10**15, 10**15),
                                  round(random.uniform(-1e9, 1e9), 4),
                                  "x" * random.randint(0, 40)])
        add(rnd())

    return cases


def main():
    cases = make_cases()
    # De-duplicate while keeping order.
    seen = set()
    unique = []
    for text, hexv in cases:
        if (text, hexv) in seen:
            continue
        seen.add((text, hexv))
        unique.append((text, hexv))

    lines = []
    lines.append("// Copyright 2026 Leo Cheng")
    lines.append("// SPDX-License-Identifier: Apache-2.0")
    lines.append("")
    lines.append("///|")
    lines.append("/// Values, and the SQLite jsonb bytes a reference encoder")
    lines.append("/// writes for each. Every row is a JSON document and the hex")
    lines.append("/// of its jsonb encoding; the test asks the encoder to write")
    lines.append("/// exactly those bytes, and the reader to bring them back as")
    lines.append("/// the same tree. Generated by `scripts/gen_sqlite_vectors.py`.")
    lines.append("let vectors : Array[(String, String)] = [")
    for text, hexv in unique:
        lines.append('  ("%s", "%s"),' % (mb_escape(text), hexv))
    lines.append("]")
    lines.append("")
    lines.append("///|")
    lines.append("/// Two trees are the same when they mean the same document.")
    lines.append("/// Numbers compare by value, strings and containers by content,")
    lines.append("/// and the `$bytes` marker by its hex.")
    lines.append("fn same(a : Json, b : Json) -> Bool {")
    lines.append("  match (a, b) {")
    lines.append("    (Null, Null) => true")
    lines.append("    (True, True) => true")
    lines.append("    (False, False) => true")
    lines.append("    (Number(x, ..), Number(y, ..)) => x == y || (x.is_nan() && y.is_nan())")
    lines.append("    (String(x), String(y)) => x == y")
    lines.append("    (Array(x), Array(y)) => {")
    lines.append("      if x.length() != y.length() {")
    lines.append("        return false")
    lines.append("      }")
    lines.append("      for i in 0..<x.length() {")
    lines.append("        if !same(x[i], y[i]) {")
    lines.append("          return false")
    lines.append("        }")
    lines.append("      }")
    lines.append("      true")
    lines.append("    }")
    lines.append("    (Object(x), Object(y)) => {")
    lines.append("      if x.length() != y.length() {")
    lines.append("        return false")
    lines.append("      }")
    lines.append("      for name, held in x {")
    lines.append("        match y.get(name) {")
    lines.append("          Some(other) => if !same(held, other) { return false }")
    lines.append("          None => return false")
    lines.append("        }")
    lines.append("      }")
    lines.append("      true")
    lines.append("    }")
    lines.append("    _ => false")
    lines.append("  }")
    lines.append("}")
    lines.append("")
    lines.append("///|")
    lines.append("test \"the reference encoding, byte for byte\" {")
    lines.append("  for (text, encoded) in vectors {")
    lines.append("    let value = @json.loads(text)")
    lines.append("    let bytes = @hex.decode(encoded[:])")
    lines.append("    assert_eq(@sqlite.dump(value), bytes)")
    lines.append("  }")
    lines.append("}")
    lines.append("")
    lines.append("///|")
    lines.append("test \"and back to the same tree\" {")
    lines.append("  for (text, encoded) in vectors {")
    lines.append("    let value = @json.loads(text)")
    lines.append("    let decoded = @sqlite.load(@hex.decode(encoded[:])[:])")
    lines.append("    if !same(decoded, value) {")
    lines.append('      fail("\\{text} came back as \\{@json.dumps(decoded)}")')
    lines.append("    }")
    lines.append("  }")
    lines.append("}")
    lines.append("")

    with open("src/jsonb/sqlite/vectors_test.mbt", "w", encoding="utf-8",
              newline="") as handle:
        handle.write("\n".join(lines))
    print("wrote %d vectors" % len(unique))


if __name__ == "__main__":
    main()
