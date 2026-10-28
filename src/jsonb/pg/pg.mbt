// PostgreSQL jsonb — binary JSON:
// https://www.postgresql.org/docs/current/datatype-json.html
//
// The layout follows the on-disk jsonb shape in PostgreSQL's
// src/include/utils/jsonb.h: a 32-bit header word that packs the total length in
// the high 30 bits and the node type in the low 2 bits, then — for a container —
// an element-count word, a JEntry per element, and the data region the JEntries
// describe. A scalar node is a tag byte and its payload.
//
// Two choices keep the promise every package in this family makes — that a tree
// read here is written back unchanged. Numbers are stored as their IEEE-754 bits,
// so a value round-trips exactly rather than through a decimal string; a byte
// string arrives as the reserved `{"$bytes": "…"}` member, so a CBOR, MessagePack
// or BSON byte string survives a trip through this format too. Both are noted on
// `load`/`dump`.
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How PostgreSQL jsonb is read and written.
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
/// What a tree becomes when a jsonb value has no JSON counterpart.
///
/// | jsonb | tree |
/// |:--|:--|
/// | `blob` | `{"$bytes": "0102"}` — lowercase hex, no separators |
///
/// A byte string survives a trip through this format the same way it does
/// through SQLite jsonb, so the byte strings of CBOR, MessagePack and BSON are
/// one `$bytes` in the tree whatever format carried them. A number is kept as its
/// IEEE-754 bits, so `1` and `1.0` round-trip exactly.
pub fn load(
  input : BytesView,
  policy~ : Policy = policy,
) -> Json raise @moonjson.Refused {
  let r : Reader = { src: input, policy, i: 0, }
  let value = r.node(0)
  if r.i < input.length() {
    raise @moonjson.Extra(at=r.i)
  }
  value
}

///|
/// Write a tree as PostgreSQL jsonb.
pub fn dump(
  value : Json,
  policy~ : Policy = policy,
) -> Bytes raise @moonjson.Refused {
  let buf = Buffer()
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
/// Four bytes, big-endian, as a signed 32-bit word. The top bit is the null flag
/// in a JEntry and is always zero in a header, so the same reader serves both.
fn Reader::uint32(self : Reader) -> Int32 raise @moonjson.Refused {
  let mut v : Int32 = 0
  for _ in 0..<4 {
    v = (v << 8) | self.byte()
  }
  v
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
/// One node: a header word, then a body whose length the header gives.
fn Reader::node(self : Reader, depth : Int32) -> Json raise @moonjson.Refused {
  if depth > self.policy.depth {
    raise @moonjson.Bad(
      at=self.i,
      why="nested deeper than \{self.policy.depth}",
    )
  }
  let header = self.uint32()
  let type_ = header & 3
  let total = header >> 2
  let end = self.i + total - 4
  match type_ {
    0 => self.scalar_node(end)
    1 => self.object_node(depth, end)
    2 => self.array_node(depth, end)
    _ =>
      raise @moonjson.Bad(
        at=self.i - 4,
        why="a jsonb node type this reader does not know",
      )
  }
}

///|
fn Reader::scalar_node(
  self : Reader,
  end : Int32,
) -> Json raise @moonjson.Refused {
  let tag = self.byte()
  let value = match tag {
    0x06 => Json::null()
    0x01 => Json::boolean(true)
    0x02 => Json::boolean(false)
    0x04 => Json::number(self.uint64().reinterpret_as_double())
    0x05 => {
      let n = self.uint32()
      let bytes = self.take(n)
      let decoded = @utf8.decode(bytes) catch {
        _ =>
          raise @moonjson.Bad(at=self.i, why="a text string that is not UTF-8")
      }
      Json::string(decoded)
    }
    0x07 => {
      let n = self.uint32()
      let bytes = self.take(n)
      Json::object({ "$bytes": @hex.encode(bytes[:]) })
    }
    _ =>
      raise @moonjson.Bad(
        at=self.i - 1,
        why="a jsonb scalar tag this reader does not know",
      )
  }
  if self.i != end {
    raise @moonjson.Bad(at=self.i, why="a scalar whose length does not match")
  }
  value
}

///|
fn Reader::array_node(
  self : Reader,
  depth : Int32,
  end : Int32,
) -> Json raise @moonjson.Refused {
  let nentries = self.uint32()
  let count = nentries >> 1
  let jentries : Array[Int32] = []
  for _ in 0..<count {
    jentries.push(self.uint32())
  }
  let items : Array[Json] = []
  for k in 0..<count {
    let entry = jentries[k]
    if entry < 0 {
      items.push(Json::null())
    } else {
      let probe = self.i + entry
      items.push(self.node(depth + 1))
      if self.i != probe {
        raise @moonjson.Bad(
          at=self.i,
          why="an element shorter than its entry says",
        )
      }
    }
  }
  if self.i != end {
    raise @moonjson.Bad(at=self.i, why="an array shorter than its length says")
  }
  Json::array(items)
}

///|
/// An object is `count` name/value pairs. The JEntry array holds the name and
/// the value of each pair in turn; a name is always a text node.
fn Reader::object_node(
  self : Reader,
  depth : Int32,
  end : Int32,
) -> Json raise @moonjson.Refused {
  let nentries = self.uint32()
  let count = nentries >> 1
  let jentries : Array[Int32] = []
  for _ in 0..<(count * 2) {
    jentries.push(self.uint32())
  }
  let out : Map[String, Json] = Map([])
  for k in 0..<count {
    let key_entry = jentries[k * 2]
    let val_entry = jentries[k * 2 + 1]
    let key_end = self.i + key_entry
    let key = self.node(depth + 1)
    if self.i != key_end {
      raise @moonjson.Bad(
        at=self.i,
        why="a member name shorter than its entry says",
      )
    }
    let name = match key {
      String(s) => s
      _ => raise @moonjson.Bad(at=self.i, why="a member name that is not text")
    }
    if val_entry < 0 {
      out[name] = Json::null()
    } else {
      let val_end = self.i + val_entry
      out[name] = self.node(depth + 1)
      if self.i != val_end {
        raise @moonjson.Bad(
          at=self.i,
          why="a member value shorter than its entry says",
        )
      }
    }
  }
  if self.i != end {
    raise @moonjson.Bad(at=self.i, why="an object shorter than its length says")
  }
  Json::object(out)
}

// ───────────────────────────── writing ─────────────────────────────

///|
fn write(
  buf : Buffer,
  value : Json,
  policy : Policy,
) -> Unit raise @moonjson.Refused {
  match value {
    Null => scalar(buf, single(0x06))
    True => scalar(buf, single(0x01))
    False => scalar(buf, single(0x02))
    Number(n, ..) => {
      let body = Buffer()
      body.write_byte(0x04)
      body.write_uint64_be(n.reinterpret_as_uint64())
      scalar(buf, body)
    }
    String(s) => {
      let bytes = @utf8.encode(s[:])
      let body = Buffer()
      body.write_byte(0x05)
      body.write_uint_be(bytes.length().reinterpret_as_uint())
      body.write_bytes(bytes[:])
      scalar(buf, body)
    }
    Array(items) => array(buf, items, policy)
    Object(members) => object(buf, members, policy)
  }
}

///|
fn single(b : Int32) -> Buffer {
  let body = Buffer()
  body.write_byte(b.to_byte())
  body
}

///|
/// A scalar node: a header whose total length includes this word, then the body.
fn scalar(buf : Buffer, body : Buffer) -> Unit {
  let total : Int32 = 4 + body.length()
  let header : Int32 = (total << 2) | 0
  buf.write_uint_be(header.reinterpret_as_uint())
  buf.write_bytes(body.to_bytes()[:])
}

///|
fn array(
  buf : Buffer,
  items : Array[Json],
  policy : Policy,
) -> Unit raise @moonjson.Refused {
  let parts : Array[Bytes] = []
  let jentries : Array[UInt32] = []
  let mut has_null = false
  let mut data_len : Int32 = 0
  for item in items {
    match item {
      Null => {
        has_null = true
        jentries.push(0x8000_0000U)
      }
      _ => {
        let child = Buffer()
        write(child, item, policy)
        let bytes = child.to_bytes()
        jentries.push(bytes.length().reinterpret_as_uint())
        parts.push(bytes)
        data_len = data_len + bytes.length()
      }
    }
  }
  let count : Int32 = items.length()
  let total : Int32 = 4 + 4 + 4 * count + data_len
  let header : Int32 = (total << 2) | 2
  buf.write_uint_be(header.reinterpret_as_uint())
  let nentries : Int32 = (count << 1) | (if has_null { 1 } else { 0 })
  buf.write_uint_be(nentries.reinterpret_as_uint())
  for entry in jentries {
    buf.write_uint_be(entry)
  }
  for part in parts {
    buf.write_bytes(part[:])
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
        let body = Buffer()
        body.write_byte(0x07)
        body.write_uint_be(bytes.length().reinterpret_as_uint())
        body.write_bytes(bytes[:])
        scalar(buf, body)
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
  let parts : Array[Bytes] = []
  let jentries : Array[UInt32] = []
  let mut has_null = false
  let mut data_len : Int32 = 0
  for name in names {
    let key_body = Buffer()
    write(key_body, Json::string(name), policy)
    let key_bytes = key_body.to_bytes()
    jentries.push(key_bytes.length().reinterpret_as_uint())
    parts.push(key_bytes)
    data_len = data_len + key_bytes.length()
    let value = members.get(name).unwrap()
    match value {
      Null => {
        has_null = true
        jentries.push(0x8000_0000U)
      }
      _ => {
        let val_body = Buffer()
        write(val_body, value, policy)
        let val_bytes = val_body.to_bytes()
        jentries.push(val_bytes.length().reinterpret_as_uint())
        parts.push(val_bytes)
        data_len = data_len + val_bytes.length()
      }
    }
  }
  let count : Int32 = names.length()
  let total : Int32 = 4 + 4 + 4 * (count * 2) + data_len
  let header : Int32 = (total << 2) | 1
  buf.write_uint_be(header.reinterpret_as_uint())
  let nentries : Int32 = (count << 1) | (if has_null { 1 } else { 0 })
  buf.write_uint_be(nentries.reinterpret_as_uint())
  for entry in jentries {
    buf.write_uint_be(entry)
  }
  for part in parts {
    buf.write_bytes(part[:])
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
