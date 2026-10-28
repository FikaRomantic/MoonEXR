///|
/// IEEE binary16 expansion without arithmetic on NaN payloads.
pub fn half_to_float_bits(bits : Int32) -> UInt32 {
  let h = bits & 65535
  let sign = (h & 32768).to_uint() << 16
  let exp = (h >> 10) & 31
  let mut frac = h & 1023
  if exp == 31 {
    return sign | 0x7f800000U | (frac.to_uint() << 13)
  }
  if exp != 0 {
    return sign | ((exp + 112).to_uint() << 23) | (frac.to_uint() << 13)
  }
  if frac == 0 {
    return sign
  }
  let mut e = -14
  while frac < 1024 {
    frac = frac << 1
    e -= 1
  }
  sign | ((e + 127).to_uint() << 23) | ((frac & 1023).to_uint() << 13)
}

///|
fn rounded_shift(v : UInt32, n : Int32) -> UInt32 {
  let upper = v >> n
  let lower = v & ((1U << n) - 1U)
  let middle = 1U << (n - 1)
  if lower > middle || (lower == middle && (upper & 1U) != 0U) {
    upper + 1U
  } else {
    upper
  }
}

///|
/// Round IEEE binary32 to binary16, round-to-nearest with ties to even.
/// Sign and the high payload bits survive NaNs; a truncated payload stays nonzero.
pub fn float_bits_to_half(bits : UInt32) -> Int32 {
  let sign = (bits >> 16).to_int() & 32768
  let exp = ((bits >> 23) & 255U).to_int()
  let frac = bits & 0x7fffffU
  if exp == 255 {
    if frac == 0U {
      return sign | 31744
    }
    return sign | 31744 | imax(1, (frac >> 13).to_int())
  }
  let e = exp - 127
  if e > 15 {
    return sign | 31744
  }
  if e < -25 {
    return sign
  }
  let mant = frac | 0x800000U
  if e < -14 {
    return sign | rounded_shift(mant, -e - 1).to_int()
  }
  let n = rounded_shift(mant, 13).to_int()
  sign | (((e + 14) << 10) + n)
}

///|
pub fn half_value(bits : Int32) -> Double {
  Float::reinterpret_from_uint(half_to_float_bits(bits)).to_double()
}

///|
test "every binary16 payload expands and contracts exactly" {
  for bits = 0; bits < 65536; bits = bits + 1 {
    assert_eq(float_bits_to_half(half_to_float_bits(bits)), bits)
  }
}

///|
test "half rounding includes ties subnormal boundary signed zero and overflow" {
  assert_eq(half_value(0x3c00), 1.0)
  assert_eq(half_value(0x0001), 0.000000059604644775390625)
  assert_eq(
    float_bits_to_half(Float::from_double(1.00048828125).reinterpret_as_uint()),
    0x3c00,
  )
  assert_eq(
    float_bits_to_half(Float::from_double(1.00146484375).reinterpret_as_uint()),
    0x3c02,
  )
  assert_eq(float_bits_to_half(0x80000000U), 0x8000)
  assert_eq(
    float_bits_to_half(Float::from_double(65520.0).reinterpret_as_uint()),
    0x7c00,
  )
  assert_true(half_value(0x7c00).is_inf())
  assert_true(half_value(0x7c01).is_nan())
}
