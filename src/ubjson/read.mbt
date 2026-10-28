// Universal Binary JSON (UBJSON) — https://ubjson.org/
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
/// The byte under the cursor without consuming it, or `-1` at the end.
fn Reader::peek(self : Reader) -> Int32 {
  if self.i < self.src.length() {
    self.src.at(self.i).to_int()
  } else {
    -1
  }
}

///|
/// `n` bytes, most significant first.
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
/// `n` bytes from here, refusing a length that runs past the end.
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
/// The argument that follows `S` or `H`: a non-negative integer, itself written
/// with a type marker like every other value.
fn Reader::count(self : Reader, depth : Int32) -> Int32 raise @moonjson.Refused {
  let len = self.value(depth)
  match len {
    Number(n, ..) =>
      if !n.is_nan() && !n.is_inf() && n >= 0.0 && n == @double.trunc(n) {
        let v = n.to_int()
        if v >= 0 {
          return v
        }
      }
    _ => ()
  }
  raise @moonjson.Bad(
    at=self.i,
    why="a length that is not a non-negative integer",
  )
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
  match head {
    0x5A => Json::null() // Z
    0x54 => Json::boolean(true) // T
    0x46 => Json::boolean(false) // F
    0x4E => self.value(depth) // N: a no-op; read the next value
    0x69 => self.int(head, depth) // i
    0x55 => self.int(head, depth) // U
    0x49 => self.int(head, depth) // I
    0x75 => self.int(head, depth) // u
    0x6C => self.int(head, depth) // l
    0x6D => self.int(head, depth) // m
    0x4C => self.int(head, depth) // L
    0x4D => self.int(head, depth) // M
    0x64 => as_float(single_to_double(self.uint(4).to_uint())) // d
    0x44 => as_float(self.uint(8).reinterpret_as_double()) // D
    0x48 => self.high(depth) // H
    0x53 => self.string(depth) // S
    0x5B => self.array(depth) // [
    0x7B => self.object(depth) // {
    0x5D => raise @moonjson.Bad(at=self.i - 1, why="a ']' with no array open")
    0x7D => raise @moonjson.Bad(at=self.i - 1, why="a '}' with no object open")
    _ =>
      raise @moonjson.Bad(
        at=self.i - 1,
        why="a marker this reader does not know",
      )
  }
}

///|
/// A fixed-width integer, signed or unsigned, kept as text so round-tripping
/// preserves `1` and `1.0` — and every other width — as different things.
fn Reader::int(
  self : Reader,
  marker : Int32,
  _depth : Int32,
) -> Json raise @moonjson.Refused {
  match marker {
    0x69 => { // i int8
      let b = self.byte()
      let s = if b >= 128 { (b - 256).to_int64() } else { b.to_int64() }
      Json::number(s.to_double(), repr=s.to_string())
    }
    0x55 => { // U uint8
      let b = self.byte()
      Json::number(b.to_double(), repr=b.to_string())
    }
    0x49 => { // I int16
      let raw = self.uint(2)
      let s = if raw >= 0x8000UL {
        raw.reinterpret_as_int64() - 0x10000L
      } else {
        raw.reinterpret_as_int64()
      }
      Json::number(s.to_double(), repr=s.to_string())
    }
    0x75 => { // u uint16
      let raw = self.uint(2)
      Json::number(raw.to_double(), repr=raw.to_string())
    }
    0x6C => { // l int32
      let raw = self.uint(4)
      let s = if raw >= 0x80000000UL {
        raw.reinterpret_as_int64() - 0x100000000L
      } else {
        raw.reinterpret_as_int64()
      }
      Json::number(s.to_double(), repr=s.to_string())
    }
    0x6D => { // m uint32
      let raw = self.uint(4)
      Json::number(raw.to_double(), repr=raw.to_string())
    }
    0x4C => { // L int64
      let raw = self.uint(8)
      let s = raw.reinterpret_as_int64()
      Json::number(s.to_double(), repr=s.to_string())
    }
    0x4D => { // M uint64
      let raw = self.uint(8)
      Json::number(raw.to_double(), repr=raw.to_string())
    }
    _ =>
      raise @moonjson.Bad(
        at=self.i - 1,
        why="an integer marker this reader does not know",
      )
  }
}

///|
/// A high-precision number: decimal digits carried as text, because UBJSON has
/// no wider integer and no decimal type of its own. The text is kept verbatim so
/// it writes back unchanged.
fn Reader::high(self : Reader, depth : Int32) -> Json raise @moonjson.Refused {
  let n = self.count(depth)
  let bytes = self.take(n.to_uint64())
  let text = @utf8.decode(bytes) catch {
    _ =>
      raise @moonjson.Bad(
        at=self.i,
        why="a high-precision number that is not UTF-8",
      )
  }
  let d = @string.parse_double(text[:]) catch { _ => 0.0 }
  Json::number(d, repr=text)
}

///|
/// A float keeps a text that says it is one, so writing the tree back out gives
/// a float again. `1.0` and `1` are the same number to JSON and different values
/// to UBJSON.
fn as_float(n : Double) -> Json {
  if n.is_nan() || n.is_inf() {
    return Json::number(n)
  }
  let text = n.to_string()
  if n == 0.0 {
    let negative = n.reinterpret_as_uint64() == 0x8000_0000_0000_0000UL
    Json::number(n, repr=if negative { "-0.0" } else { "0.0" })
  } else if text.contains(".") || text.contains("e") || text.contains("E") {
    Json::number(n, repr=text)
  } else {
    Json::number(n, repr=text + ".0")
  }
}

///|
fn Reader::string(self : Reader, depth : Int32) -> Json raise @moonjson.Refused {
  let n = self.count(depth)
  let bytes = self.take(n.to_uint64())
  let decoded = @utf8.decode(bytes) catch {
    _ => raise @moonjson.Bad(at=self.i, why="a string that is not UTF-8")
  }
  Json::string(decoded)
}

///|
fn Reader::array(self : Reader, depth : Int32) -> Json raise @moonjson.Refused {
  let items : Array[Json] = []
  while true {
    let b = self.peek()
    if b < 0 {
      raise @moonjson.Short(at=self.i)
    }
    if b == 0x5D {
      self.i += 1
      break
    }
    items.push(self.value(depth + 1))
  }
  Json::array(items)
}

///|
/// A member is a string key — itself a `S` value — and then a value. UBJSON
/// keys are always strings, so a key that is not one is refused rather than
/// stringified.
fn Reader::object(self : Reader, depth : Int32) -> Json raise @moonjson.Refused {
  let out : Map[String, Json] = Map([])
  while true {
    let b = self.peek()
    if b < 0 {
      raise @moonjson.Short(at=self.i)
    }
    if b == 0x7D {
      self.i += 1
      break
    }
    let key = self.value(depth + 1)
    match key {
      String(name) => {
        let value = self.value(depth + 1)
        out[name] = value
      }
      _ =>
        raise @moonjson.Bad(at=self.i, why="an object key that is not a string")
    }
  }
  Json::object(out)
}

///|
/// IEEE-754 single precision, done from the bit pattern, because the core
/// library has no Float-to-Double conversion and UBJSON's `d` marker needs one.
fn single_to_double(bits : UInt32) -> Double {
  let sign = (bits >> 31).to_uint64() << 63
  let mut exponent = ((bits >> 23) & 0xFF).reinterpret_as_int()
  let mut mantissa = bits & 0x7F_FFFF
  if exponent == 0xFF {
    let payload = if mantissa == 0 { 0UL } else { mantissa.to_uint64() << 29 }
    return (sign | 0x7FF0_0000_0000_0000UL | payload).reinterpret_as_double()
  }
  if exponent == 0 {
    if mantissa == 0 {
      return sign.reinterpret_as_double()
    }
    while (mantissa & 0x80_0000) == 0 {
      mantissa = mantissa << 1
      exponent -= 1
    }
    exponent += 1
    mantissa = mantissa & 0x7F_FFFF
  }
  let wide = (exponent - 127 + 1023).to_uint64()
  (sign | (wide << 52) | (mantissa.to_uint64() << 29)).reinterpret_as_double()
}
