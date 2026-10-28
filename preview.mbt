///|
pub(all) enum ToneMap {
  Clamp
  Reinhard
} derive(Debug, Eq)

///|
pub extend ToneMap with @debug.Debug::{to_repr}

///|
pub extend ToneMap with Eq::{equal, not_equal}

///|
pub(all) struct PreviewOptions {
  exposure_stops : Double
  gamma : Double
  tone_map : ToneMap
  premultiplied_alpha : Bool
} derive(Debug)

///|
pub extend PreviewOptions with @debug.Debug::{to_repr}

///|
pub fn PreviewOptions::default() -> PreviewOptions {
  {
    exposure_stops: 0.0,
    gamma: 2.2,
    tone_map: Reinhard,
    premultiplied_alpha: false,
  }
}

///|
fn clamp01(v : Double) -> Double {
  if v.is_nan() || v <= 0.0 {
    0.0
  } else if v >= 1.0 {
    1.0
  } else {
    v
  }
}

///|
fn preview_byte(
  value : Double,
  scale : Double,
  options : PreviewOptions,
) -> Byte {
  let v = if value.is_nan() || value <= 0.0 {
    0.0
  } else if value.is_inf() {
    1.0
  } else {
    let exposed = value * scale
    if options.tone_map == Clamp {
      clamp01(exposed)
    } else if !finite(exposed) {
      1.0
    } else {
      exposed / (1.0 + exposed)
    }
  }
  (clamp01(@math.pow(v, 1.0 / options.gamma)) * 255.0 + 0.5).to_int().to_byte()
}

///|
/// RGBA8 diagnostic preview. Assumes input channels already share the desired
/// linear colour space; no ICC/chromaticity conversion or display calibration.
pub fn Image::preview_rgba(
  self : Image,
  rgb~ : Array[String] = ["R", "G", "B"],
  alpha~ : String? = None,
  options~ : PreviewOptions = PreviewOptions::default(),
  limits~ : Limits = Limits::default(),
) -> Bytes raise ExrError {
  limits.validate()
  if rgb.length() != 3 {
    raise Invalid("preview needs three colour channel names", 0)
  }
  if !finite(options.exposure_stops) ||
    options.exposure_stops < -64.0 ||
    options.exposure_stops > 64.0 ||
    !finite(options.gamma) ||
    options.gamma <= 0.0 ||
    options.gamma > 16.0 {
    raise Invalid("preview exposure/gamma range", 0)
  }
  let w = self.data_window
  let count = w.pixels()
  if count > limits.max_pixels || mul(count, 4) > limits.max_decoded_bytes {
    raise Limit("preview bytes")
  }
  let channels = rgb.map(name => self.plane(name))
  let a = alpha.map(name => self.plane(name))
  let scale = @math.pow(2.0, options.exposure_stops)
  let out = sink()
  for row = 0; row < w.height(); row = row + 1 {
    for col = 0; col < w.width(); col = col + 1 {
      let x = w.x0 + col
      let y = w.y0 + row
      let opacity = match a {
        None => 1.0
        Some(p) => clamp01(p.value_at(x, y))
      }
      for p in channels {
        let value = if options.premultiplied_alpha {
          if opacity == 0.0 {
            0.0
          } else {
            p.value_at(x, y) / opacity
          }
        } else {
          p.value_at(x, y)
        }
        out.bytes.push(preview_byte(value, scale, options))
      }
      out.bytes.push((opacity * 255.0 + 0.5).to_int().to_byte())
    }
  }
  out.finish()
}

///|
test "preview maps HDR explicitly without altering sample planes" {
  let w = Window::new(-1, 2, 0, 2)
  let make = fn(name : String, values : Array[Double]) -> Plane raise ExrError {
    Plane::from_values({ name, kind: F32, linear: false, }, w, values)
  }
  let image = Image::new(w, [
    make("R", [2.0, 100.0]),
    make("G", [1.0, -1.0]),
    make("B", [0.5, 0.0]),
    make("A", [0.5, 0.0]),
  ])
  let bytes = image.preview_rgba(alpha=Some("A"), options={
    exposure_stops: 0.0,
    gamma: 1.0,
    tone_map: Clamp,
    premultiplied_alpha: true,
  })
  assert_eq(bytes, b"\xff\xff\xff\x80\x00\x00\x00\x00")
  assert_eq(image.plane("R").value_at(-1, 2), 2.0)
  let mapped = image.preview_rgba(options={
    ..PreviewOptions::default(),
    gamma: 1.0,
  })
  assert_eq(mapped[0], b'\xaa')
  assert_true(
    try {
      ignore(
        image.preview_rgba(options={ ..PreviewOptions::default(), gamma: 0.0, }),
      )
      false
    } catch {
      _ => true
    },
  )
}
