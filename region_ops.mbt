///|
/// Crop by absolute coordinates; reject disjoint requests, clip partial overlap.
pub fn Image::crop(
  self : Image,
  region : Window,
  limits~ : Limits = Limits::default(),
) -> Image raise ExrError {
  let window = match self.data_window.intersection(region) {
    Some(w) => w
    None => raise Invalid("crop does not intersect image", 0)
  }
  let planes = self.planes.map(p => {
    let b = sink()
    let row_bytes = mul(window.width(), p.channel.kind.bytes())
    for row = 0; row < window.height(); row = row + 1 {
      let start = mul(
        self.data_window.offset(window.x0, window.y0 + row),
        p.channel.kind.bytes(),
      )
      b.raw(p.data[start:start + row_bytes].to_owned())
    }
    Plane::from_bits(p.channel, window, b.finish(), limits~)
  })
  self.with_planes(window, planes, limits)
}

///|
pub fn Image::select(
  self : Image,
  names : Array[String],
  limits~ : Limits = Limits::default(),
) -> Image raise ExrError {
  let channels = selected_channels(self.channels(), Some(names))
  self.with_planes(
    self.data_window,
    channels.map(c => self.plane(c.name)),
    limits,
  )
}

///|
pub fn Image::rename(
  self : Image,
  mapping : Map[String, String],
  limits~ : Limits = Limits::default(),
) -> Image raise ExrError {
  for name, _ in mapping {
    ignore(self.plane(name))
  }
  let planes = self.planes.map(p => {
    let name = mapping.get(p.channel.name).unwrap_or(p.channel.name)
    Plane::from_bits({ ..p.channel, name, }, p.window, p.data, limits~)
  })
  self.with_planes(self.data_window, planes, limits)
}

///|
fn translated(v : Int32, delta : Int32) -> Int32 raise ExrError {
  let result = v.to_int64() + delta.to_int64()
  if result < -2147483648L || result > 2147483647L {
    raise Limit("translated coordinate")
  }
  result.to_int()
}

///|
/// Translate both windows without resampling or changing any sample bits.
pub fn Image::translate(
  self : Image,
  dx : Int32,
  dy : Int32,
  limits~ : Limits = Limits::default(),
) -> Image raise ExrError {
  let moved = fn(w : Window) -> Window raise ExrError {
    Window::new(
      translated(w.x0, dx),
      translated(w.y0, dy),
      translated(w.x1, dx),
      translated(w.y1, dy),
    )
  }
  let window = moved(self.data_window)
  Image::new(
    window,
    self.planes.map(p => Plane::from_bits(p.channel, window, p.data, limits~)),
    display=moved(self.display_window),
    metadata=self.metadata,
    pixel_aspect=self.pixel_aspect,
    screen_center=(self.screen_x, self.screen_y),
    screen_width=self.screen_width,
    limits~,
  )
}

///|
test "crop selection rename and translation preserve image coordinate semantics" {
  let w = Window::new(-2, -1, 1, 1)
  let p = Plane::from_values(
    { name: "beauty.R", kind: F32, linear: false, },
    w,
    Array::makei(12, i => i.to_double()),
  )
  let image = Image::new(w, [p])
  let crop = image.crop(Window::new(-1, 0, 8, 8))
  assert_eq(crop.window(), Window::new(-1, 0, 1, 1))
  assert_eq(crop.display_window(), w)
  assert_eq(crop.plane("beauty.R").value_at(-1, 0), 5.0)
  let renamed = crop.rename({ "beauty.R": "R" }).select(["R"])
  assert_eq(
    renamed.plane("R").sample_bits(),
    crop.plane("beauty.R").sample_bits(),
  )
  let moved = renamed.translate(10, -5)
  assert_eq(moved.plane("R").value_at(9, -5), 5.0)
  assert_eq(moved.display_window(), Window::new(8, -6, 11, -4))
  assert_true(
    try {
      ignore(image.select(["absent"]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(image.rename({ "absent": "R" }))
      false
    } catch {
      _ => true
    },
  )
}
