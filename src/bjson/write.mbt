// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A sixteen-bit little-endian length.
fn write_u16(buf : Buffer, v : Int32) -> Unit {
  buf.write_byte((v & 0xFF).to_byte())
  buf.write_byte(((v >> 8) & 0xFF).to_byte())
}

///|
/// An eight-byte little-endian signed integer.
fn write_i64(buf : Buffer, v : Int64) -> Unit {
  for k in 0..<8 {
    buf.write_byte(((v >> (k * 8)) & 0xFFL).to_int().to_byte())
  }
}

///|
/// A string, in the shortest of the three length-prefixed forms.
fn write_string(buf : Buffer, s : String) -> Unit {
  let bytes = @utf8.encode(s[:])
  let len = bytes.length()
  if len <= 0xFF {
    buf.write_byte(0x08)
    buf.write_byte(len.to_byte())
  } else if len <= 0xFFFF {
    buf.write_byte(0x09)
    write_u16(buf, len)
  } else {
    buf.write_byte(0x0A)
    buf.write_int_le(len)
  }
  buf.write_bytes(bytes[:])
}

///|
/// An object key: always a four-byte little-endian length, then UTF-8 bytes.
fn write_key(buf : Buffer, s : String) -> Unit {
  let bytes = @utf8.encode(s[:])
  buf.write_int_le(bytes.length())
  buf.write_bytes(bytes[:])
}

///|
/// A number, either in the narrowest integer width that holds it or as a double.
fn write_number(buf : Buffer, n : Double) -> Unit {
  if n.is_nan() || n.is_inf() || n != @double.trunc(n) {
    buf.write_byte(0x07)
    buf.write_double_le(n)
    return
  }
  let v = n.to_int64()
  if v >= -128L && v <= 127L {
    buf.write_byte(0x03)
    buf.write_byte((v.to_int() & 0xFF).to_byte())
  } else if v >= -32768L && v <= 32767L {
    buf.write_byte(0x04)
    write_u16(buf, v.to_int())
  } else if v >= -2147483648L && v <= 2147483647L {
    buf.write_byte(0x05)
    buf.write_int_le(v.to_int())
  } else {
    buf.write_byte(0x06)
    write_i64(buf, v)
  }
}

///|
/// The markers `load` documents, written back as the types they stand for.
/// Answers whether it wrote the value: an object that is not a marker is a plain
/// object, which the caller writes.
fn write_marker(
  buf : Buffer,
  members : Map[String, Json],
) -> Bool raise @moonjson.Refused {
  if members.length() == 1 {
    if members.get("$bytes") is Some(String(hex)) {
      let bytes = @hex.decode(hex[:]) catch {
        _ => raise @moonjson.Unwritable(why="\"$bytes\" wants lowercase hex")
      }
      let len = bytes.length()
      if len <= 0xFF {
        buf.write_byte(0x0B)
        buf.write_byte(len.to_byte())
      } else if len <= 0xFFFF {
        buf.write_byte(0x0C)
        write_u16(buf, len)
      } else {
        buf.write_byte(0x0D)
        buf.write_int_le(len)
      }
      buf.write_bytes(bytes[:])
      return true
    }
    if members.get("$undefined") is Some(True) {
      buf.write_byte(0x10)
      return true
    }
  }
  false
}

///|
fn write(
  buf : Buffer,
  value : Json,
  policy : Policy,
  depth : Int32,
) -> Unit raise @moonjson.Refused {
  if depth > policy.depth {
    raise @moonjson.Unwritable(why="nested deeper than \{policy.depth}")
  }
  match value {
    Null => buf.write_byte(0x00)
    True => buf.write_byte(0x02)
    False => buf.write_byte(0x01)
    Number(n, ..) => write_number(buf, n)
    String(s) => write_string(buf, s)
    Array(items) => {
      buf.write_byte(0x0E)
      buf.write_int_le(items.length())
      for item in items {
        write(buf, item, policy, depth + 1)
      }
    }
    Object(members) =>
      if !write_marker(buf, members) {
        buf.write_byte(0x0F)
        buf.write_int_le(members.length())
        for k, v in members {
          write_key(buf, k)
          write(buf, v, policy, depth + 1)
        }
      }
  }
}
