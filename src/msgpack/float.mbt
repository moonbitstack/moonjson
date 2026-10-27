// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Single precision, from the bits.
///
/// The same conversion CBOR does, repeated here because two packages cannot
/// share a private function and eighty lines do not deserve a package of their
/// own. If a third format needs it, it moves into one.

///|
fn shrink(value : UInt64, shift : Int32) -> UInt64 {
  if shift <= 0 {
    return value
  }
  if shift >= 64 {
    return 0UL
  }
  let half = 1UL << (shift - 1)
  let remainder = value & ((1UL << shift) - 1UL)
  let kept = value >> shift
  if remainder > half || (remainder == half && (kept & 1UL) == 1UL) {
    kept + 1UL
  } else {
    kept
  }
}

///|
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

///|
fn double_to_single(value : Double) -> UInt32 {
  let bits = value.reinterpret_as_uint64()
  let sign = bits >> 63 << 31
  let exponent = ((bits >> 52) & 0x7FF).to_int()
  let mantissa = bits & 0xF_FFFF_FFFF_FFFFUL
  if exponent == 0x7FF {
    let payload = if mantissa == 0 { 0UL } else { 0x40_0000UL }
    return (sign | 0x7F80_0000UL | payload).to_uint()
  }
  let biased = exponent - 1023 + 127
  if biased >= 0xFF {
    return (sign | 0x7F80_0000UL).to_uint()
  }
  if biased <= 0 {
    if biased < -23 {
      return sign.to_uint()
    }
    let whole = mantissa | 0x10_0000_0000_0000UL
    return (sign | shrink(whole, 1 - biased + 29)).to_uint()
  }
  (sign | (biased.to_uint64() << 23) | shrink(mantissa, 29)).to_uint()
}

///|
/// A float keeps a text that says it is one, so writing the tree back out gives
/// a float again.
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
