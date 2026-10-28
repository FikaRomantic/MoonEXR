///|
pub(all) enum PixelType {
  U32
  F16
  F32
} derive(Debug, Eq)

///|
pub extend PixelType with @debug.Debug::{to_repr}

///|
pub extend PixelType with Eq::{equal, not_equal}

///|
pub fn PixelType::bytes(self : PixelType) -> Int32 {
  match self {
    F16 => 2
    U32 | F32 => 4
  }
}

///|
fn PixelType::code(self : PixelType) -> Int32 {
  match self {
    U32 => 0
    F16 => 1
    F32 => 2
  }
}

///|
fn pixel_type(code : Int32) -> PixelType raise ExrError {
  match code {
    0 => U32
    1 => F16
    2 => F32
    _ => raise Unsupported("pixel representation")
  }
}

///|
pub(all) struct Channel {
  name : String
  kind : PixelType
  linear : Bool
} derive(Debug, Eq)

///|
pub extend Channel with @debug.Debug::{to_repr}

///|
pub extend Channel with Eq::{equal, not_equal}

///|
fn valid_name(name : String) -> Unit raise ExrError {
  let bytes = @utf8.encode(name)
  if bytes.length() == 0 || bytes.length() > 255 {
    raise Invalid("name length must be 1..255 UTF-8 bytes", 0)
  }
  for b in bytes {
    if b == 0 {
      raise Invalid("NUL in name", 0)
    }
  }
}

///|
fn name_compare(a : String, b : String) -> Int32 {
  let a = @utf8.encode(a)
  let b = @utf8.encode(b)
  for i = 0; i < imin(a.length(), b.length()); i = i + 1 {
    if a[i] != b[i] {
      return a[i].to_int() - b[i].to_int()
    }
  }
  a.length() - b.length()
}

///|
pub struct Plane {
  priv channel : Channel
  priv window : Window
  priv data : Bytes
}

///|
pub fn Plane::from_bits(
  channel : Channel,
  window : Window,
  bits : Bytes,
  limits~ : Limits = Limits::default(),
) -> Plane raise ExrError {
  limits.validate()
  valid_name(channel.name)
  let pixels = window.pixels()
  if pixels > limits.max_pixels {
    raise Limit("plane pixel count")
  }
  let size = mul(pixels, channel.kind.bytes())
  if size > limits.max_decoded_bytes {
    raise Limit("plane byte budget")
  }
  if size != bits.length() {
    raise Invalid("plane sample byte count", 0)
  }
  { channel, window, data: bits, }
}

///|
pub fn Plane::channel(self : Plane) -> Channel {
  self.channel
}

///|
pub fn Plane::window(self : Plane) -> Window {
  self.window
}

///|
pub fn Plane::sample_bits(self : Plane) -> Bytes {
  self.data
}

///|
pub fn Plane::bits_at(
  self : Plane,
  x : Int32,
  y : Int32,
) -> UInt32 raise ExrError {
  let width = self.channel.kind.bytes()
  let start = mul(self.window.offset(x, y), width)
  reader(self.data[start:start + width].to_owned()).uint(width).to_uint()
}

///|
pub fn Plane::value_at(
  self : Plane,
  x : Int32,
  y : Int32,
) -> Double raise ExrError {
  let bits = self.bits_at(x, y)
  match self.channel.kind {
    U32 => bits.to_double()
    F16 => half_value(bits.to_int())
    F32 => Float::reinterpret_from_uint(bits).to_double()
  }
}

///|
pub fn Plane::from_values(
  channel : Channel,
  window : Window,
  values : Array[Double],
  limits~ : Limits = Limits::default(),
) -> Plane raise ExrError {
  limits.validate()
  let count = window.pixels()
  if count > limits.max_pixels ||
    mul(count, channel.kind.bytes()) > limits.max_decoded_bytes {
    raise Limit("plane allocation")
  }
  if values.length() != count {
    raise Invalid("plane value count", 0)
  }
  let out = sink()
  for v in values {
    match channel.kind {
      U32 => {
        if !finite(v) || v < 0.0 || v > 4294967295.0 || v != v.trunc() {
          raise Invalid("UINT sample must be exact integer in 0..2^32-1", 0)
        }
        out.uint(v.to_uint64(), 4)
      }
      F32 => out.f32(v)
      F16 =>
        out.uint(
          float_bits_to_half(Float::from_double(v).reinterpret_as_uint()).to_uint64(),
          2,
        )
    }
  }
  Plane::from_bits(channel, window, out.finish(), limits~)
}

///|
test "typed planes preserve integer precision and bit payloads" {
  let w = Window::new(-1, 7, 1, 7)
  let p = Plane::from_values(
    { name: "object.id", kind: U32, linear: true, },
    w,
    [0.0, 16777217.0, 4294967295.0],
  )
  assert_eq(p.value_at(0, 7), 16777217.0)
  assert_eq(p.bits_at(1, 7), 4294967295U)
  assert_true(
    try {
      ignore(p.value_at(2, 7))
      false
    } catch {
      _ => true
    },
  )
  let raw = b"\x01\x00\xc0\x7f\x00\x00\x00\x80\x00\x00\x80\x7f"
  let q = Plane::from_bits({ name: "Z", kind: F32, linear: false, }, w, raw)
  assert_eq(q.sample_bits(), raw)
  assert_true(q.value_at(-1, 7).is_nan())
  assert_eq(q.bits_at(0, 7), 2147483648U)
}

///|
test "planes reject invalid byte shape names and UINT values" {
  let w = Window::new(0, 0, 0, 0)
  for value in [-1.0, 0.1, 4294967296.0] {
    assert_true(
      try {
        ignore(
          Plane::from_values({ name: "id", kind: U32, linear: true, }, w, [
            value,
          ]),
        )
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(
        Plane::from_bits(
          { name: "", kind: F16, linear: false, },
          w,
          b"\x00\x00",
        ),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        Plane::from_bits({ name: "x", kind: F16, linear: false, }, w, b"\x00"),
      )
      false
    } catch {
      _ => true
    },
  )
}
