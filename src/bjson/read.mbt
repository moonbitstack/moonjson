// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A cursor over the bytes of one document.
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
/// `n` bytes, least significant first — bjson is little-endian throughout.
fn Reader::le(self : Reader, n : Int32) -> UInt64 raise @moonjson.Refused {
  let mut v = 0UL
  for k in 0..<n {
    let b = self.byte().to_uint64()
    v = v | (b << (k * 8))
  }
  v
}

///|
/// `n` bytes as a signed integer, for `n` of one, two, four or eight.
fn Reader::signed_le(self : Reader, n : Int32) -> Int64 raise @moonjson.Refused {
  let mut v = 0L
  for k in 0..<n {
    let b = self.byte().to_int64()
    v = v | (b << (k * 8))
  }
  let bits = n * 8
  let signbit = 1L << (bits - 1)
  if (v & signbit) != 0L {
    v = v - (1L << bits)
  }
  v
}

///|
/// A byte length, in the one/two/four-byte form the container tag implies.
fn Reader::len_by_width(
  self : Reader,
  width : Int32,
) -> Int32 raise @moonjson.Refused {
  match width {
    1 => self.byte()
    2 => {
      let lo = self.byte()
      let hi = self.byte()
      (hi << 8) | lo
    }
    4 => self.le(4).to_int()
    _ => raise @moonjson.Bad(at=self.i, why="a bad length width")
  }
}

///|
fn Reader::string(
  self : Reader,
  width : Int32,
) -> String raise @moonjson.Refused {
  let length = self.len_by_width(width)
  let bytes = self.take(length)
  @utf8.decode(bytes[:]) catch {
    _ =>
      raise @moonjson.Bad(at=self.i - length, why="a string that is not UTF-8")
  }
}

///|
fn Reader::key(self : Reader) -> String raise @moonjson.Refused {
  let length = self.le(4).to_int()
  let bytes = self.take(length)
  @utf8.decode(bytes[:]) catch {
    _ => raise @moonjson.Bad(at=self.i - length, why="a key that is not UTF-8")
  }
}

///|
fn Reader::value(self : Reader, depth : Int32) -> Json raise @moonjson.Refused {
  let tag = self.byte()
  match tag {
    0x00 => Json::null()
    0x01 => Json::boolean(false)
    0x02 => Json::boolean(true)
    0x03 => Json::number(self.signed_le(1).to_double())
    0x04 => Json::number(self.signed_le(2).to_double())
    0x05 => Json::number(self.signed_le(4).to_double())
    0x06 => {
      let v = self.signed_le(8)
      if v >= -9007199254740992L && v <= 9007199254740992L {
        Json::number(v.to_double())
      } else {
        Json::number(v.to_double(), repr=v.to_string())
      }
    }
    0x07 => Json::number(self.le(8).reinterpret_as_double())
    0x08 | 0x09 | 0x0A => {
      let width = tag - 0x07
      Json::string(self.string(width))
    }
    0x0B | 0x0C | 0x0D => {
      let width = tag - 0x0A
      let length = self.len_by_width(width)
      let bytes = self.take(length)
      Json::object({ "$bytes": Json::string(@hex.encode(bytes[:])) })
    }
    0x0E => self.array(depth)
    0x0F => self.object(depth)
    0x10 => Json::object({ "$undefined": Json::boolean(true) })
    _ => raise @moonjson.Bad(at=self.i - 1, why="unknown bjson type tag \{tag}")
  }
}

///|
fn Reader::array(self : Reader, depth : Int32) -> Json raise @moonjson.Refused {
  if depth > self.policy.depth {
    raise @moonjson.Bad(
      at=self.i,
      why="nested deeper than \{self.policy.depth}",
    )
  }
  let count = self.le(4).to_int()
  let items : Array[Json] = []
  for _ in 0..<count {
    items.push(self.value(depth + 1))
  }
  Json::array(items)
}

///|
fn Reader::object(self : Reader, depth : Int32) -> Json raise @moonjson.Refused {
  if depth > self.policy.depth {
    raise @moonjson.Bad(
      at=self.i,
      why="nested deeper than \{self.policy.depth}",
    )
  }
  let count = self.le(4).to_int()
  let members : Map[String, Json] = Map([])
  for _ in 0..<count {
    let k = self.key()
    members[k] = self.value(depth + 1)
  }
  Json::object(members)
}
