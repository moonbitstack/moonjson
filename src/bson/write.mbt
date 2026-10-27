// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
fn document(
  buf : Buffer,
  value : Json,
  policy : Policy,
) -> Unit raise @moonjson.Refused {
  match value {
    Object(members) => body(buf, members, policy)
    _ =>
      raise @moonjson.Unwritable(why="a BSON document is an object at the top")
  }
}

///|
/// A document is its length, its elements, and a terminator — so the elements
/// are written first and the length is put in front of them afterwards.
fn body(
  buf : Buffer,
  members : Map[String, Json],
  policy : Policy,
) -> Unit raise @moonjson.Refused {
  let inner = Buffer()
  for name, held in members {
    element(inner, name, held, policy)
  }
  buf.write_int_le(inner.length() + 5)
  buf.write_bytes(inner.to_bytes()[:])
  buf.write_byte(0)
}

///|
fn cstring(buf : Buffer, text : String) -> Unit {
  buf.write_string_utf8(text[:])
  buf.write_byte(0)
}

///|
fn text(buf : Buffer, s : StringView) -> Unit {
  let bytes = @utf8.encode(s)
  buf.write_int_le(bytes.length() + 1)
  buf.write_bytes(bytes[:])
  buf.write_byte(0)
}

///|
fn element(
  buf : Buffer,
  name : String,
  value : Json,
  policy : Policy,
) -> Unit raise @moonjson.Refused {
  match value {
    Null => {
      buf.write_byte(0x0A)
      cstring(buf, name)
    }
    True => {
      buf.write_byte(0x08)
      cstring(buf, name)
      buf.write_byte(1)
    }
    False => {
      buf.write_byte(0x08)
      cstring(buf, name)
      buf.write_byte(0)
    }
    Number(n, repr~) => number(buf, name, n, repr)
    String(s) => {
      buf.write_byte(0x02)
      cstring(buf, name)
      text(buf, s[:])
    }
    Array(items) => {
      buf.write_byte(0x04)
      cstring(buf, name)
      let inner = Buffer()
      for i, item in items {
        element(inner, i.to_string(), item, policy)
      }
      buf.write_int_le(inner.length() + 5)
      buf.write_bytes(inner.to_bytes()[:])
      buf.write_byte(0)
    }
    Object(members) =>
      if !marked(buf, name, members, policy) {
        buf.write_byte(0x03)
        cstring(buf, name)
        body(buf, members, policy)
      }
  }
}

///|
/// The markers `load` documents, written back as the types they stand for.
/// Answers whether it wrote the member: an object that is not a marker is an
/// embedded document, which the caller writes.
fn marked(
  buf : Buffer,
  name : String,
  members : Map[String, Json],
  policy : Policy,
) -> Bool raise @moonjson.Refused {
  if members.length() == 1 {
    if members.get("$oid") is Some(String(hex)) {
      let bytes = @hex.decode(hex[:]) catch {
        _ =>
          raise @moonjson.Unwritable(why="\"$oid\" wants twelve bytes of hex")
      }
      if bytes.length() != 12 {
        raise @moonjson.Unwritable(why="\"$oid\" wants twelve bytes of hex")
      }
      buf.write_byte(0x07)
      cstring(buf, name)
      buf.write_bytes(bytes[:])
      return true
    }
    if members.get("$bytes") is Some(String(hex)) {
      let bytes = @hex.decode(hex[:]) catch {
        _ => raise @moonjson.Unwritable(why="\"$bytes\" wants lowercase hex")
      }
      buf.write_byte(0x05)
      cstring(buf, name)
      buf.write_int_le(bytes.length())
      buf.write_byte(0)
      buf.write_bytes(bytes[:])
      return true
    }
    if members.get("$binary") is Some(Object(detail)) {
      let kind = match detail.get("kind") {
        Some(Number(k, ..)) => k.to_int()
        _ => raise @moonjson.Unwritable(why="\"$binary\" wants a \"kind\"")
      }
      let bytes = match detail.get("data") {
        Some(String(hex)) =>
          @hex.decode(hex[:]) catch {
            _ =>
              raise @moonjson.Unwritable(why="\"$binary\" wants lowercase hex")
          }
        _ => raise @moonjson.Unwritable(why="\"$binary\" wants a \"data\"")
      }
      buf.write_byte(0x05)
      cstring(buf, name)
      buf.write_int_le(bytes.length())
      buf.write_byte(kind.to_byte())
      buf.write_bytes(bytes[:])
      return true
    }
    if members.get("$date") is Some(Number(n, ..)) && n == @double.trunc(n) {
      buf.write_byte(0x09)
      cstring(buf, name)
      buf.write_int64_le(n.to_int64())
      return true
    }
    if members.get("$timestamp") is Some(Object(detail)) {
      let seconds = match detail.get("t") {
        Some(Number(v, ..)) => v.to_int64()
        _ => raise @moonjson.Unwritable(why="\"$timestamp\" wants a \"t\"")
      }
      let increment = match detail.get("i") {
        Some(Number(v, ..)) => v.to_int64()
        _ => raise @moonjson.Unwritable(why="\"$timestamp\" wants an \"i\"")
      }
      buf.write_byte(0x11)
      cstring(buf, name)
      buf.write_int64_le((seconds << 32) | (increment & 0xFFFF_FFFFL))
      return true
    }
    if members.get("$decimal128") is Some(String(hex)) {
      let bytes = @hex.decode(hex[:]) catch {
        _ =>
          raise @moonjson.Unwritable(
            why="\"$decimal128\" wants sixteen bytes of hex",
          )
      }
      if bytes.length() != 16 {
        raise @moonjson.Unwritable(
          why="\"$decimal128\" wants sixteen bytes of hex",
        )
      }
      buf.write_byte(0x13)
      cstring(buf, name)
      buf.write_bytes(bytes[:])
      return true
    }
    if members.get("$undefined") is Some(True) {
      buf.write_byte(0x06)
      cstring(buf, name)
      return true
    }
    if members.get("$symbol") is Some(String(s)) {
      buf.write_byte(0x0E)
      cstring(buf, name)
      text(buf, s[:])
      return true
    }
    if members.get("$code") is Some(String(code)) {
      buf.write_byte(0x0D)
      cstring(buf, name)
      text(buf, code[:])
      return true
    }
    if members.get("$minKey") is Some(True) {
      buf.write_byte(0xFF)
      cstring(buf, name)
      return true
    }
    if members.get("$maxKey") is Some(True) {
      buf.write_byte(0x7F)
      cstring(buf, name)
      return true
    }
    if members.get("$dbpointer") is Some(Object(detail)) {
      let ns = match detail.get("ns") {
        Some(String(s)) => s
        _ => raise @moonjson.Unwritable(why="\"$dbpointer\" wants an \"ns\"")
      }
      let oid = match detail.get("oid") {
        Some(String(hex)) => hex
        _ => raise @moonjson.Unwritable(why="\"$dbpointer\" wants an \"oid\"")
      }
      let bytes = @hex.decode(oid[:]) catch {
        _ =>
          raise @moonjson.Unwritable(
            why="\"$dbpointer\" wants twelve bytes of hex",
          )
      }
      buf.write_byte(0x0C)
      cstring(buf, name)
      text(buf, ns[:])
      buf.write_bytes(bytes[:])
      return true
    }
    if members.get("$regex") is Some(String(pattern)) {
      let options = match members.get("options") {
        Some(String(s)) => s
        _ => ""
      }
      buf.write_byte(0x0B)
      cstring(buf, name)
      cstring(buf, pattern)
      cstring(buf, options)
      return true
    }
  }
  if members.length() == 2 {
    if members.get("$code") is Some(String(code)) &&
      members.get("$scope") is Some(Object(scope_members)) {
      // A scoped function is a total length, then a string and a document —
      // not a document itself, so it is laid out by hand.
      let payload = Buffer()
      text(payload, code[:])
      body(payload, scope_members, policy)
      buf.write_byte(0x0F)
      cstring(buf, name)
      buf.write_int_le(payload.length() + 4)
      buf.write_bytes(payload.to_bytes()[:])
      return true
    }
  }
  false
}

///|
fn number(buf : Buffer, name : String, n : Double, repr : String?) -> Unit {
  match repr {
    Some(t) =>
      if is_integer_text(t) {
        match integer_text(t) {
          Some(value) =>
            if value >= -2147483648L && value <= 2147483647L {
              buf.write_byte(0x10)
              cstring(buf, name)
              buf.write_int_le(value.to_int())
            } else {
              buf.write_byte(0x12)
              cstring(buf, name)
              buf.write_int64_le(value)
            }
          None => double(buf, name, n)
        }
      } else {
        double(buf, name, n)
      }
    None =>
      if !n.is_nan() &&
        !n.is_inf() &&
        n == @double.trunc(n) &&
        n >= -2147483648.0 &&
        n <= 2147483647.0 {
        buf.write_byte(0x10)
        cstring(buf, name)
        buf.write_int_le(n.to_int())
      } else if !n.is_nan() &&
        !n.is_inf() &&
        n == @double.trunc(n) &&
        n >= -9223372036854775808.0 &&
        n < 9223372036854775808.0 {
        buf.write_byte(0x12)
        cstring(buf, name)
        buf.write_int64_le(n.to_int64())
      } else {
        double(buf, name, n)
      }
  }
}

///|
fn double(buf : Buffer, name : String, n : Double) -> Unit {
  buf.write_byte(0x01)
  cstring(buf, name)
  buf.write_double_le(n)
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
fn integer_text(text : String) -> Int64? {
  let negative = text.at(0).to_int() == 0x2D
  let mut i = if negative { 1 } else { 0 }
  let mut value = 0UL
  let limit = if negative {
    9223372036854775808UL
  } else {
    9223372036854775807UL
  }
  while i < text.length() {
    let digit = (text.at(i).to_int() - 0x30).to_uint64()
    if value > (limit - digit) / 10UL {
      return None
    }
    value = value * 10UL + digit
    i += 1
  }
  if negative {
    Some((0UL - value).reinterpret_as_int64())
  } else {
    Some(value.reinterpret_as_int64())
  }
}
