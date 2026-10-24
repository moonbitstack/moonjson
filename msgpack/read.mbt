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
fn Reader::peek(self : Reader) -> Int32 {
  if self.i < self.src.length() {
    self.src.at(self.i).to_int()
  } else {
    -1
  }
}

///|
fn Reader::uint(self : Reader, n : Int32) -> UInt64 raise @moonjson.Refused {
  if self.i + n > self.src.length() {
    raise @moonjson.Short(at=self.src.length())
  }
  let mut v = 0UL
  for _ in 0..<n {
    v = (v << 8) | self.byte().to_uint64()
  }
  v
}

///|
fn Reader::take(
  self : Reader,
  length : UInt64,
) -> BytesView raise @moonjson.Refused {
  if length > 0x7FFF_FFFFUL {
    raise @moonjson.Bad(at=self.i, why="a length past the end of any document")
  }
  let n = length.to_int()
  if self.i + n > self.src.length() {
    raise @moonjson.Short(at=self.src.length())
  }
  let view = self.src[self.i:self.i + n]
  self.i += n
  view
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
  // The four fixed-width families first: they are one byte of head and no more.
  if head <= 0x7F {
    return Json::number(head.to_double())
  }
  if head >= 0xE0 {
    return Json::number((head - 0x100).to_double())
  }
  if (head & 0xF0) == 0x80 {
    return self.map(head & 0x0F, depth)
  }
  if (head & 0xF0) == 0x90 {
    return self.array(head & 0x0F, depth)
  }
  if (head & 0xE0) == 0xA0 {
    return self.text((head & 0x1F).to_uint64())
  }
  match head {
    0xC0 => Json::null()
    0xC2 => Json::boolean(false)
    0xC3 => Json::boolean(true)
    0xC4 => self.binary(self.uint(1))
    0xC5 => self.binary(self.uint(2))
    0xC6 => self.binary(self.uint(4))
    0xC7 => self.extension(self.uint(1), self.uint(1))
    0xC8 => self.extension(self.uint(1), self.uint(2))
    0xC9 => self.extension(self.uint(1), self.uint(4))
    0xCA => as_float(single_to_double(self.uint(4).to_uint()))
    0xCB => as_float(self.uint(8).reinterpret_as_double())
    0xCC => Json::number(self.uint(1).to_double())
    0xCD => Json::number(self.uint(2).to_double())
    0xCE => Json::number(self.uint(4).to_double())
    0xCF => integer(self.uint(8), 64)
    0xD0 => integer(self.uint(1), 8)
    0xD1 => integer(self.uint(2), 16)
    0xD2 => integer(self.uint(4), 32)
    0xD3 => integer(self.uint(8), 64)
    0xD4 => self.extension(1UL, self.uint(1))
    0xD5 => self.extension(2UL, self.uint(1))
    0xD6 => self.extension(4UL, self.uint(1))
    0xD7 => self.extension(8UL, self.uint(1))
    0xD8 => self.extension(16UL, self.uint(1))
    0xD9 => self.text(self.uint(1))
    0xDA => self.text(self.uint(2))
    0xDB => self.text(self.uint(4))
    0xDC => self.array(self.uint(2).to_int(), depth)
    0xDD => self.array(self.uint(4).to_int(), depth)
    0xDE => self.map(self.uint(2).to_int(), depth)
    0xDF => self.map(self.uint(4).to_int(), depth)
    _ => raise @moonjson.Bad(at=self.i - 1, why="0xc1 is not a value")
  }
}

///|
/// An integer read as two's complement: the width says how many bits are
/// significant, and the top one says the sign.
fn integer(raw : UInt64, width : Int32) -> Json {
  let negative = ((raw >> (width - 1)) & 1UL) == 1UL
  let magnitude = if !negative {
    raw
  } else if width == 64 {
    0UL - raw
  } else {
    (1UL << width) - raw
  }
  if !negative && magnitude < 9007199254740992UL {
    return Json::number(magnitude.to_double())
  }
  let text = magnitude.to_string()
  if negative {
    let out = StringBuilder()
    out.write_char('-')
    out.write_string(text)
    Json::number(-magnitude.to_double(), repr=out.to_string())
  } else {
    Json::number(magnitude.to_double(), repr=text)
  }
}

///|
fn Reader::binary(
  self : Reader,
  length : UInt64,
) -> Json raise @moonjson.Refused {
  Json::object({ "$bytes": @hex.encode(self.take(length)) })
}

///|
/// An extension type. MessagePack's own timestamp is ext type -1; it is kept as
/// it is rather than interpreted, because the tree has no date and a marker
/// that names the type is lossless where a guess would not be.
fn Reader::extension(
  self : Reader,
  length : UInt64,
  kind : UInt64,
) -> Json raise @moonjson.Refused {
  let data = @hex.encode(self.take(length))
  Json::object({
    "$ext": Json::number(kind.to_double()),
    "data": Json::string(data),
  })
}

///|
fn Reader::text(self : Reader, length : UInt64) -> Json raise @moonjson.Refused {
  let bytes = self.take(length)
  let text = @utf8.decode(bytes) catch {
    _ => raise @moonjson.Bad(at=self.i, why="a string that is not UTF-8")
  }
  Json::string(text)
}

///|
fn Reader::array(
  self : Reader,
  count : Int32,
  depth : Int32,
) -> Json raise @moonjson.Refused {
  if count < 0 {
    raise @moonjson.Bad(at=self.i, why="an array longer than this machine")
  }
  let items : Array[Json] = []
  for _ in 0..<count {
    items.push(self.value(depth + 1))
  }
  Json::array(items)
}

///|
fn Reader::map(
  self : Reader,
  count : Int32,
  depth : Int32,
) -> Json raise @moonjson.Refused {
  if count < 0 {
    raise @moonjson.Bad(at=self.i, why="a map longer than this machine")
  }
  let out : Map[String, Json] = Map([])
  for _ in 0..<count {
    let key = self.value(depth + 1)
    let value = self.value(depth + 1)
    // MessagePack allows any key; an object has only string keys. A key that is
    // not a string is refused rather than stringified, because the other side
    // would read the string back as a key of a different type.
    match key {
      String(name) => out[name] = value
      _ =>
        raise @moonjson.Bad(
          at=self.i,
          why="a map key that is not a string has no place in a tree",
        )
    }
  }
  Json::object(out)
}
