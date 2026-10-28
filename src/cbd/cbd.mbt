// CBD — CompactBinaryData:
// https://github.com/makalin/CBD
// Format spec: https://raw.githubusercontent.com/makalin/CBD/main/docs/format_specification.md
//
// A compact binary encoding of the JSON data model. A stream starts with a
// 5-byte header (magic 0xC1, version 0x01, three reserved zero bytes), then each
// value is a one-byte descriptor: its low 3 bits name the type, its high 5 bits
// hold a length or element count when that fits, and a 31 in those five bits is
// the escape to an unsigned LEB128 varint. This keeps the common small value to a
// single byte.
//
// Two choices keep the promise every package in this family makes — that a tree
// read here is written back unchanged. Numbers are stored as their IEEE-754 bits,
// so a value round-trips exactly; a byte string arrives as the reserved
// `{"$bytes": "…"}` member, so the byte strings of CBOR, MessagePack and BSON are
// one `$bytes` in the tree whatever format carried them. Both are noted on
// `load`/`dump`.
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How CBD is read and written.
///
/// The byte layout is fixed; the one knob is how deep a document may nest before
/// it is refused, because a document of a hundred thousand open brackets is a
/// denial of service rather than a document.
pub(all) struct Policy {
  /// The deepest nesting accepted, in levels.
  depth : Int32
} derive(Eq, Debug)

///|
pub extend Policy with Eq::{equal, not_equal}

///|
pub extend Policy with Debug::{to_repr}

///|
/// The default: five hundred levels deep.
pub let policy : Policy = { depth: 500, }

///|
/// Build a policy by naming the parts that differ from the default.
pub fn Policy::new(depth~ : Int32 = policy.depth) -> Policy {
  { depth, }
}

///|
/// What a tree becomes when a CBD value has no JSON counterpart.
///
/// | CBD | tree |
/// |:--|:--|
/// | `blob` | `{"$bytes": "0102"}` — lowercase hex, no separators |
///
/// A byte string survives a trip through this format, so the byte strings of
/// CBOR, MessagePack and BSON are one `$bytes` in the tree whichever format
/// carried them. A number is kept as its IEEE-754 bits, so `1` and `1.0`
/// round-trip exactly.
pub fn load(
  input : BytesView,
  policy~ : Policy = policy,
) -> Json raise @moonjson.Refused {
  let r : Reader = { src: input, policy, i: 0, }
  if r.byte() != 0xC1 {
    raise @moonjson.Bad(at=0, why="not a CBD stream (bad magic)")
  }
  if r.byte() != 0x01 {
    raise @moonjson.Bad(at=1, why="a CBD version this reader does not know")
  }
  let _ = r.byte()
  let _ = r.byte()
  let _ = r.byte()
  let value = r.node(0)
  if r.i < input.length() {
    raise @moonjson.Extra(at=r.i)
  }
  value
}

///|
/// Write a tree as CBD.
pub fn dump(
  value : Json,
  policy~ : Policy = policy,
) -> Bytes raise @moonjson.Refused {
  let buf = Buffer()
  buf.write_byte(0xC1)
  buf.write_byte(0x01)
  buf.write_byte(0x00)
  buf.write_byte(0x00)
  buf.write_byte(0x00)
  write(buf, value, policy)
  buf.to_bytes()
}

// ───────────────────────────── reading ─────────────────────────────

///|
priv struct Reader {
  src : BytesView
  policy : Policy
  mut i : Int32
}

///|
fn Reader::byte(self : Reader) -> Int32 raise @moonjson.Refused {
  if self.i >= self.src.length() {
    raise @moonjson.Short(at=self.i)
  }
  let b = self.src.at(self.i).to_int()
  self.i += 1
  b
}

///|
fn Reader::take(self : Reader, n : Int32) -> BytesView raise @moonjson.Refused {
  if n < 0 || self.i + n > self.src.length() {
    raise @moonjson.Short(at=self.src.length())
  }
  let view = self.src[self.i:self.i + n]
  self.i += n
  view
}

///|
fn Reader::uint64(self : Reader) -> UInt64 raise @moonjson.Refused {
  let mut v : UInt64 = 0
  for _ in 0..<8 {
    v = (v << 8) | self.byte().to_uint64()
  }
  v
}

///|
/// An unsigned LEB128 varint.
fn Reader::varint(self : Reader) -> Int32 raise @moonjson.Refused {
  let mut v : Int32 = 0
  let mut shift = 0
  let mut going = true
  while going {
    let b = self.byte()
    v = v | ((b & 0x7F) << shift)
    if (b & 0x80) == 0 {
      going = false
    } else {
      shift += 7
    }
  }
  v
}

///|
/// The length or count a descriptor carries: its high five bits, or a varint when
/// those five bits are the 31 escape.
fn Reader::count_of(self : Reader, d : Int32) -> Int32 raise @moonjson.Refused {
  let field = (d >> 3) & 0x1F
  if field < 31 {
    field
  } else {
    self.varint()
  }
}

///|
fn Reader::node(self : Reader, depth : Int32) -> Json raise @moonjson.Refused {
  if depth > self.policy.depth {
    raise @moonjson.Bad(
      at=self.i,
      why="nested deeper than \{self.policy.depth}",
    )
  }
  let d = self.byte()
  let type_ = d & 7
  match type_ {
    0 => Json::null()
    1 => Json::boolean(false)
    2 => Json::boolean(true)
    3 => Json::number(self.uint64().reinterpret_as_double())
    4 => {
      let n = self.count_of(d)
      let bytes = self.take(n)
      let decoded = @utf8.decode(bytes) catch {
        _ =>
          raise @moonjson.Bad(at=self.i, why="a text string that is not UTF-8")
      }
      Json::string(decoded)
    }
    5 => {
      let n = self.count_of(d)
      let bytes = self.take(n)
      Json::object({ "$bytes": @hex.encode(bytes[:]) })
    }
    6 => {
      let count = self.count_of(d)
      let items : Array[Json] = []
      for _ in 0..<count {
        items.push(self.node(depth + 1))
      }
      Json::array(items)
    }
    7 => {
      let count = self.count_of(d)
      let out : Map[String, Json] = Map([])
      for _ in 0..<count {
        let key = self.node(depth + 1)
        let name = match key {
          String(s) => s
          _ =>
            raise @moonjson.Bad(at=self.i, why="a member name that is not text")
        }
        out[name] = self.node(depth + 1)
      }
      Json::object(out)
    }
    _ =>
      raise @moonjson.Bad(
        at=self.i - 1,
        why="a CBD type this reader does not know",
      )
  }
}

// ───────────────────────────── writing ─────────────────────────────

///|
fn write(
  buf : Buffer,
  value : Json,
  policy : Policy,
) -> Unit raise @moonjson.Refused {
  match value {
    Null => buf.write_byte(0x00)
    False => buf.write_byte(0x01)
    True => buf.write_byte(0x02)
    Number(n, ..) => {
      buf.write_byte(0x03)
      buf.write_uint64_be(n.reinterpret_as_uint64())
    }
    String(s) => {
      let bytes = @utf8.encode(s[:])
      head(buf, 4, bytes.length())
      buf.write_bytes(bytes[:])
    }
    Array(items) => {
      let count : Int32 = items.length()
      head(buf, 6, count)
      for item in items {
        write(buf, item, policy)
      }
    }
    Object(members) => object(buf, members, policy)
  }
}

///|
/// The descriptor byte: a short length in the high five bits, or the 31 escape
/// followed by a varint.
fn head(buf : Buffer, type_ : Int32, len : Int32) -> Unit {
  if len < 31 {
    buf.write_byte(((len << 3) | type_).to_byte())
  } else {
    buf.write_byte(((31 << 3) | type_).to_byte())
    varint(buf, len)
  }
}

///|
fn varint(buf : Buffer, n : Int32) -> Unit {
  let mut v = n
  let mut going = true
  while going {
    if v >= 0x80 {
      buf.write_byte(((v & 0x7F) | 0x80).to_byte())
      v = v >> 7
    } else {
      buf.write_byte(v.to_byte())
      going = false
    }
  }
}

///|
/// An object is either the `$bytes` marker `load` documents, or a map whose keys
/// are strings — written in code-point order, because that is the order the tree
/// remembers them in and the order the reader sees them again.
fn object(
  buf : Buffer,
  members : Map[String, Json],
  policy : Policy,
) -> Unit raise @moonjson.Refused {
  if members.length() == 1 {
    match members.get("$bytes") {
      Some(String(hex)) => {
        let bytes = @hex.decode(hex[:]) catch {
          _ => raise @moonjson.Unwritable(why="\"$bytes\" wants lowercase hex")
        }
        let count : Int32 = bytes.length()
        head(buf, 5, count)
        buf.write_bytes(bytes[:])
        return
      }
      _ => ()
    }
  }
  let names : Array[String] = []
  for name, _ in members {
    names.push(name)
  }
  names.sort_by(compare_keys)
  let count : Int32 = names.length()
  head(buf, 7, count)
  for name in names {
    write(buf, Json::string(name), policy)
    write(buf, members.get(name).unwrap(), policy)
  }
}

///|
/// Bytewise lexicographic order of names, the order the reader meets them in.
fn compare_keys(a : String, b : String) -> Int32 {
  let ba = @utf8.encode(a[:])
  let bb = @utf8.encode(b[:])
  let mut i = 0
  while i < ba.length() && i < bb.length() {
    let x = ba.at(i).to_int()
    let y = bb.at(i).to_int()
    if x != y {
      return x - y
    }
    i += 1
  }
  ba.length() - bb.length()
}
