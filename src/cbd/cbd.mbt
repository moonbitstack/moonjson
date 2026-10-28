// CBD — CompactBinaryData:
// https://github.com/makalin/CBD
// Format spec: https://raw.githubusercontent.com/makalin/CBD/main/docs/format_specification.md
//
// The framing follows the specification literally:
//
//   Header (5 bytes): magic 0xCB 0xD1, version 0x01, dictionary size (uint16 BE)
//   Dictionary:       one UTF-8 key each, length as 1 byte (<128) or 2 bytes
//                     with the high bit set, in order of first appearance;
//                     keys get the 1-based ids 1, 2, 3 …
//   Data:             one type byte per value. Bits 7-5 are the type code, bit 0
//                     is the container flag, bits 4-1 are reserved. Null 0x00,
//                     false 0x20, true 0x21, number 0x40 with a 2-bit format,
//                     string 0x60, array 0x81, object 0xA1; counts and lengths
//                     are unsigned LEB128 varints, big-endian for fixed words.
//
// Two points the draft leaves open are pinned down here and written on the
// declarations: the number format bits live in bits 2-1 (00 integer, 11 float64),
// and a number that is not a non-negative integral value is written as float64
// so every JSON number round-trips exactly. The draft's own example — an object
// with `name` and `age` — is decoded in the tests, byte for byte.
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
/// Read one CBD document.
///
/// The header is magic `0xCB 0xD1`, version `0x01`, then the dictionary size.
/// A byte string has no type of its own in CBD v0.1.0, so it stays an ordinary
/// object `{"$bytes": "…"}` — the marker every package in this family shares —
/// and a trip through CBD leaves it exactly as it was.
pub fn load(
  input : BytesView,
  policy~ : Policy = policy,
) -> Json raise @moonjson.Refused {
  let r : Reader = { src: input, policy, i: 0, }
  if r.byte() != 0xCB {
    raise @moonjson.Bad(at=0, why="not a CBD stream (bad magic)")
  }
  if r.byte() != 0xD1 {
    raise @moonjson.Bad(at=1, why="not a CBD stream (bad magic)")
  }
  if r.byte() != 0x01 {
    raise @moonjson.Bad(at=2, why="a CBD version this reader does not know")
  }
  let dict_count = (r.byte() << 8) | r.byte()
  let dict : Array[String] = []
  for _ in 0..<dict_count {
    dict.push(r.dict_key())
  }
  let value = r.node(0, dict)
  if r.i < input.length() {
    raise @moonjson.Extra(at=r.i)
  }
  value
}

///|
/// Write a tree as CBD.
///
/// The dictionary is built in the order keys are first met, matching the
/// specification's "order of first appearance".
pub fn dump(
  value : Json,
  policy~ : Policy = policy,
) -> Bytes raise @moonjson.Refused {
  let dict : Array[String] = []
  let index : Map[String, Int32] = Map([])
  collect(value, dict, index)
  let buf = Buffer()
  buf.write_byte(0xCB)
  buf.write_byte(0xD1)
  buf.write_byte(0x01)
  buf.write_uint16_be(dict.length().to_uint16())
  for key in dict {
    write_dict_key(buf, key)
  }
  write(buf, value, index, policy)
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
/// An unsigned LEB128 varint, as a count, a length or a key id.
fn Reader::varint(self : Reader) -> Int32 raise @moonjson.Refused {
  self.varint_u64().to_int()
}

///|
fn Reader::varint_u64(self : Reader) -> UInt64 raise @moonjson.Refused {
  let mut v : UInt64 = 0
  let mut shift = 0
  let mut going = true
  while going {
    let b = self.byte()
    v = v | ((b.to_uint64() & 0x7FUL) << shift)
    if (b & 0x80) == 0 {
      going = false
    } else {
      shift += 7
    }
  }
  v
}

///|
/// A dictionary key: a length (one byte, or two with the high bit set) then the
/// UTF-8 bytes.
fn Reader::dict_key(self : Reader) -> String raise @moonjson.Refused {
  let first = self.byte()
  let n = if (first & 0x80) == 0 {
    first
  } else {
    ((first & 0x7F) << 8) | self.byte()
  }
  let bytes = self.take(n)
  @utf8.decode(bytes) catch {
    _ =>
      raise @moonjson.Bad(at=self.i, why="a dictionary key that is not UTF-8")
  }
}

///|
fn Reader::node(
  self : Reader,
  depth : Int32,
  dict : Array[String],
) -> Json raise @moonjson.Refused {
  if depth > self.policy.depth {
    raise @moonjson.Bad(
      at=self.i,
      why="nested deeper than \{self.policy.depth}",
    )
  }
  let d = self.byte()
  let type_ = (d >> 5) & 7
  let is_container = (d & 1) == 1
  match type_ {
    0 => Json::null()
    1 => Json::boolean(is_container)
    2 => self.number_node(d)
    3 => {
      let n = self.varint()
      let bytes = self.take(n)
      let decoded = @utf8.decode(bytes) catch {
        _ =>
          raise @moonjson.Bad(at=self.i, why="a text string that is not UTF-8")
      }
      Json::string(decoded)
    }
    4 => {
      let count = self.varint()
      let items : Array[Json] = []
      for _ in 0..<count {
        items.push(self.node(depth + 1, dict))
      }
      Json::array(items)
    }
    5 => {
      let count = self.varint()
      let out : Map[String, Json] = Map([])
      for _ in 0..<count {
        let id = self.varint()
        if id < 1 || id > dict.length() {
          raise @moonjson.Bad(at=self.i, why="a key id outside the dictionary")
        }
        let name = dict[id - 1]
        out[name] = self.node(depth + 1, dict)
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

///|
/// A number: the two format bits live in bits 2-1. `00`/`01` are a non-negative
/// integer as a varint, `11` is a 64-bit float, `10` a 32-bit float.
fn Reader::number_node(
  self : Reader,
  d : Int32,
) -> Json raise @moonjson.Refused {
  let format = (d >> 1) & 3
  if format == 0 || format == 1 {
    Json::number(self.varint_u64().to_double())
  } else if format == 3 {
    Json::number(self.uint64().reinterpret_as_double())
  } else {
    let _ = self.byte()
    let _ = self.byte()
    let _ = self.byte()
    let _ = self.byte()
    raise @moonjson.Bad(
      at=self.i - 4,
      why="a 32-bit float, which this encoder never writes",
    )
  }
}

// ───────────────────────────── writing ─────────────────────────────

///|
/// Collect every object key once, in the order it is first met, and give it its
/// 1-based id. A key that repeats keeps its first id.
fn collect(
  value : Json,
  dict : Array[String],
  index : Map[String, Int32],
) -> Unit {
  match value {
    Object(members) =>
      for name, child in members {
        if index.get(name) == None {
          dict.push(name)
          index[name] = dict.length()
        }
        collect(child, dict, index)
      }
    Array(items) =>
      for item in items {
        collect(item, dict, index)
      }
    _ => ()
  }
}

///|
fn write_dict_key(buf : Buffer, key : String) -> Unit {
  let bytes = @utf8.encode(key[:])
  let n = bytes.length()
  if n < 128 {
    buf.write_byte(n.to_byte())
  } else {
    buf.write_byte((0x80 | (n >> 8)).to_byte())
    buf.write_byte((n & 0xFF).to_byte())
  }
  buf.write_bytes(bytes[:])
}

///|
fn write(
  buf : Buffer,
  value : Json,
  index : Map[String, Int32],
  policy : Policy,
) -> Unit raise @moonjson.Refused {
  match value {
    Null => buf.write_byte(0x00)
    False => buf.write_byte(0x20)
    True => buf.write_byte(0x21)
    Number(n, ..) => write_number(buf, n)
    String(s) => {
      let bytes = @utf8.encode(s[:])
      buf.write_byte(0x60)
      write_varint(buf, bytes.length())
      buf.write_bytes(bytes[:])
    }
    Array(items) => {
      buf.write_byte(0x81)
      write_varint(buf, items.length())
      for item in items {
        write(buf, item, index, policy)
      }
    }
    Object(members) => {
      buf.write_byte(0xA1)
      write_varint(buf, members.length())
      for name, child in members {
        write_varint(buf, index.get(name).unwrap())
        write(buf, child, index, policy)
      }
    }
  }
}

///|
/// A number: a non-negative integral value that fits in an unsigned 64-bit word
/// goes as format `00` and a varint, matching the specification's example; a
/// value that is not one goes as format `11` and its IEEE-754 bits, so every
/// JSON number — negative, fractional, huge — round-trips exactly.
fn write_number(buf : Buffer, n : Double) -> Unit {
  if n >= 0.0 && n == @double.trunc(n) && n < 1.8e19 {
    buf.write_byte(0x40)
    write_varint_u64(buf, n.to_int64().reinterpret_as_uint64())
  } else {
    buf.write_byte(0x46)
    buf.write_uint64_be(n.reinterpret_as_uint64())
  }
}

///|
fn write_varint(buf : Buffer, n : Int32) -> Unit {
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
fn write_varint_u64(buf : Buffer, n : UInt64) -> Unit {
  let mut v = n
  let mut going = true
  while going {
    if v >= 0x80UL {
      buf.write_byte(((v & 0x7FUL) | 0x80UL).to_byte())
      v = v >> 7
    } else {
      buf.write_byte(v.to_byte())
      going = false
    }
  }
}
