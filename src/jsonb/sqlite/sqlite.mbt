// SQLite jsonb — binary JSON:
// https://www.sqlite.org/jsonb.html
//
// SQLite's jsonb is JSON's data model with one addition, a byte string, so a
// SQLite blob reads into the same tree the rest of this family already
// understands, and what the tree cannot hold outright is carried in the markers
// documented on `load` — so a blob read here is written as a blob again, and
// the byte strings of CBOR, MessagePack and BSON are one thing in the tree.
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How SQLite jsonb is read and written.
///
/// The byte layout itself is fixed by SQLite; the one knob is how deep a
/// document may nest before it is refused, because a document of a hundred
/// thousand open brackets is a denial of service rather than a document.
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
/// What a tree becomes when a SQLite jsonb value has no JSON counterpart.
///
/// JSON has no byte string, so a SQLite blob is carried as an object with one
/// reserved member:
///
/// | jsonb | tree |
/// |:--|:--|
/// | `blob` | `{"$bytes": "0102"}` — lowercase hex, no separators |
///
/// SQLite jsonb is JSON's data model plus that one addition, so a blob reads
/// into the same tree the rest of this family already understands, and what the
/// tree cannot hold outright is carried in the markers documented here. A blob
/// read here is written as a blob again, and the byte strings of CBOR,
/// MessagePack and BSON are the one `$bytes` in the tree.
///
/// An object that happens to have a single `$bytes` member as its *data* has to
/// be written through the `$map` form, because the marker is reserved — the
/// same bargain every other package in this family makes.
pub fn load(
  input : BytesView,
  policy~ : Policy = policy,
) -> Json raise @moonjson.Refused {
  let r : Reader = { src: input, policy, i: 0, }
  let value = r.value(0)
  if r.i < input.length() {
    raise @moonjson.Extra(at=r.i)
  }
  value
}

///|
/// Write a tree as SQLite jsonb.
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
/// The content length a head byte promises: the high nibble directly, or a
/// 1/2/4/8-byte big-endian field that follows when the high nibble is 0xC/0xD/
/// 0xE/0xF.
fn Reader::length(self : Reader, high : Int32) -> Int32 raise @moonjson.Refused {
  if high <= 11 {
    return high
  }
  if high == 0xC {
    return self.byte()
  }
  if high == 0xD {
    return (self.byte() << 8) | self.byte()
  }
  if high == 0xE {
    let mut v = 0
    for _ in 0..<4 {
      v = (v << 8) | self.byte()
    }
    return v
  }
  // 0xF: eight bytes, longer than any document this reader accepts.
  let mut v = 0L
  for _ in 0..<8 {
    v = (v << 8) | self.byte().to_int64()
  }
  if v > 0x7FFF_FFFFL {
    raise @moonjson.Bad(at=self.i, why="a length past the end of any document")
  }
  v.to_int()
}

///|
fn Reader::value(self : Reader, depth : Int32) -> Json raise @moonjson.Refused {
  if depth > self.policy.depth {
    raise @moonjson.Bad(
      at=self.i,
      why="nested deeper than \{self.policy.depth}",
    )
  }
  let head = self.byte()
  let high = head >> 4
  let low = head & 0x0F
  match low {
    0 => Json::null()
    1 => Json::boolean(true)
    2 => Json::boolean(false)
    3 => self.decimal(high)
    5 => self.decimal(high)
    6 => self.blob(high)
    7 => self.text(high)
    0xB => self.array(high, depth)
    0xC => self.object(high, depth)
    _ =>
      raise @moonjson.Bad(
        at=self.i - 1,
        why="a jsonb type this reader does not know",
      )
  }
}

///|
/// An integer or a float, kept as text so round-tripping preserves `1` and
/// `1.0` as different things — the same bargain CBOR makes.
fn Reader::decimal(self : Reader, high : Int32) -> Json raise @moonjson.Refused {
  let n = self.length(high)
  let bytes = self.take(n)
  let text = @utf8.decode(bytes) catch {
    _ => raise @moonjson.Bad(at=self.i, why="a number that is not UTF-8")
  }
  let d = @string.parse_double(text[:]) catch { _ => 0.0 }
  Json::number(d, repr=text)
}

///|
fn Reader::blob(self : Reader, high : Int32) -> Json raise @moonjson.Refused {
  let n = self.length(high)
  let bytes = self.take(n)
  Json::object({ "$bytes": @hex.encode(bytes[:]) })
}

///|
fn Reader::text(self : Reader, high : Int32) -> Json raise @moonjson.Refused {
  let n = self.length(high)
  let bytes = self.take(n)
  let decoded = @utf8.decode(bytes) catch {
    _ => raise @moonjson.Bad(at=self.i, why="a text string that is not UTF-8")
  }
  Json::string(decoded)
}

///|
fn Reader::array(
  self : Reader,
  high : Int32,
  depth : Int32,
) -> Json raise @moonjson.Refused {
  let n = self.length(high)
  let end = self.i + n
  let items : Array[Json] = []
  while self.i < end {
    items.push(self.value(depth + 1))
  }
  if self.i != end {
    raise @moonjson.Bad(at=self.i, why="an array shorter than its length says")
  }
  Json::array(items)
}

///|
/// A member is a name — itself a TEXT node — and then a value node.
fn Reader::object(
  self : Reader,
  high : Int32,
  depth : Int32,
) -> Json raise @moonjson.Refused {
  let n = self.length(high)
  let end = self.i + n
  let out : Map[String, Json] = Map([])
  while self.i < end {
    let name = self.value(depth + 1)
    match name {
      String(key) => {
        let value = self.value(depth + 1)
        out[key] = value
      }
      _ => raise @moonjson.Bad(at=self.i, why="a member name that is not text")
    }
  }
  if self.i != end {
    raise @moonjson.Bad(at=self.i, why="an object shorter than its length says")
  }
  Json::object(out)
}

// ───────────────────────────── writing ─────────────────────────────

///|
/// A head byte and its length, in the shortest form that holds the length: the
/// length in the high nibble when it fits, else a 1/2/4-byte size field chosen
/// by the 0xC/0xD/0xE high nibble. The low nibble is the type.
fn head(buf : Buffer, type_ : Int32, length : Int32) -> Unit {
  if length <= 11 {
    buf.write_byte(((length << 4) | type_).to_byte())
  } else if length <= 0xFF {
    buf.write_byte(((0xC << 4) | type_).to_byte())
    buf.write_byte(length.to_byte())
  } else if length <= 0xFFFF {
    buf.write_byte(((0xD << 4) | type_).to_byte())
    buf.write_uint16_be(length.to_uint16())
  } else {
    buf.write_byte(((0xE << 4) | type_).to_byte())
    buf.write_uint_be(length.reinterpret_as_uint())
  }
}

///|
fn write(
  buf : Buffer,
  value : Json,
  policy : Policy,
) -> Unit raise @moonjson.Refused {
  match value {
    Null => buf.write_byte(0x00)
    True => buf.write_byte(0x01)
    False => buf.write_byte(0x02)
    Number(n, repr~) => number(buf, n, repr)
    String(s) => text(buf, s[:])
    Array(items) => {
      let body = Buffer()
      for item in items {
        write(body, item, policy)
      }
      head(buf, 0xB, body.length())
      buf.write_bytes(body.to_bytes()[:])
    }
    Object(members) => object(buf, members, policy)
  }
}

///|
fn text(buf : Buffer, s : StringView) -> Unit {
  let bytes = @utf8.encode(s)
  head(buf, 7, bytes.length())
  buf.write_bytes(bytes[:])
}

///|
/// An object is either the `$bytes` marker `load` documents, or a map whose
/// keys are strings — written in code-point order, because that is the order
/// the tree remembers them in and the order the reader will see them again.
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
        head(buf, 6, bytes.length())
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
  let body = Buffer()
  for name in names {
    text(body, name[:])
    write(body, members.get(name).unwrap(), policy)
  }
  head(buf, 0xC, body.length())
  buf.write_bytes(body.to_bytes()[:])
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

///|
/// A number: an integer when the tree says it is one, a float when it says it
/// is one. The text the tree keeps decides, because `1` and `1.0` are the same
/// number to JSON and different values to SQLite jsonb.
fn number(buf : Buffer, n : Double, repr : String?) -> Unit {
  match repr {
    Some(text) =>
      if is_integer_text(text) {
        let bytes = @utf8.encode(text[:])
        head(buf, 3, bytes.length())
        buf.write_bytes(bytes[:])
      } else {
        let bytes = @utf8.encode(text[:])
        head(buf, 5, bytes.length())
        buf.write_bytes(bytes[:])
      }
    None =>
      if !n.is_nan() && !n.is_inf() && n == @double.trunc(n) {
        let text = n.to_string()
        let bytes = @utf8.encode(text[:])
        head(buf, 3, bytes.length())
        buf.write_bytes(bytes[:])
      } else {
        let text = float_text(n)
        let bytes = @utf8.encode(text[:])
        head(buf, 5, bytes.length())
        buf.write_bytes(bytes[:])
      }
  }
}

///|
/// The decimal text of a float that has no text of its own, keeping a decimal
/// point so it reads back as a float rather than an integer.
fn float_text(n : Double) -> String {
  if n == @double.trunc(n) {
    let text = n.to_string()
    if text.contains(".") || text.contains("e") || text.contains("E") {
      text
    } else {
      text + ".0"
    }
  } else {
    n.to_string()
  }
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
