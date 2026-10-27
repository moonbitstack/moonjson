// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn write(
  buf : Buffer,
  value : Json,
  policy : Policy,
) -> Unit raise @moonjson.Refused {
  match value {
    Null => buf.write_byte(0xC0)
    True => buf.write_byte(0xC3)
    False => buf.write_byte(0xC2)
    Number(n, repr~) => number(buf, n, repr, policy)
    String(s) => text(buf, s[:])
    Array(items) => {
      let count = items.length()
      if count < 16 {
        buf.write_byte((0x90 + count).to_byte())
      } else if count <= 0xFFFF {
        buf.write_byte(0xDC)
        buf.write_uint16_be(count.to_uint16())
      } else {
        buf.write_byte(0xDD)
        buf.write_uint_be(count.reinterpret_as_uint())
      }
      for item in items {
        write(buf, item, policy)
      }
    }
    Object(members) => object(buf, members, policy)
  }
}

///|
fn text(buf : Buffer, s : StringView) -> Unit {
  let bytes = @utf8.encode(s)
  let count = bytes.length()
  if count < 32 {
    buf.write_byte((0xA0 + count).to_byte())
  } else if count <= 0xFF {
    buf.write_byte(0xD9)
    buf.write_byte(count.to_byte())
  } else if count <= 0xFFFF {
    buf.write_byte(0xDA)
    buf.write_uint16_be(count.to_uint16())
  } else {
    buf.write_byte(0xDB)
    buf.write_uint_be(count.reinterpret_as_uint())
  }
  buf.write_bytes(bytes[:])
}

///|
fn binary(buf : Buffer, bytes : Bytes) -> Unit {
  let count = bytes.length()
  if count <= 0xFF {
    buf.write_byte(0xC4)
    buf.write_byte(count.to_byte())
  } else if count <= 0xFFFF {
    buf.write_byte(0xC5)
    buf.write_uint16_be(count.to_uint16())
  } else {
    buf.write_byte(0xC6)
    buf.write_uint_be(count.reinterpret_as_uint())
  }
  buf.write_bytes(bytes[:])
}

///|
fn extension(buf : Buffer, kind : Int32, bytes : Bytes) -> Unit {
  let count = bytes.length()
  let fixed = count == 1 ||
    count == 2 ||
    count == 4 ||
    count == 8 ||
    count == 16
  if fixed && kind >= 0 && kind <= 0x7F {
    buf.write_byte(
      (0xD4 +
      (if count == 1 {
        0
      } else if count == 2 {
        1
      } else if count == 4 {
        2
      } else if count == 8 {
        3
      } else {
        4
      })).to_byte(),
    )
  } else if count <= 0xFF {
    buf.write_byte(0xC7)
    buf.write_byte(count.to_byte())
  } else if count <= 0xFFFF {
    buf.write_byte(0xC8)
    buf.write_uint16_be(count.to_uint16())
  } else {
    buf.write_byte(0xC9)
    buf.write_uint_be(count.reinterpret_as_uint())
  }
  buf.write_byte(kind.to_byte())
  buf.write_bytes(bytes[:])
}

///|
fn object(
  buf : Buffer,
  members : Map[String, Json],
  policy : Policy,
) -> Unit raise @moonjson.Refused {
  if members.length() == 1 {
    if members.get("$bytes") is Some(String(hex)) {
      let bytes = @hex.decode(hex[:]) catch {
        _ => raise @moonjson.Unwritable(why="\"$bytes\" wants lowercase hex")
      }
      binary(buf, bytes)
      return
    }
  }
  if members.length() == 2 {
    if members.get("$ext") is Some(Number(kind, ..)) &&
      members.get("data") is Some(String(hex)) &&
      kind == @double.trunc(kind) &&
      kind >= -128.0 &&
      kind <= 127.0 {
      let bytes = @hex.decode(hex[:]) catch {
        _ => raise @moonjson.Unwritable(why="\"data\" wants lowercase hex")
      }
      extension(buf, kind.to_int(), bytes)
      return
    }
  }
  let count = members.length()
  if count < 16 {
    buf.write_byte((0x80 + count).to_byte())
  } else if count <= 0xFFFF {
    buf.write_byte(0xDE)
    buf.write_uint16_be(count.to_uint16())
  } else {
    buf.write_byte(0xDF)
    buf.write_uint_be(count.reinterpret_as_uint())
  }
  for name, held in members {
    text(buf, name[:])
    write(buf, held, policy)
  }
}

///|
fn number(buf : Buffer, n : Double, repr : String?, policy : Policy) -> Unit {
  match repr {
    Some(t) =>
      if is_integer_text(t) {
        if t.at(0).to_int() == 0x2D {
          match magnitude(t[1:]) {
            Some(m) => negative(buf, m)
            None => float(buf, n, policy)
          }
        } else {
          match magnitude(t) {
            Some(value) => positive(buf, value)
            None => float(buf, n, policy)
          }
        }
      } else {
        float(buf, n, policy)
      }
    None =>
      if !n.is_nan() && !n.is_inf() && n == @double.trunc(n) {
        if n >= 0.0 && n < 9223372036854775808.0 {
          positive(buf, n.to_uint64())
        } else if n < 0.0 && n >= -9223372036854775808.0 {
          negative(buf, (-n).to_uint64())
        } else {
          float(buf, n, policy)
        }
      } else {
        float(buf, n, policy)
      }
  }
}

///|
fn positive(buf : Buffer, value : UInt64) -> Unit {
  if value <= 0x7FUL {
    buf.write_byte(value.to_byte())
  } else if value <= 0xFFUL {
    buf.write_byte(0xCC)
    buf.write_byte(value.to_byte())
  } else if value <= 0xFFFFUL {
    buf.write_byte(0xCD)
    buf.write_uint16_be(value.to_uint16())
  } else if value <= 0xFFFF_FFFFUL {
    buf.write_byte(0xCE)
    buf.write_uint_be(value.to_uint())
  } else {
    buf.write_byte(0xCF)
    buf.write_uint64_be(value)
  }
}

///|
/// A negative integer, in the shortest two's complement width that holds it.
fn negative(buf : Buffer, magnitude : UInt64) -> Unit {
  let bits = 0UL - magnitude
  if magnitude <= 32UL {
    buf.write_byte(bits.to_byte())
  } else if magnitude <= 128UL {
    buf.write_byte(0xD0)
    buf.write_byte(bits.to_byte())
  } else if magnitude <= 32768UL {
    buf.write_byte(0xD1)
    buf.write_uint16_be(bits.to_uint16())
  } else if magnitude <= 2147483648UL {
    buf.write_byte(0xD2)
    buf.write_uint_be(bits.to_uint())
  } else {
    buf.write_byte(0xD3)
    buf.write_uint64_be(bits)
  }
}

///|
fn float(buf : Buffer, n : Double, policy : Policy) -> Unit {
  let bits = n.reinterpret_as_uint64()
  if policy.floats == Shortest {
    let single = double_to_single(n)
    let back = single_to_double(single).reinterpret_as_uint64()
    if back == bits || (n.is_nan() && single_to_double(single).is_nan()) {
      buf.write_byte(0xCA)
      buf.write_uint_be(single)
      return
    }
  }
  buf.write_byte(0xCB)
  buf.write_uint64_be(bits)
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
fn magnitude(text : StringView) -> UInt64? {
  let mut value = 0UL
  for i in 0..<text.length() {
    let digit = (text.at(i).to_int() - 0x30).to_uint64()
    if value > (0xFFFF_FFFF_FFFF_FFFFUL - digit) / 10UL {
      return None
    }
    value = value * 10UL + digit
  }
  Some(value)
}
