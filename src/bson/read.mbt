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
/// `n` bytes, least significant first — BSON is little-endian throughout.
fn Reader::le(self : Reader, n : Int32) -> UInt64 raise @moonjson.Refused {
  if self.i + n > self.src.length() {
    raise @moonjson.Short(at=self.src.length())
  }
  let mut v = 0UL
  for k in 0..<n {
    v = v | (self.byte().to_uint64() << (k * 8))
  }
  v
}

///|
fn Reader::int32(self : Reader) -> Int32 raise @moonjson.Refused {
  self.le(4).to_uint().reinterpret_as_int()
}

///|
fn Reader::cstring(self : Reader) -> String raise @moonjson.Refused {
  let start = self.i
  while self.i < self.src.length() && self.src.at(self.i).to_int() != 0 {
    self.i += 1
  }
  if self.i >= self.src.length() {
    raise @moonjson.Short(at=self.src.length())
  }
  let text = @utf8.decode(self.src[start:self.i]) catch {
    _ => raise @moonjson.Bad(at=start, why="a name that is not UTF-8")
  }
  self.i += 1
  text
}

///|
fn Reader::text(self : Reader) -> String raise @moonjson.Refused {
  let length = self.int32()
  if length < 1 {
    raise @moonjson.Bad(
      at=self.i - 4,
      why="a string shorter than its terminator",
    )
  }
  let bytes = self.take(length)
  if bytes.at(length - 1).to_int() != 0 {
    raise @moonjson.Bad(at=self.i, why="a string without its terminator")
  }
  @utf8.decode(bytes[:length - 1]) catch {
    _ =>
      raise @moonjson.Bad(at=self.i - length, why="a string that is not UTF-8")
  }
}

///|
fn Reader::document(
  self : Reader,
  depth : Int32,
) -> Json raise @moonjson.Refused {
  if depth > self.policy.depth {
    raise @moonjson.Bad(
      at=self.i,
      why="nested deeper than \{self.policy.depth}",
    )
  }
  let start = self.i
  let total = self.int32()
  if total < 5 {
    raise @moonjson.Bad(at=start, why="a document shorter than its own header")
  }
  let end = start + total
  if end > self.src.length() {
    raise @moonjson.Short(at=self.src.length())
  }
  let out : Map[String, Json] = Map([])
  let mut open = true
  while open {
    let kind = self.byte()
    if kind == 0 {
      open = false
    } else {
      let name = self.cstring()
      out[name] = self.element(kind, depth)
    }
  }
  if self.i != end {
    // The header said where the document ends and the terminators said
    // something else. One of them is wrong and there is no way to tell which.
    raise @moonjson.Bad(at=self.i, why="a document whose length is not its own")
  }
  Json::object(out)
}

///|
fn Reader::array(self : Reader, depth : Int32) -> Json raise @moonjson.Refused {
  if depth > self.policy.depth {
    raise @moonjson.Bad(
      at=self.i,
      why="nested deeper than \{self.policy.depth}",
    )
  }
  let start = self.i
  let total = self.int32()
  if total < 5 {
    raise @moonjson.Bad(at=start, why="an array shorter than its own header")
  }
  let end = start + total
  if end > self.src.length() {
    raise @moonjson.Short(at=self.src.length())
  }
  let items : Array[Json] = []
  let mut open = true
  while open {
    let kind = self.byte()
    if kind == 0 {
      open = false
    } else {
      // The names are "0", "1", … by the specification; the order in the file
      // is the order of the elements, so the names are not read.
      self.cstring() |> ignore
      items.push(self.element(kind, depth))
    }
  }
  if self.i != end {
    raise @moonjson.Bad(at=self.i, why="an array whose length is not its own")
  }
  Json::array(items)
}

///|
fn Reader::element(
  self : Reader,
  kind : Int32,
  depth : Int32,
) -> Json raise @moonjson.Refused {
  match kind {
    0x01 => as_float(self.le(8).reinterpret_as_double())
    0x02 => Json::string(self.text())
    0x03 => self.document(depth + 1)
    0x04 => self.array(depth + 1)
    0x05 => {
      let length = self.int32()
      let subtype = self.byte()
      let bytes = @hex.encode(self.take(length))
      if subtype == 0 {
        Json::object({ "$bytes": Json::string(bytes) })
      } else {
        Json::object({
          "$binary": Json::object({
            "kind": Json::number(subtype.to_double()),
            "data": Json::string(bytes),
          }),
        })
      }
    }
    0x06 => Json::object({ "$undefined": Json::boolean(true) })
    0x07 => Json::object({ "$oid": Json::string(@hex.encode(self.take(12))) })
    0x08 => Json::boolean(self.byte() != 0)
    0x09 => {
      let millis = self.le(8).reinterpret_as_int64()
      Json::object({
        "$date": Json::number(millis.to_double(), repr=millis.to_string()),
      })
    }
    0x0A => Json::null()
    0x0B => {
      let pattern = self.cstring()
      let options = self.cstring()
      Json::object({
        "$regex": Json::string(pattern),
        "options": Json::string(options),
      })
    }
    0x0C => {
      let ns = self.text()
      let oid = @hex.encode(self.take(12))
      Json::object({
        "$dbpointer": Json::object({
          "ns": Json::string(ns),
          "oid": Json::string(oid),
        }),
      })
    }
    0x0D => Json::object({ "$code": Json::string(self.text()) })
    0x0E => Json::object({ "$symbol": Json::string(self.text()) })
    0x0F => {
      let start = self.i
      let total = self.int32()
      let code = self.text()
      let scope = self.document(depth + 1)
      if self.i != start + total {
        raise @moonjson.Bad(
          at=self.i,
          why="a scoped function whose length is not its own",
        )
      }
      Json::object({ "$code": Json::string(code), "$scope": scope })
    }
    0x10 => {
      let value = self.int32()
      Json::number(value.to_double())
    }
    0x11 => {
      let raw = self.le(8)
      let increment = (raw & 0xFFFF_FFFFUL).to_double()
      let seconds = (raw >> 32).to_double()
      Json::object({
        "$timestamp": Json::object({
          "t": Json::number(seconds),
          "i": Json::number(increment),
        }),
      })
    }
    0x12 => {
      let value = self.le(8).reinterpret_as_int64()
      if value > 9007199254740992L || value < -9007199254740992L {
        Json::number(value.to_double(), repr=value.to_string())
      } else {
        Json::number(value.to_double())
      }
    }
    0x13 =>
      Json::object({ "$decimal128": Json::string(@hex.encode(self.take(16))) })
    0xFF => Json::object({ "$minKey": Json::boolean(true) })
    0x7F => Json::object({ "$maxKey": Json::boolean(true) })
    _ =>
      raise @moonjson.Bad(at=self.i - 1, why="element type \{kind} is not one")
  }
}

///|
/// A float keeps a text that says it is one, so writing the tree back out gives
/// a double again.
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
