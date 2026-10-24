// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// IEEE-754 half and single precision, done from the bit patterns.
///
/// The core library has no Float-to-Double conversion, and CBOR needs the two
/// smaller widths in both directions anyway: reading 16- and 32-bit floats, and
/// writing the shortest width that still reads back as the same number. Doing
/// it on the bits is also the only way to round half-to-even the way the
/// standard says, rather than the way a cast happens to.

///|
/// Round right by `shift`, ties to even. This is the whole of the rounding rule
/// in both directions, and the reason a value like 65504 has an exact half
/// while 65505 does not.
fn shrink(value : UInt64, shift : Int32) -> UInt64 {
  if shift <= 0 {
    return value
  }
  if shift >= 64 {
    return 0UL
  }
  let half = 1UL << (shift - 1)
  let mask = (1UL << shift) - 1UL
  let remainder = value & mask
  let kept = value >> shift
  if remainder > half || (remainder == half && (kept & 1UL) == 1UL) {
    kept + 1UL
  } else {
    kept
  }
}

///|
fn half_to_double(bits : UInt32) -> Double {
  let sign = (bits >> 15).to_uint64() << 63
  let mut exponent = ((bits >> 10) & 0x1F).reinterpret_as_int()
  let mut mantissa = bits & 0x3FF
  if exponent == 0x1F {
    let payload = if mantissa == 0 { 0UL } else { mantissa.to_uint64() << 42 }
    return (sign | 0x7FF0_0000_0000_0000UL | payload).reinterpret_as_double()
  }
  if exponent == 0 {
    if mantissa == 0 {
      return sign.reinterpret_as_double()
    }
    // A subnormal half is a normal double: shift the leading one into place
    // and account for every shift in the exponent.
    while (mantissa & 0x400) == 0 {
      mantissa = mantissa << 1
      exponent -= 1
    }
    exponent += 1
    mantissa = mantissa & 0x3FF
  }
  let wide = (exponent - 15 + 1023).to_uint64()
  (sign | (wide << 52) | (mantissa.to_uint64() << 42)).reinterpret_as_double()
}

///|
fn double_to_half(value : Double) -> UInt32 {
  let bits = value.reinterpret_as_uint64()
  let sign = bits >> 63 << 15
  let exponent = ((bits >> 52) & 0x7FF).to_int()
  let mantissa = bits & 0xF_FFFF_FFFF_FFFFUL
  if exponent == 0x7FF {
    let payload = if mantissa == 0 { 0UL } else { 0x200UL }
    return (sign | 0x7C00UL | payload).to_uint()
  }
  let biased = exponent - 1023 + 15
  if biased >= 0x1F {
    return (sign | 0x7C00UL).to_uint()
  }
  if biased <= 0 {
    if biased < -10 {
      return sign.to_uint()
    }
    // A subnormal half counts in units of 2^-24, so the significand is scaled
    // down to that unit rather than to a normal half's 2^-14.
    let whole = mantissa | 0x10_0000_0000_0000UL
    let kept = shrink(whole, 43 - biased)
    return (sign | kept).to_uint()
  }
  let kept = shrink(mantissa, 42)
  (sign | (biased.to_uint64() << 10) | kept).to_uint()
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
    let kept = shrink(whole, 1 - biased + 29)
    return (sign | kept).to_uint()
  }
  let kept = shrink(mantissa, 29)
  (sign | (biased.to_uint64() << 23) | kept).to_uint()
}
