///|
/// Explicit numerical conversion. Identity conversion retains every source bit.
/// Float->UINT rejects fractions and nonfinite values; no implicit saturation.
pub fn Plane::convert(
  self : Plane,
  kind : PixelType,
  limits~ : Limits = Limits::default(),
) -> Plane raise ExrError {
  limits.validate()
  if self.window.pixels() > limits.max_pixels {
    raise Limit("converted plane pixel count")
  }
  if kind == self.channel.kind {
    return Plane::from_bits(self.channel, self.window, self.data, limits~)
  }
  let out = sink()
  if mul(self.window.pixels(), kind.bytes()) > limits.max_decoded_bytes {
    raise Limit("converted plane bytes")
  }
  let r = reader(self.data)
  while r.pos < r.end {
    let bits = r.uint(self.channel.kind.bytes()).to_uint()
    if self.channel.kind == F16 && kind == F32 {
      out.uint(half_to_float_bits(bits.reinterpret_as_int()).to_uint64(), 4)
      continue
    }
    if self.channel.kind == F32 && kind == F16 {
      out.uint(float_bits_to_half(bits).to_uint64(), 2)
      continue
    }
    let value = match self.channel.kind {
      U32 => bits.to_double()
      F16 => half_value(bits.reinterpret_as_int())
      F32 => Float::reinterpret_from_uint(bits).to_double()
    }
    match kind {
      U32 => {
        if !finite(value) ||
          value < 0.0 ||
          value > 4294967295.0 ||
          value.trunc() != value {
          raise Invalid("lossy float to UINT conversion", r.pos)
        }
        out.uint(value.to_uint64(), 4)
      }
      F16 =>
        out.uint(
          float_bits_to_half(Float::from_double(value).reinterpret_as_uint()).to_uint64(),
          2,
        )
      F32 => out.f32(value)
    }
  }
  Plane::from_bits(
    { ..self.channel, kind, },
    self.window,
    out.finish(),
    limits~,
  )
}

///|
/// Map sample values to a new plane; never mutates the input.
/// F16/F32 conversion follows round-to-nearest. UINT validation is strict.
pub fn Plane::map_values(
  self : Plane,
  function : (Double) -> Double,
  output_type~ : PixelType = F32,
  limits~ : Limits = Limits::default(),
) -> Plane raise ExrError {
  limits.validate()
  let values : Array[Double] = []
  let w = self.window
  if w.pixels() > limits.max_pixels ||
    mul(w.pixels(), output_type.bytes()) > limits.max_decoded_bytes {
    raise Limit("mapped plane allocation")
  }
  for row = 0; row < w.height(); row = row + 1 {
    for col = 0; col < w.width(); col = col + 1 {
      values.push(function(self.value_at(w.x0 + col, w.y0 + row)))
    }
  }
  Plane::from_values({ ..self.channel, kind: output_type, }, w, values, limits~)
}

///|
pub fn Image::replace_plane(
  self : Image,
  replacement : Plane,
  limits~ : Limits = Limits::default(),
) -> Image raise ExrError {
  let mut found = false
  let planes = self.planes.map(p => {
    if p.channel.name == replacement.channel.name {
      found = true
      replacement
    } else {
      p
    }
  })
  if !found {
    planes.push(replacement)
  }
  self.with_planes(self.data_window, planes, limits)
}

///|
test "explicit conversion preserves half payloads and rejects fractional UINT" {
  let w = Window::new(0, 0, 3, 0)
  let p = Plane::from_bits(
    { name: "Y", kind: F16, linear: false, },
    w,
    b"\x00\x80\x01\x7c\xff\x7f\x00\x3c",
  )
  assert_eq(p.convert(F32).convert(F16).sample_bits(), p.sample_bits())
  assert_eq(p.convert(F16).sample_bits(), p.sample_bits())
  assert_true(
    try {
      ignore(p.convert(U32))
      false
    } catch {
      _ => true
    },
  )
  let exact = Plane::from_values({ name: "id", kind: U32, linear: true, }, w, [
    0.0, 1.0, 16777216.0, 4294967295.0,
  ])
  assert_eq(exact.convert(F32).value_at(2, 0), 16777216.0)
  assert_true(
    try {
      ignore(exact.convert(F32).convert(U32))
      false
    } catch {
      _ => true
    },
  )
  let mapped = p.map_values(_ => 2.0)
  assert_eq(mapped.statistics().mean, Some(2.0))
  let image = Image::new(w, [p]).replace_plane(mapped)
  assert_eq(image.plane("Y").channel().kind, F32)
}
