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
/// The argument that follows a head byte: the length, the value or the tag.
fn Reader::arg(self : Reader, info : Int32) -> UInt64 raise @moonjson.Refused {
  if info < 24 {
    info.to_uint64()
  } else if info == 24 {
    self.uint(1)
  } else if info == 25 {
    self.uint(2)
  } else if info == 26 {
    self.uint(4)
  } else if info == 27 {
    self.uint(8)
  } else {
    raise @moonjson.Bad(
      at=self.i - 1,
      why="additional information \{info} is reserved",
    )
  }
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
  let major = head >> 5
  let info = head & 0x1F
  match major {
    0 => {
      let n = self.arg(info)
      integer(n, false)
    }
    1 => {
      let n = self.arg(info)
      integer(n, true)
    }
    2 => self.bytes(info)
    3 => self.text(info)
    4 => self.array(info, depth)
    5 => self.map(info, depth)
    6 => self.tag(info, depth)
    _ => self.simple(info)
  }
}

///|
/// An integer, kept as text when a double would round it. A CBOR document can
/// carry any 64-bit integer; JSON's number is an IEEE-754 double, so above
/// 2^53 the tree keeps the digits and `@json.dumps` writes them back unchanged.
fn integer(n : UInt64, negative : Bool) -> Json {
  if negative {
    if n < 9007199254740992UL {
      Json::number(-n.to_double() - 1.0)
    } else {
      let text = StringBuilder()
      text.write_char('-')
      text.write_string(increment(n.to_string()))
      Json::number(-n.to_double() - 1.0, repr=text.to_string())
    }
  } else if n < 9007199254740992UL {
    Json::number(n.to_double())
  } else {
    Json::number(n.to_double(), repr=n.to_string())
  }
}

///|
/// The decimal text of `n + 1`, for a negative integer below -2^53, which is
/// one more than the argument CBOR stores.
fn increment(n : String) -> String {
  let mut i = n.length() - 1
  while i >= 0 && n.at(i).to_int() == 0x39 {
    i -= 1
  }
  let out = StringBuilder()
  if i < 0 {
    out.write_char('1')
    for _ in 0..<n.length() {
      out.write_char('0')
    }
    return out.to_string()
  }
  out.write_view(n[:i])
  out.write_char((n.at(i).to_int() + 1).unsafe_to_char())
  for _ in 0..<(n.length() - i - 1) {
    out.write_char('0')
  }
  out.to_string()
}

///|
fn Reader::bytes(self : Reader, info : Int32) -> Json raise @moonjson.Refused {
  let out = Buffer()
  if info == 31 {
    // Indefinite: chunks until a break. Each chunk must itself be definite, as
    // RFC 8949 §3.2.3 requires — a chunk of a chunk would be a length with no
    // meaning.
    while self.peek() != 0xFF {
      if self.peek() < 0 {
        raise @moonjson.Short(at=self.i)
      }
      let head = self.byte()
      if head >> 5 != 2 || (head & 0x1F) == 31 {
        raise @moonjson.Bad(at=self.i - 1, why="a chunk is not a byte string")
      }
      let length = self.arg(head & 0x1F)
      out.write_bytes(self.take(length))
    }
    self.i += 1
  } else {
    let length = self.arg(info)
    out.write_bytes(self.take(length))
  }
  Json::object({ "$bytes": @hex.encode(out.to_bytes()[:]) })
}

///|
/// `length` bytes from here, refusing a length that runs past the end.
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
fn Reader::text(self : Reader, info : Int32) -> Json raise @moonjson.Refused {
  let chunks = Buffer()
  if info == 31 {
    while self.peek() != 0xFF {
      if self.peek() < 0 {
        raise @moonjson.Short(at=self.i)
      }
      let head = self.byte()
      if head >> 5 != 3 || (head & 0x1F) == 31 {
        raise @moonjson.Bad(at=self.i - 1, why="a chunk is not a text string")
      }
      let length = self.arg(head & 0x1F)
      chunks.write_bytes(self.take(length))
    }
    self.i += 1
  } else {
    let length = self.arg(info)
    chunks.write_bytes(self.take(length))
  }
  let text = @utf8.decode(chunks.to_bytes()) catch {
    _ => raise @moonjson.Bad(at=self.i, why="a text string that is not UTF-8")
  }
  Json::string(text)
}

///|
fn Reader::array(
  self : Reader,
  info : Int32,
  depth : Int32,
) -> Json raise @moonjson.Refused {
  let items : Array[Json] = []
  if info == 31 {
    while self.peek() != 0xFF {
      items.push(self.value(depth + 1))
    }
    self.i += 1
  } else {
    let count = self.arg(info)
    if count.to_int() < 0 {
      raise @moonjson.Bad(at=self.i, why="an array longer than this machine")
    }
    for _ in 0..<count.to_int() {
      items.push(self.value(depth + 1))
    }
  }
  Json::array(items)
}

///|
fn Reader::map(
  self : Reader,
  info : Int32,
  depth : Int32,
) -> Json raise @moonjson.Refused {
  let keys : Array[Json] = []
  let values : Array[Json] = []
  let mut strings = true
  if info == 31 {
    while self.peek() != 0xFF {
      let key = self.value(depth + 1)
      if key is String(_) {

      } else {
        strings = false
      }
      keys.push(key)
      values.push(self.value(depth + 1))
    }
    self.i += 1
  } else {
    let count = self.arg(info)
    if count > 0x7FFF_FFFFUL {
      raise @moonjson.Bad(at=self.i, why="a map longer than this machine")
    }
    for _ in 0..<count.to_int() {
      let key = self.value(depth + 1)
      if key is String(_) {

      } else {
        strings = false
      }
      keys.push(key)
      values.push(self.value(depth + 1))
    }
  }
  if !strings {
    // One key that is not a string is enough: an object has only string keys,
    // so the whole map goes into the `$map` form rather than half of a document
    // meaning one thing and half another.
    let pairs : Array[Json] = []
    for i, key in keys {
      pairs.push(Json::array([key, values[i]]))
    }
    return Json::object({ "$map": Json::array(pairs) })
  }
  let out : Map[String, Json] = Map([])
  for i, key in keys {
    if key is String(name) {
      out[name] = values[i]
    }
  }
  Json::object(out)
}

///|
fn Reader::tag(
  self : Reader,
  info : Int32,
  depth : Int32,
) -> Json raise @moonjson.Refused {
  let number = self.arg(info)
  // The two bignum tags are the one place a tag changes the value rather than
  // wrapping it: a JSON reader that met `2(h'…')` as a tag object could not do
  // arithmetic with it, and the number it stands for is the whole point.
  if number == 2UL || number == 3UL {
    let held = self.value(depth + 1)
    match held {
      Object(members) =>
        if members.get("$bytes") is Some(String(hex)) {
          let magnitude = @hex.decode(hex[:]) catch {
            _ => raise @moonjson.Bad(at=self.i, why="a bignum that is not hex")
          }
          let text = bytes_decimal(magnitude[:])
          return if number == 2UL {
            Json::number(
              @string.parse_double(text) catch {
                _ => 0.0
              },
              repr=text,
            )
          } else {
            let negative = StringBuilder()
            negative.write_char('-')
            negative.write_string(increment(text))
            Json::number(
              -(@string.parse_double(text) catch { _ => 0.0 }) - 1.0,
              repr=negative.to_string(),
            )
          }
        }
      _ => ()
    }
    return Json::object({
      "$tag": Json::number(number.to_double()),
      "value": held,
    })
  }
  let held = self.value(depth + 1)
  Json::object({ "$tag": Json::number(number.to_double()), "value": held })
}

///|
/// A float keeps a text that says it is one, so writing the tree back out gives
/// a float again. `1.0` and `1` are the same number to JSON and different
/// values to CBOR.
fn as_float(n : Double) -> Json {
  if n.is_nan() || n.is_inf() {
    return Json::number(n)
  }
  let text = n.to_string()
  if n == 0.0 {
    let negative = n.reinterpret_as_uint64() == 0x8000_0000_0000_0000UL
    Json::number(n, repr=if negative { "-0.0" } else { "0.0" })
  } else if text.contains(".") || text.contains("e") {
    Json::number(n, repr=text)
  } else {
    Json::number(n, repr="\{text}.0")
  }
}

///|
fn Reader::simple(self : Reader, info : Int32) -> Json raise @moonjson.Refused {
  match info {
    20 => Json::boolean(false)
    21 => Json::boolean(true)
    22 => Json::null()
    23 => Json::object({ "$undefined": Json::boolean(true) })
    24 => Json::object({ "$simple": Json::number(self.uint(1).to_double()) })
    25 => as_float(half_to_double(self.uint(2).to_uint()))
    26 => as_float(single_to_double(self.uint(4).to_uint()))
    27 => as_float(self.uint(8).reinterpret_as_double())
    31 =>
      // A break outside an indefinite-length item, which is not a value.
      raise @moonjson.Bad(at=self.i - 1, why="a break with nothing to end")
    _ => Json::object({ "$simple": Json::number(info.to_double()) })
  }
}
