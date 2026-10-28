// Smile binary data format — https://github.com/FasterXML/smile-format-specification
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A non-negative length as a 7-bit little-endian variable-length integer with
/// the high bit of every byte but the last set as a continuation marker.
fn put_vint(buf : Buffer, v : Int32) -> Unit {
  let mut n = v
  while true {
    if n < 128 {
      buf.write_byte(n.to_byte())
      break
    } else {
      buf.write_byte(((n & 127) | 128).to_byte())
      n = n >> 7
    }
  }
}

///|
fn write(
  buf : Buffer,
  value : Json,
  policy : Policy,
) -> Unit raise @moonjson.Refused {
  match value {
    Null => buf.write_byte(0x2D)
    True => buf.write_byte(0x2F)
    False => buf.write_byte(0x2E)
    Number(n, repr~) => number(buf, n, repr)
    String(s) => string(buf, s[:])
    Array(items) => {
      buf.write_byte(0x38)
      put_vint(buf, items.length())
      for item in items {
        write(buf, item, policy)
      }
      buf.write_byte(0x39)
    }
    Object(members) => object(buf, members, policy)
  }
}

///|
fn string(buf : Buffer, s : StringView) -> Unit {
  buf.write_byte(0x22)
  let bytes = @utf8.encode(s)
  put_vint(buf, bytes.length())
  buf.write_bytes(bytes[:])
}

///|
/// A number: an integer when the tree says it is one, a float when it says it
/// is one. The text the tree keeps decides, because `1` and `1.0` are the same
/// number to JSON and different values to Smile.
fn number(buf : Buffer, n : Double, repr : String?) -> Unit {
  match repr {
    Some(text) =>
      if is_integer_text(text) {
        integer_text(buf, text)
      } else {
        float(buf, n)
      }
    None =>
      if !n.is_nan() && !n.is_inf() && n == @double.trunc(n) {
        integer_double(buf, n)
      } else {
        float(buf, n)
      }
  }
}

///|
/// An object is either the `$bytes` marker `load` documents, or a map whose
/// keys are strings — written in bytewise order of the name so the encoding of
/// a given tree is the same every time.
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
        buf.write_byte(0x24)
        put_vint(buf, bytes.length())
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
  buf.write_byte(0x3B)
  put_vint(buf, names.length())
  for name in names {
    buf.write_byte(0x22)
    let kbytes = @utf8.encode(name[:])
    put_vint(buf, kbytes.length())
    buf.write_bytes(kbytes[:])
    write(buf, members.get(name).unwrap(), policy)
  }
  buf.write_byte(0x3C)
}

///|
/// An integer: a small int when it fits in the inline byte, else a 32-bit or
/// 64-bit zigzag int, else a double (keeping `repr` so a huge integer keeps its
/// exact text). The inline small-int byte `0x36 + v` would collide with a
/// reserved marker for a handful of values, which fall back to the 32-bit form.
fn integer_text(buf : Buffer, text : String) -> Unit {
  match parse_int64(text) {
    Some(v) => put_integer(buf, v)
    None => {
      let d = @string.parse_double(text[:]) catch { _ => 0.0 }
      float(buf, d)
    }
  }
}

///|
fn integer_double(buf : Buffer, n : Double) -> Unit {
  if n >= -9223372036854775808.0 && n <= 9223372036854775807.0 {
    put_integer(buf, n.to_int64())
  } else {
    float(buf, n)
  }
}

///|
fn put_integer(buf : Buffer, v : Int64) -> Unit {
  if v >= -16 && v <= 15 {
    let b = 0x36 + v.to_int()
    if b == 0x27 ||
      b == 0x28 ||
      b == 0x29 ||
      b == 0x2A ||
      b == 0x2B ||
      b == 0x2C ||
      b == 0x2D ||
      b == 0x2E ||
      b == 0x2F ||
      b == 0x38 ||
      b == 0x39 ||
      b == 0x3B ||
      b == 0x3C {
      put_int32(buf, v)
    } else {
      buf.write_byte(b.to_byte())
    }
  } else if v >= -2147483648L && v <= 2147483647L {
    put_int32(buf, v)
  } else {
    put_int64(buf, v)
  }
}

///|
/// A 32-bit zigzag int, big-endian.
fn put_int32(buf : Buffer, v : Int64) -> Unit {
  buf.write_byte(0x27)
  let z = ((v << 1) ^ (if v < 0L { -1L } else { 0L })) & 0xFFFF_FFFFL
  buf.write_byte(((z >> 24) & 0xFFL).to_int().to_byte())
  buf.write_byte(((z >> 16) & 0xFFL).to_int().to_byte())
  buf.write_byte(((z >> 8) & 0xFFL).to_int().to_byte())
  buf.write_byte((z & 0xFFL).to_int().to_byte())
}

///|
/// A 64-bit zigzag int, big-endian.
fn put_int64(buf : Buffer, v : Int64) -> Unit {
  buf.write_byte(0x28)
  let z = ((v << 1) ^ (if v < 0L { -1L } else { 0L })) & 0xFFFF_FFFF_FFFF_FFFFL
  buf.write_byte(((z >> 56) & 0xFFL).to_int().to_byte())
  buf.write_byte(((z >> 48) & 0xFFL).to_int().to_byte())
  buf.write_byte(((z >> 40) & 0xFFL).to_int().to_byte())
  buf.write_byte(((z >> 32) & 0xFFL).to_int().to_byte())
  buf.write_byte(((z >> 24) & 0xFFL).to_int().to_byte())
  buf.write_byte(((z >> 16) & 0xFFL).to_int().to_byte())
  buf.write_byte(((z >> 8) & 0xFFL).to_int().to_byte())
  buf.write_byte((z & 0xFFL).to_int().to_byte())
}

///|
/// A float kept as the eight big-endian bytes of its IEEE-754 bits.
fn float(buf : Buffer, n : Double) -> Unit {
  buf.write_byte(0x2B)
  let bits = n.reinterpret_as_uint64()
  buf.write_byte(((bits >> 56) & 0xFFUL).to_int().to_byte())
  buf.write_byte(((bits >> 48) & 0xFFUL).to_int().to_byte())
  buf.write_byte(((bits >> 40) & 0xFFUL).to_int().to_byte())
  buf.write_byte(((bits >> 32) & 0xFFUL).to_int().to_byte())
  buf.write_byte(((bits >> 24) & 0xFFUL).to_int().to_byte())
  buf.write_byte(((bits >> 16) & 0xFFUL).to_int().to_byte())
  buf.write_byte(((bits >> 8) & 0xFFUL).to_int().to_byte())
  buf.write_byte((bits & 0xFFUL).to_int().to_byte())
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
/// The magnitude of an integer written as digits, when it fits in 64 bits.
fn parse_int64(text : String) -> Int64? {
  if text.length() == 0 {
    return None
  }
  let mut i = 0
  let mut negative = false
  if text.at(0).to_int() == 0x2D {
    negative = true
    i = 1
    if text.length() == 1 {
      return None
    }
  }
  let mut value = 0L
  while i < text.length() {
    let c = text.at(i).to_int()
    if c < 0x30 || c > 0x39 {
      return None
    }
    let digit = (c - 0x30).to_int64()
    if value > (9223372036854775807L - digit) / 10L {
      return None
    }
    value = value * 10L + digit
    i += 1
  }
  if negative {
    if value > 9223372036854775807L {
      return None
    }
    Some(-value)
  } else {
    if value > 9223372036854775807L {
      return None
    }
    Some(value)
  }
}
