// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The decimal value of a big-endian byte string, as digits.
///
/// A bignum tag holds the number as bytes; a tree holds it as a number, and
/// JSON writes numbers as digits, so the conversion has to happen here rather
/// than being left to a caller who would have to grow a big-integer library to
/// read a small one.
fn bytes_decimal(bytes : BytesView) -> String {
  let digits : Array[Int32] = [0]
  for k in 0..<bytes.length() {
    let mut carry = bytes.at(k).to_int()
    for i in 0..<digits.length() {
      let v = digits[i] * 256 + carry
      digits[i] = v % 10
      carry = v / 10
    }
    while carry > 0 {
      digits.push(carry % 10)
      carry = carry / 10
    }
  }
  let out = StringBuilder()
  let mut last = digits.length() - 1
  while last > 0 && digits[last] == 0 {
    last -= 1
  }
  for i in 0..<=last {
    out.write_char((digits[last - i] + 48).unsafe_to_char())
  }
  out.to_string()
}

///|
/// The big-endian byte string of a decimal, as a bignum tag holds it.
fn decimal_bytes(text : StringView) -> Bytes {
  let digits : Array[Int32] = []
  for i in 0..<text.length() {
    let c = text.at(i).to_int()
    if c >= 0x30 && c <= 0x39 {
      digits.push(c - 0x30)
    }
  }
  let little : Array[Byte] = []
  let mut going = true
  while going {
    let mut remainder = 0
    let mut more = false
    for i in 0..<digits.length() {
      let v = remainder * 10 + digits[i]
      digits[i] = v / 256
      remainder = v % 256
      if digits[i] != 0 {
        more = true
      }
    }
    little.push(remainder.to_byte())
    going = more
  }
  // The loop produces the least significant byte first; a bignum holds them
  // the other way round.
  let out = Buffer()
  for i in 0..<little.length() {
    out.write_byte(little[little.length() - 1 - i])
  }
  out.to_bytes()
}
