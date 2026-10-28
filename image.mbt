///|
pub struct Image {
  priv data_window : Window
  priv display_window : Window
  priv planes : Array[Plane]
  priv metadata : Array[Attribute]
  priv pixel_aspect : Double
  priv screen_x : Double
  priv screen_y : Double
  priv screen_width : Double
}

///|
pub fn Image::new(
  window : Window,
  planes : Array[Plane],
  display~ : Window = window,
  metadata~ : Array[Attribute] = [],
  pixel_aspect~ : Double = 1.0,
  screen_center~ : (Double, Double) = (0.0, 0.0),
  screen_width~ : Double = 1.0,
  limits~ : Limits = Limits::default(),
) -> Image raise ExrError {
  limits.validate()
  if planes.is_empty() || planes.length() > limits.max_channels {
    raise Limit("image channel count")
  }
  if window.pixels() > limits.max_pixels {
    raise Limit("image pixel count")
  }
  let ordered = planes.copy()
  ordered.sort_by((a, b) => name_compare(a.channel.name, b.channel.name))
  let mut previous = ""
  let mut bytes = 0
  for p in ordered {
    valid_name(p.channel.name)
    if p.window != window || p.channel.name == previous {
      raise Invalid("plane window or duplicate channel", 0)
    }
    previous = p.channel.name
    bytes = add(bytes, p.data.length())
  }
  if bytes > limits.max_decoded_bytes {
    raise Limit("image decoded bytes")
  }
  if metadata.length() > limits.max_attributes - 8 {
    raise Limit("image metadata count")
  }
  let names : Map[String, Bool] = {}
  let mut header_size = 0
  for a in metadata {
    a.validate(limits.max_header_bytes)
    if reserved(a.name) || names.contains(a.name) {
      raise Invalid("reserved/duplicate metadata", 0)
    }
    names[a.name] = true
    header_size = add(
      header_size,
      add(
        a.value.length(),
        @utf8.encode(a.name).length() + @utf8.encode(a.kind).length() + 6,
      ),
    )
  }
  if header_size > limits.max_header_bytes {
    raise Limit("metadata byte budget")
  }
  let (screen_x, screen_y) = screen_center
  for v in [pixel_aspect, screen_x, screen_y, screen_width] {
    if !finite(v) || Float::from_double(v).is_inf() {
      raise Invalid("finite screen/aspect value required", 0)
    }
  }
  if pixel_aspect <= 0.0 || screen_width < 0.0 {
    raise Invalid("invalid aspect/width", 0)
  }
  {
    data_window: window,
    display_window: display,
    planes: ordered,
    metadata: metadata.copy(),
    pixel_aspect,
    screen_x,
    screen_y,
    screen_width,
  }
}

///|
pub fn Image::window(self : Image) -> Window {
  self.data_window
}

///|
pub fn Image::display_window(self : Image) -> Window {
  self.display_window
}

///|
pub fn Image::channels(self : Image) -> Array[Channel] {
  self.planes.map(p => p.channel)
}

///|
pub fn Image::metadata(self : Image) -> Array[Attribute] {
  self.metadata.copy()
}

///|
pub fn Image::pixel_aspect(self : Image) -> Double {
  self.pixel_aspect
}

///|
pub fn Image::screen(self : Image) -> (Double, Double, Double) {
  (self.screen_x, self.screen_y, self.screen_width)
}

///|
pub fn Image::plane(self : Image, name : String) -> Plane raise ExrError {
  for p in self.planes {
    if p.channel.name == name {
      return p
    }
  }
  raise Invalid("missing channel: " + name, 0)
}

///|
fn Image::with_planes(
  self : Image,
  window : Window,
  planes : Array[Plane],
  limits : Limits,
) -> Image raise ExrError {
  Image::new(
    window,
    planes,
    display=self.display_window,
    metadata=self.metadata,
    pixel_aspect=self.pixel_aspect,
    screen_center=(self.screen_x, self.screen_y),
    screen_width=self.screen_width,
    limits~,
  )
}

///|
test "image owns channel and metadata arrays and enforces common windows" {
  let w = Window::new(0, 0, 0, 0)
  let p = Plane::from_values({ name: "R", kind: F32, linear: false, }, w, [2.0])
  let planes = [p]
  let attrs = [Attribute::text("comments", "a")]
  let img = Image::new(w, planes, metadata=attrs)
  planes.clear()
  attrs.clear()
  assert_eq(img.plane("R").value_at(0, 0), 2.0)
  assert_eq(img.metadata().length(), 1)
  assert_true(
    try {
      ignore(Image::new(w, [p, p]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(Image::new(w, [p], metadata=[Attribute::text("channels", "bad")]))
      false
    } catch {
      _ => true
    },
  )
}
