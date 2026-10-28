// Smile binary data format — https://github.com/FasterXML/smile-format-specification
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

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
/// The four magic bytes, or this is not a Smile document at all.
fn Reader::header(self : Reader) -> Unit raise @moonjson.Refused {
  if self.i + 4 > self.src.length() {
    raise @moonjson.Short(at=self.src.length())
  }
  let want : Array[Int32] = [0x3A, 0x29, 0x0A, 0x00]
  for k in 0..<4 {
    if self.src.at(self.i).to_int() != want[k] {
      raise @moonjson.Bad(at=self.i, why="a header this reader does not know")
    }
    self.i += 1
  }
}

///|
/// A non-negative length as a 7-bit little-endian variable-length integer with
/// the high bit of every byte but the last set as a continuation marker.
fn Reader::vint(self : Reader) -> Int32 raise @moonjson.Refused {
  let mut shift = 0
  let mut value = 0L
  while true {
    let b = self.byte()
    value = value | ((b & 0x7F).to_int64() << shift)
    if (b & 0x80) == 0 {
      break
    }
    shift = shift + 7
    if shift > 35 {
      raise @moonjson.Bad(at=self.i, why="a length too long to hold")
    }
  }
  if value > 0x7FFF_FFFFL {
    raise @moonjson.Bad(at=self.i, why="a length past the end of any document")
  }
  value.to_int()
}

///|
/// One value. The first byte decides what it is; see `write.mbt` for the
/// matching encoder and the comment there on which markers are emitted.
fn Reader::value(self : Reader, depth : Int32) -> Json raise @moonjson.Refused {
  if depth > self.policy.depth {
    raise @moonjson.Bad(
      at=self.i,
      why="nested deeper than \{self.policy.depth}",
    )
  }
  let b = self.byte()
  match b {
    0x00 =>
      raise @moonjson.Bad(
        at=self.i - 1,
        why="an end marker where a value was expected",
      )
    0x22 => self.string()
    0x24 => self.binary()
    0x27 => self.int32()
    0x28 => self.int64()
    0x2A =>
      raise @moonjson.Bad(
        at=self.i - 1,
        why="a 32-bit float, which this reader does not decode",
      )
    0x2B => self.float64()
    0x2D => Json::null()
    0x2E => Json::boolean(false)
    0x2F => Json::boolean(true)
    0x38 => self.array(depth)
    0x3B => self.object(depth)
    0x39 =>
      raise @moonjson.Bad(
        at=self.i - 1,
        why="an array end where a value was expected",
      )
    0x3C =>
      raise @moonjson.Bad(
        at=self.i - 1,
        why="an object end where a value was expected",
      )
    // `0x26` is small int -16; `0x30..0x37` are small ints -6..1; `0x3A` is
    // small int 4; `0x3D..0x45` are small ints 7..15. Bytes `0x27..0x2C` are
    // the larger numeric/float markers, `0x2D..0x2F` the literals and
    // `0x38/0x39` and `0x3B/0x3C` the array/object controls, so none of those
    // are small ints.
    _ if b == 0x26 ||
      (b >= 0x30 && b <= 0x37) ||
      b == 0x3A ||
      (b >= 0x3D && b <= 0x45) => {
      let v = b - 0x36
      Json::number(v.to_double(), repr=v.to_string())
    }
    // Back-references (0x21/0x23/0x25) and shared-string/short-key forms are
    // not produced by this writer and not decoded here.
    0x29 =>
      raise @moonjson.Bad(
        at=self.i - 1,
        why="a big integer, which this reader does not decode",
      )
    0x2C =>
      raise @moonjson.Bad(
        at=self.i - 1,
        why="a big decimal, which this reader does not decode",
      )
    _ =>
      raise @moonjson.Bad(
        at=self.i - 1,
        why="a marker this reader does not know",
      )
  }
}

///|
fn Reader::string(self : Reader) -> Json raise @moonjson.Refused {
  let len = self.vint()
  let bytes = self.take(len)
  let text = @utf8.decode(bytes) catch {
    _ => raise @moonjson.Bad(at=self.i, why="a text string that is not UTF-8")
  }
  Json::string(text)
}

///|
/// A Smile binary becomes the `$bytes` marker, because JSON has no byte string
/// of its own.
fn Reader::binary(self : Reader) -> Json raise @moonjson.Refused {
  let len = self.vint()
  let bytes = self.take(len)
  Json::object({ "$bytes": Json::string(@hex.encode(bytes[:])) })
}

///|
fn Reader::int32(self : Reader) -> Json raise @moonjson.Refused {
  let mut raw = 0UL
  for _ in 0..<4 {
    raw = (raw << 8) | self.byte().to_uint64()
  }
  let z = raw.reinterpret_as_int64()
  let v = (z >> 1) ^ -(z & 1)
  Json::number(v.to_double(), repr=v.to_string())
}

///|
fn Reader::int64(self : Reader) -> Json raise @moonjson.Refused {
  let mut raw = 0UL
  for _ in 0..<8 {
    raw = (raw << 8) | self.byte().to_uint64()
  }
  let z = raw.reinterpret_as_int64()
  let v = (z >> 1) ^ -(z & 1)
  Json::number(v.to_double(), repr=v.to_string())
}

///|
/// The eight-byte big-endian double stored as is, with a text kept.
fn Reader::float64(self : Reader) -> Json raise @moonjson.Refused {
  let mut bits = 0UL
  for _ in 0..<8 {
    bits = (bits << 8) | self.byte().to_uint64()
  }
  float_bits(bits.reinterpret_as_double())
}

///|
/// Keep a double's text so that writing the tree back out gives a float again:
/// `1.0` and `1` are the same number to JSON and different values to Smile.
fn float_bits(n : Double) -> Json {
  let text = n.to_string()
  let repr = if text.contains(".") || text.contains("e") || text.contains("E") {
    text
  } else {
    text + ".0"
  }
  Json::number(n, repr~)
}

///|
fn Reader::array(self : Reader, depth : Int32) -> Json raise @moonjson.Refused {
  let len = self.vint()
  let items : Array[Json] = []
  let mut k = 0
  while k < len {
    items.push(self.value(depth + 1))
    k = k + 1
  }
  if self.byte() != 0x39 {
    raise @moonjson.Bad(at=self.i - 1, why="an array not closed by 0x39")
  }
  Json::array(items)
}

///|
/// A member is a non-shared string key (this writer always uses `0x22`) and
/// then a value, closed by `0x3C`.
fn Reader::object(self : Reader, depth : Int32) -> Json raise @moonjson.Refused {
  let len = self.vint()
  let out : Map[String, Json] = Map([])
  let mut k = 0
  while k < len {
    let key_byte = self.byte()
    if key_byte != 0x22 {
      raise @moonjson.Bad(
        at=self.i - 1,
        why="a member name that is not a string",
      )
    }
    let klen = self.vint()
    let kbytes = self.take(klen)
    let key = @utf8.decode(kbytes) catch {
      _ => raise @moonjson.Bad(at=self.i, why="a member name that is not UTF-8")
    }
    let value = self.value(depth + 1)
    out[key] = value
    k = k + 1
  }
  if self.byte() != 0x3C {
    raise @moonjson.Bad(at=self.i - 1, why="an object not closed by 0x3C")
  }
  Json::object(out)
}
