// PostgreSQL numeric — the `NumericVar` wire layout:
// https://www.postgresql.org/docs/current/datatype-numeric.html
// Reference: src/backend/utils/adt/numeric.c (numeric_send / numeric_recv) and
// src/include/utils/numeric.h.
//
// A numeric is `ndigits int16, weight int16, sign uint16, dscale uint16`, then
// `ndigits` int16 base-10000 digits, every word big-endian. `weight` is the
// power of 10000 of the first digit, so the decimal point sits after
// `4 * (weight + 1)` digits; `dscale` is the display scale. Signs are
// 0x0000 positive, 0x4000 negative, 0xC000 NaN, 0xD000 +Inf, 0xF000 -Inf.
// The digits are a decimal fraction in base 10000, which is what makes a
// numeric exact where a float is not.

///|
priv struct Decimal {
  neg : Bool
  digits : String
  point : Int32
}

///|
/// One base-10000 digit from four decimal characters.
fn group4(s : String, k : Int32) -> Int32 {
  let mut v : Int32 = 0
  for i in 0..<4 {
    v = v * 10 + (s[k + i].to_int() - 0x30)
  }
  v
}

///|
fn zeros(n : Int32) -> String {
  let out = StringBuilder()
  for _ in 0..<n {
    out.write_char('0')
  }
  out.to_string()
}

///|
fn pad4(d : Int32) -> String {
  let s = d.to_string()
  let out = StringBuilder()
  for _ in 0..<(4 - s.length()) {
    out.write_char('0')
  }
  out.write_string(s)
  out.to_string()
}

///|
fn parse_int(s : String) -> Int32 {
  let mut v : Int32 = 0
  let mut neg = false
  let mut i : Int32 = 0
  if s.length() > 0 && (s[0] == '-' || s[0] == '+') {
    neg = s[0] == '-'
    i = 1
  }
  while i < s.length() {
    if s[i] >= '0' && s[i] <= '9' {
      v = v * 10 + (s[i].to_int() - 0x30)
    }
    i += 1
  }
  if neg {
    -v
  } else {
    v
  }
}

///|
/// Split a decimal literal (optional sign, digits, optional `.`, optional
/// exponent) into a sign, its significant digits and the position of the
/// decimal point, with the exponent folded in.
fn parse_decimal(text : String) -> Decimal {
  let mut s = text
  let mut neg = false
  if s.length() > 0 && (s[0] == '-' || s[0] == '+') {
    neg = s[0] == '-'
    s = s[1:s.length()].to_owned()
  }
  let mut mantissa = s
  let mut exp : Int32 = 0
  let mut e_at : Int32 = -1
  let mut i : Int32 = 0
  while i < s.length() {
    if s[i] == 'e' || s[i] == 'E' {
      e_at = i
      break
    }
    i += 1
  }
  if e_at >= 0 {
    mantissa = s[0:e_at].to_owned()
    exp = parse_int(s[e_at + 1:s.length()].to_owned())
  }
  let mut ip = mantissa
  let mut fp = ""
  let mut dot_at : Int32 = -1
  let mut j : Int32 = 0
  while j < mantissa.length() {
    if mantissa[j] == '.' {
      dot_at = j
      break
    }
    j += 1
  }
  if dot_at >= 0 {
    ip = mantissa[0:dot_at].to_owned()
    fp = mantissa[dot_at + 1:mantissa.length()].to_owned()
  }
  let raw = ip + fp
  let mut point : Int32 = ip.length() + exp
  let mut start : Int32 = 0
  while start < raw.length() && raw[start] == '0' {
    start += 1
  }
  let digits = if start >= raw.length() {
    ""
  } else {
    raw[start:raw.length()].to_owned()
  }
  point = point - start
  { neg, digits, point, }
}

///|
/// Write a number as a NumericVar. The decimal text decides the digits, so a
/// number that came in as text keeps every digit it had.
fn encode_numeric(buf : Buffer, n : Double, repr : String?) -> Unit {
  let text = match repr {
    Some(t) => t
    None => n.to_string()
  }
  let dec = parse_decimal(text)
  let digits = dec.digits
  let point = dec.point
  let int_str = if point <= 0 {
    ""
  } else if point <= digits.length() {
    digits[0:point].to_owned()
  } else {
    digits + zeros(point - digits.length())
  }
  let frac_str = if point >= digits.length() {
    ""
  } else if point >= 0 {
    digits[point:digits.length()].to_owned()
  } else {
    zeros(-point) + digits
  }
  let dscale : Int32 = frac_str.length()
  let int_groups : Array[Int32] = []
  let int_padded = zeros((4 - int_str.length() % 4) % 4) + int_str
  let mut k : Int32 = 0
  while k < int_padded.length() {
    int_groups.push(group4(int_padded, k))
    k += 4
  }
  let frac_groups : Array[Int32] = []
  let frac_padded = frac_str + zeros((4 - frac_str.length() % 4) % 4)
  let mut m : Int32 = 0
  while m < frac_padded.length() {
    frac_groups.push(group4(frac_padded, m))
    m += 4
  }
  let groups : Array[Int32] = []
  for g in int_groups {
    groups.push(g)
  }
  for g in frac_groups {
    groups.push(g)
  }
  let mut weight : Int32 = int_groups.length() - 1
  if int_groups.length() == 0 {
    weight = -1
  }
  let mut lead : Int32 = 0
  while lead < groups.length() && groups[lead] == 0 {
    lead += 1
  }
  let stripped : Array[Int32] = []
  let mut idx = lead
  while idx < groups.length() {
    stripped.push(groups[idx])
    idx += 1
  }
  weight = weight - lead
  let mut end = stripped.length()
  while end > 0 && stripped[end - 1] == 0 {
    end -= 1
  }
  let ndigits = end
  if ndigits == 0 {
    weight = 0
  }
  let negative = dec.neg && ndigits > 0
  buf.write_uint16_be(ndigits.to_uint16())
  buf.write_uint16_be(weight.to_uint16())
  buf.write_uint16_be((if negative { 0x4000 } else { 0x0000 }).to_uint16())
  buf.write_uint16_be(dscale.to_uint16())
  for i in 0..<ndigits {
    buf.write_uint16_be(stripped[i].to_uint16())
  }
}

///|
fn Reader::uint16(self : Reader) -> Int32 raise @moonjson.Refused {
  (self.byte() << 8) | self.byte()
}

///|
fn Reader::int16(self : Reader) -> Int32 raise @moonjson.Refused {
  let v = self.uint16()
  if v >= 0x8000 {
    v - 0x10000
  } else {
    v
  }
}

///|
/// Read a NumericVar and give back the number it names.
fn decode_numeric(r : Reader) -> Double raise @moonjson.Refused {
  let ndigits = r.int16()
  let weight = r.int16()
  let sign = r.uint16()
  let dscale = r.uint16()
  let _ = dscale
  let digits : Array[Int32] = []
  for _ in 0..<ndigits {
    digits.push(r.int16())
  }
  if sign == 0xC000 {
    return @double.not_a_number
  }
  if sign == 0xD000 {
    return @double.infinity
  }
  if sign == 0xF000 {
    return @double.neg_infinity
  }
  let out = StringBuilder()
  if sign == 0x4000 {
    out.write_char('-')
  }
  if ndigits == 0 {
    out.write_char('0')
  } else {
    let all_sb = StringBuilder()
    for d in digits {
      all_sb.write_string(pad4(d))
    }
    let all = all_sb.to_string()
    let point : Int32 = 4 * (weight + 1)
    if point <= 0 {
      out.write_string("0.")
      for _ in 0..<-point {
        out.write_char('0')
      }
      out.write_string(all)
    } else if point >= all.length() {
      out.write_string(all)
      for _ in 0..<(point - all.length()) {
        out.write_char('0')
      }
    } else {
      out.write_view(all[0:point])
      out.write_char('.')
      out.write_view(all[point:all.length()])
    }
  }
  @string.parse_double(out.to_string()) catch {
    _ => 0.0
  }
}
