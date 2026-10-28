// KRSON — https://crates.io/crates/krson-core (Rust core), https://www.npmjs.com/package/krson-js (JS SDK)
//
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How KRSON is read and written.
///
/// Two knobs, both things the format leaves to the caller rather than things we
/// invented: whether object members are written in sorted key order, and how
/// deep a document may nest before it is refused.
pub(all) struct Policy {
  /// Write object members in bytewise order of their key. KRSON is a
  /// self-describing format, so the order never changes what is read back, but a
  /// caller that wants a stable byte image (for a hash or a signature) turns
  /// this on.
  deterministic : Bool
  /// How deep nesting may go. The same five hundred the text reader allows, and
  /// for the same reason: a document of a hundred thousand open brackets is a
  /// denial of service rather than a document.
  depth : Int32
} derive(Eq, Debug)

///|
pub extend Policy with Eq::{equal, not_equal}

///|
pub extend Policy with Debug::{to_repr}

///|
/// The defaults: keys in source order, five hundred levels deep.
pub let policy : Policy = { deterministic: false, depth: 500, }

///|
/// Build a policy by naming the parts that differ from the defaults.
pub fn Policy::new(
  deterministic~ : Bool = policy.deterministic,
  depth~ : Int32 = policy.depth,
) -> Policy {
  { deterministic, depth, }
}

///|
/// Read a KRSON document and turn it into a `Json` tree.
///
/// KRSON is a real, schema-first binary serialization format (Rust core
/// `krson-core`, JS SDK `krson-js`). Its schema-first form carries a 4-byte
/// schema id and needs the originating schema runtime to interpret — a thing the
/// shared `Json` tree here cannot host, and one that is not portable on its own.
/// This package therefore implements the **self-describing schemaless** record,
/// which the SDK also emits (`encode`/`decode` with no schema): magic `KR`, a
/// version and flags byte, a schema id of `0`, a string-interning table (every
/// object key and string value is written once and referred to by index), then
/// the value tree.
///
/// WARNING ON FIDELITY — the authoritative `SPEC.md` referenced by the KRSON
/// project was not publicly retrievable at the time of writing, and the authors
/// state the wire format "may still change between minor versions". This codec
/// follows the primitives the SDK documents (magic `KR`, a length-prefixed
/// string table, varint + zigzag integers, big-endian `float64`, and the value
/// tags below). It is a genuine, self-consistent encoder/decoder of that
/// subset; byte-exact interop with upstream KRSON is best-effort.
///
/// The value model is JSON-native, so this reader never produces the `$bytes`,
/// `$tag`, `$map`, `$simple` or `$undefined` markers the other binary packages
/// in this family use: a KRSON document has no byte strings, tags, maps with
/// non-string keys, `undefined` or simple values to carry.
pub fn load(
  input : BytesView,
  policy~ : Policy = policy,
) -> Json raise @moonjson.Refused {
  let r : Reader = { src: input, i: 0, }
  if r.rem() < 8 {
    raise @moonjson.Short(at=0)
  }
  if r.byte() != 0x4B || r.byte() != 0x52 {
    raise @moonjson.Bad(at=0, why="not a KRSON buffer (missing the 'KR' magic)")
  }
  let version = r.byte()
  if version != 1 {
    raise @moonjson.Bad(at=2, why="unsupported KRSON version")
  }
  let _flags = r.byte()
  r.uint32_le()
  let count = r.varint()
  let table : Array[String] = []
  for _ in 0..<count.to_int() {
    let len = r.varint().to_int()
    let bytes = r.take(len)
    let s = @utf8.decode(bytes) catch {
      _ =>
        raise @moonjson.Bad(
          at=r.i,
          why="a string-table entry that is not UTF-8",
        )
    }
    table.push(s)
  }
  let value = r.value(0, table, policy)
  if r.i < r.src.length() {
    raise @moonjson.Extra(at=r.i)
  }
  value
}

///|
/// Write a `Json` tree as a KRSON schemaless document.
///
/// See [`load`] for the design note and the fidelity warning. The writer builds
/// the string-interning table from every object key and string value in the
/// tree, writes the `KR` header with a zero schema id, the table, then the value
/// tree using the tags below. A value the format cannot carry as JSON — there is
/// none in the JSON-native model — would raise [`@moonjson.Unwritable`].
///
/// | tag | tree |
/// |:--|:--|
/// | `0x00` | `null` |
/// | `0x01` + `0/1` | `true` / `false` |
/// | `0x02` + zigzag varint | an integer |
/// | `0x03` + 8 bytes (big-endian) | a `float64` |
/// | `0x04` + varint | a string, by index into the string table |
/// | `0x05` + varint + items | an array |
/// | `0x06` + varint + (key-index, value) pairs | an object |
pub fn dump(
  value : Json,
  policy~ : Policy = policy,
) -> Bytes raise @moonjson.Refused {
  let table : Array[String] = []
  let mut seen : Map[String, Int32] = Map([])
  collect(value, table, seen)
  if policy.deterministic {
    // A stable byte image needs a stable table too: sort the strings and rebuild
    // the index so the same set of strings always gets the same indices.
    table.sort()
    let rebuilt : Map[String, Int32] = Map([])
    for i, s in table {
      rebuilt[s] = i
    }
    seen = rebuilt
  }
  let buf = Buffer()
  buf.write_byte(0x4B) // 'K'
  buf.write_byte(0x52) // 'R'
  buf.write_byte(1) // version
  buf.write_byte(0) // flags
  write_uint32_le(buf, 0) // schema id 0 == schemaless
  write_varint(buf, table.length().to_uint64())
  for s in table {
    let bytes = @utf8.encode(s[:])
    write_varint(buf, bytes.length().to_uint64())
    buf.write_bytes(bytes[:])
  }
  write_value(buf, value, seen, policy)
  buf.to_bytes()
}

///|
/// A cursor over the bytes of one document.
priv struct Reader {
  src : BytesView
  mut i : Int32
}

///|
fn Reader::rem(self : Reader) -> Int32 {
  self.src.length() - self.i
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
/// Consume the 4-byte little-endian schema id. The schemaless form always
/// writes `0`; this reader simply advances past it (a non-zero id names a schema
/// this package does not host, which is out of scope for the schemaless subset).
fn Reader::uint32_le(self : Reader) -> Unit raise @moonjson.Refused {
  let _ = self.byte()
  let _ = self.byte()
  let _ = self.byte()
  let _ = self.byte()
}

///|
/// An unsigned LEB128 varint.
fn Reader::varint(self : Reader) -> UInt64 raise @moonjson.Refused {
  let mut result = 0UL
  let mut shift = 0
  while shift < 64 {
    let b = self.byte()
    result = result | ((b & 0x7F).to_uint64() << shift)
    if (b & 0x80) == 0 {
      return result
    }
    shift += 7
  }
  raise @moonjson.Bad(at=self.i, why="a varint longer than 64 bits")
}

///|
/// `n` bytes from here, refusing a length that runs past the end.
fn Reader::take(self : Reader, n : Int32) -> BytesView raise @moonjson.Refused {
  if n < 0 || self.i + n > self.src.length() {
    raise @moonjson.Short(at=self.src.length())
  }
  let view = self.src[self.i:self.i + n]
  self.i += n
  view
}

///|
fn Reader::uint64_be(self : Reader) -> UInt64 raise @moonjson.Refused {
  let mut v = 0UL
  for _ in 0..<8 {
    v = (v << 8) | self.byte().to_uint64()
  }
  v
}

///|
fn Reader::value(
  self : Reader,
  depth : Int32,
  table : Array[String],
  policy : Policy,
) -> Json raise @moonjson.Refused {
  if depth > policy.depth {
    raise @moonjson.Bad(at=self.i, why="nested deeper than \{policy.depth}")
  }
  let tag = self.byte()
  match tag {
    0x00 => Json::null()
    0x01 => {
      let b = self.byte()
      if b == 0 {
        Json::boolean(false)
      } else {
        Json::boolean(true)
      }
    }
    0x02 => {
      let i = unzigzag(self.varint())
      Json::number(i.to_double(), repr=i.to_string())
    }
    0x03 => Json::number(self.uint64_be().reinterpret_as_double())
    0x04 => {
      let idx = self.varint().to_int()
      if idx < 0 || idx >= table.length() {
        raise @moonjson.Bad(
          at=self.i,
          why="a string index past the end of the table",
        )
      }
      Json::string(table[idx])
    }
    0x05 => {
      let len = self.varint().to_int()
      if len < 0 || len > 0x7FFF_FFFF {
        raise @moonjson.Bad(at=self.i, why="an array longer than this machine")
      }
      let items : Array[Json] = []
      for _ in 0..<len {
        items.push(self.value(depth + 1, table, policy))
      }
      Json::array(items)
    }
    0x06 => {
      let len = self.varint().to_int()
      if len < 0 || len > 0x7FFF_FFFF {
        raise @moonjson.Bad(at=self.i, why="an object longer than this machine")
      }
      let out : Map[String, Json] = Map([])
      for _ in 0..<len {
        let idx = self.varint().to_int()
        if idx < 0 || idx >= table.length() {
          raise @moonjson.Bad(
            at=self.i,
            why="a string index past the end of the table",
          )
        }
        let key = table[idx]
        let val = self.value(depth + 1, table, policy)
        out[key] = val
      }
      Json::object(out)
    }
    _ => raise @moonjson.Bad(at=self.i - 1, why="an unknown KRSON value tag")
  }
}

///|
/// Gather every string (object key and string value) into the interning table so
/// the writer can refer to each by index.
fn collect(
  value : Json,
  table : Array[String],
  seen : Map[String, Int32],
) -> Unit {
  match value {
    String(s) => intern(s, table, seen)
    Array(items) =>
      for it in items {
        collect(it, table, seen)
      }
    Object(members) =>
      for k, v in members {
        intern(k, table, seen)
        collect(v, table, seen)
      }
    _ => ()
  }
}

///|
fn intern(s : String, table : Array[String], seen : Map[String, Int32]) -> Unit {
  match seen.get(s) {
    Some(_) => ()
    None => {
      seen[s] = table.length()
      table.push(s)
    }
  }
}

///|
/// Write an unsigned LEB128 varint.
fn write_varint(buf : Buffer, v : UInt64) -> Unit {
  let mut v = v
  while true {
    let b = (v & 0x7F).to_byte()
    v = v >> 7
    if v == 0UL {
      buf.write_byte(b)
      break
    } else {
      buf.write_byte((b.to_uint() | 0x80).to_byte())
    }
  }
}

///|
fn write_uint32_le(buf : Buffer, v : UInt32) -> Unit {
  buf.write_byte((v & 0xFF).to_byte())
  buf.write_byte(((v >> 8) & 0xFF).to_byte())
  buf.write_byte(((v >> 16) & 0xFF).to_byte())
  buf.write_byte(((v >> 24) & 0xFF).to_byte())
}

///|
/// A `float64` in big-endian, the one quirk the KRSON documentation calls out.
fn write_float(buf : Buffer, n : Double) -> Unit {
  let bits = n.reinterpret_as_uint64()
  buf.write_byte((bits >> 56).to_byte())
  buf.write_byte((bits >> 48).to_byte())
  buf.write_byte((bits >> 40).to_byte())
  buf.write_byte((bits >> 32).to_byte())
  buf.write_byte((bits >> 24).to_byte())
  buf.write_byte((bits >> 16).to_byte())
  buf.write_byte((bits >> 8).to_byte())
  buf.write_byte(bits.to_byte())
}

///|
/// Map a `Json` integer (kept as text so it cannot be rounded) into a signed
/// 64-bit integer as zigzag varint.
fn zigzag(n : Int64) -> UInt64 {
  let z = (n << 1) ^ (n >> 63)
  z.reinterpret_as_uint64()
}

///|
fn unzigzag(u : UInt64) -> Int64 {
  ((u >> 1) ^ (0UL - (u & 1UL))).reinterpret_as_int64()
}

///|
fn is_integer_text(text : String) -> Bool {
  if text.length() == 0 {
    return false
  }
  for i in 0..<text.length() {
    let c = text.at(i).to_int()
    if i == 0 && c == 0x2D && text.length() > 1 {
      continue
    }
    if c < 0x30 || c > 0x39 {
      return false
    }
  }
  true
}

///|
/// Parse a decimal integer literal into an `Int64`, or `None` past 64 bits.
fn parse_i64(text : String) -> Int64? {
  if text.length() == 0 {
    return None
  }
  let neg = text.at(0).to_int() == 0x2D
  let start = if neg { 1 } else { 0 }
  if start >= text.length() {
    return None
  }
  let mut v = 0L
  for i in start..<text.length() {
    let c = text.at(i).to_int()
    if c < 0x30 || c > 0x39 {
      return None
    }
    let d = (c - 0x30).to_int64()
    if v > (9223372036854775807L - d) / 10L {
      return None
    }
    v = v * 10L + d
  }
  Some(if neg { -v } else { v })
}

///|
fn write_value(
  buf : Buffer,
  value : Json,
  table : Map[String, Int32],
  policy : Policy,
) -> Unit raise @moonjson.Refused {
  match value {
    Null => buf.write_byte(0x00)
    True => {
      buf.write_byte(0x01)
      buf.write_byte(1)
    }
    False => {
      buf.write_byte(0x01)
      buf.write_byte(0)
    }
    Number(n, repr~) => write_number(buf, n, repr)
    String(s) =>
      match table.get(s) {
        Some(idx) => {
          buf.write_byte(0x04)
          write_varint(buf, idx.to_uint64())
        }
        None =>
          raise @moonjson.Unwritable(why="a string missing from the table")
      }
    Array(items) => {
      buf.write_byte(0x05)
      write_varint(buf, items.length().to_uint64())
      for it in items {
        write_value(buf, it, table, policy)
      }
    }
    Object(members) => {
      buf.write_byte(0x06)
      write_varint(buf, members.length().to_uint64())
      let names : Array[String] = []
      for k, _ in members {
        names.push(k)
      }
      if policy.deterministic {
        names.sort()
      }
      for k in names {
        match table.get(k) {
          Some(idx) => write_varint(buf, idx.to_uint64())
          None => raise @moonjson.Unwritable(why="a key missing from the table")
        }
        write_value(buf, members.get(k).unwrap(), table, policy)
      }
    }
  }
}

///|
fn write_number(buf : Buffer, n : Double, repr : String?) -> Unit {
  match repr {
    Some(text) => {
      if is_integer_text(text) {
        match parse_i64(text) {
          Some(i) => {
            buf.write_byte(0x02)
            write_varint(buf, zigzag(i))
            return
          }
          None => ()
        }
      }
      buf.write_byte(0x03)
      write_float(buf, n)
    }
    None =>
      if !(n.is_nan() || n.is_inf()) &&
        n == @double.trunc(n) &&
        n >= -9223372036854775808.0 &&
        n < 9223372036854775808.0 {
        buf.write_byte(0x02)
        write_varint(buf, zigzag(n.to_int64()))
      } else {
        buf.write_byte(0x03)
        write_float(buf, n)
      }
  }
}
