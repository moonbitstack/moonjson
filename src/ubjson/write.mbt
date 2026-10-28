// Universal Binary JSON (UBJSON) — https://ubjson.org/
// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One value, in the simple container form: `[`/`]` and `{`/`}` with a type
/// marker on every element, never the optimized `#`/`$` prefixes.
fn write(
  buf : Buffer,
  value : Json,
  policy : Policy,
) -> Unit raise @moonjson.Refused {
  match value {
    Null => buf.write_byte(0x5A) // Z
    True => buf.write_byte(0x54) // T
    False => buf.write_byte(0x46) // F
    Number(n, repr~) => number(buf, n, repr)
    String(s) => string(buf, s[:])
    Array(items) => {
      buf.write_byte(0x5B) // [
      for item in items {
        write(buf, item, policy)
      }
      buf.write_byte(0x5D) // ]
    }
    Object(members) => object(buf, members, policy)
  }
}

///|
fn string(buf : Buffer, s : StringView) -> Unit {
  let bytes = @utf8.encode(s)
  buf.write_byte(0x53) // S
  write_count(buf, bytes.length())
  buf.write_bytes(bytes[:])
}

///|
/// An object is either the `$bytes` marker `load` documents — spelled as a
/// UBJSON array of uint8, because UBJSON has no byte string — or a plain object
/// whose keys are strings, written in code-point order.
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
        buf.write_byte(0x5B) // [
        for b in bytes {
          buf.write_byte(0x55) // U
          buf.write_byte(b)
        }
        buf.write_byte(0x5D) // ]
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
  buf.write_byte(0x7B) // {
  for name in names {
    string(buf, name[:])
    write(buf, members.get(name).unwrap(), policy)
  }
  buf.write_byte(0x7D) // }
}

///|
/// A length — a string length, a high-precision digit count — as the smallest
/// signed integer the spec allows: `i` for up to 127, then `I`, `l`, `L`.
fn write_count(buf : Buffer, n : Int32) -> Unit {
  if n <= 127 {
    buf.write_byte(0x69) // i
    buf.write_byte(n.to_byte())
  } else if n <= 32767 {
    buf.write_byte(0x49) // I
    buf.write_uint16_be(n.to_uint16())
  } else if n <= 2147483647 {
    buf.write_byte(0x6C) // l
    buf.write_uint_be(n.reinterpret_as_uint())
  } else {
    buf.write_byte(0x4C) // L
    buf.write_uint64_be(n.to_int64().reinterpret_as_uint64())
  }
}

///|
/// A number: an integer when the tree says it is one, a float when it says it is
/// one, and a high-precision decimal when the digits do not fit in an int64. The
/// text the tree keeps decides — `1` and `1.0` are the same number to JSON and
/// different values to UBJSON.
fn number(buf : Buffer, n : Double, repr : String?) -> Unit {
  match repr {
    Some(text) =>
      if is_integer_text(text) {
        write_int_text(buf, text)
      } else {
        float(buf, n)
      }
    None =>
      if !n.is_nan() && !n.is_inf() && n == @double.trunc(n) {
        write_int_text(buf, n.to_string())
      } else {
        float(buf, n)
      }
  }
}

///|
/// Write an integer in the smallest fixed-width type that holds it, or, when it
/// is wider than int64, as a high-precision decimal `H` (which keeps the text).
fn write_int_text(buf : Buffer, text : StringView) -> Unit {
  let negative = text.length() > 0 && text.at(0).to_int() == 0x2D
  let digits = if negative { text[1:] } else { text[:] }
  let magnitude = parse_uint64(digits)
  match magnitude {
    None => write_high(buf, text.to_owned())
    Some(m) =>
      if negative {
        if m <= 128UL {
          write_signed(buf, 0x69, -m.reinterpret_as_int64(), 1)
        } else if m <= 32768UL {
          write_signed(buf, 0x49, -m.reinterpret_as_int64(), 2)
        } else if m <= 2147483648UL {
          write_signed(buf, 0x6C, -m.reinterpret_as_int64(), 4)
        } else if m <= 9223372036854775808UL {
          write_signed(buf, 0x4C, -m.reinterpret_as_int64(), 8)
        } else {
          write_high(buf, text.to_owned())
        }
      } else if m <= 127UL {
        write_signed(buf, 0x69, m.reinterpret_as_int64(), 1)
      } else if m <= 32767UL {
        write_signed(buf, 0x49, m.reinterpret_as_int64(), 2)
      } else if m <= 2147483647UL {
        write_signed(buf, 0x6C, m.reinterpret_as_int64(), 4)
      } else if m <= 9223372036854775807UL {
        write_signed(buf, 0x4C, m.reinterpret_as_int64(), 8)
      } else {
        write_high(buf, text.to_owned())
      }
  }
}

///|
/// One fixed-width signed integer: its marker, then its bytes big-endian.
fn write_signed(
  buf : Buffer,
  marker : Int32,
  value : Int64,
  width : Int32,
) -> Unit {
  buf.write_byte(marker.to_byte())
  let u = value.reinterpret_as_uint64()
  if width == 1 {
    buf.write_byte(u.to_byte())
  } else if width == 2 {
    buf.write_uint16_be(u.to_uint16())
  } else if width == 4 {
    buf.write_uint_be(u.to_uint())
  } else {
    buf.write_uint64_be(u)
  }
}

///|
/// A high-precision number: the `H` marker, a length, then the decimal text.
/// UBJSON has no wider integer and no decimal type, so this is where an integer
/// past int64 — or any decimal too wide for `D` — lives.
fn write_high(buf : Buffer, text : String) -> Unit {
  buf.write_byte(0x48) // H
  write_count(buf, text.length())
  let bytes = @utf8.encode(text[:])
  buf.write_bytes(bytes[:])
}

///|
fn float(buf : Buffer, n : Double) -> Unit {
  buf.write_byte(0x44) // D
  buf.write_uint64_be(n.reinterpret_as_uint64())
}

///|
fn parse_uint64(text : StringView) -> UInt64? {
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

///|
fn is_integer_text(text : StringView) -> Bool {
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
