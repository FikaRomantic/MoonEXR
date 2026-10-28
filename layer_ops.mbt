///|
/// A layer is the name prefix before the last dot, excluding the final component.
pub fn Channel::layer(self : Channel) -> String {
  let bytes = @utf8.encode(self.name)
  let mut last = -1
  for i = 0; i < bytes.length(); i = i + 1 {
    if bytes[i] == b'.' {
      last = i
    }
  }
  if last < 0 {
    ""
  } else {
    @utf8.decode_lossy(bytes[0:last])
  }
}

///|
pub fn Image::layers(self : Image) -> Array[String] {
  let seen : Map[String, Bool] = Map([])
  let result : Array[String] = []
  for ch in self.channels() {
    let layer = ch.layer()
    if !seen.contains(layer) {
      seen[layer] = true
      result.push(layer)
    }
  }
  result.sort_by(name_compare)
  result
}

///|
pub fn Image::select_layer(
  self : Image,
  layer : String,
  limits~ : Limits = Limits::default(),
) -> Image raise ExrError {
  let names = self
    .channels()
    .filter(ch => ch.layer() == layer)
    .map(ch => ch.name)
  self.select(names, limits~)
}

///|
/// Merge distinct channels only when all geometry, screen settings and metadata agree.
pub fn merge(
  images : Array[Image],
  limits~ : Limits = Limits::default(),
) -> Image raise ExrError {
  if images.is_empty() {
    raise Invalid("no images to merge", 0)
  }
  let first = images[0]
  let planes : Array[Plane] = []
  for img in images {
    if img.data_window != first.data_window ||
      img.display_window != first.display_window ||
      img.pixel_aspect != first.pixel_aspect ||
      img.screen() != first.screen() ||
      img.metadata != first.metadata {
      raise Invalid("merge requires equal windows screen and metadata", 0)
    }
    for p in img.planes {
      planes.push(p)
    }
  }
  first.with_planes(first.data_window, planes, limits)
}

///|
pub fn Image::with_metadata(
  self : Image,
  attrs : Array[Attribute],
  limits~ : Limits = Limits::default(),
) -> Image raise ExrError {
  Image::new(
    self.data_window,
    self.planes,
    display=self.display_window,
    metadata=attrs,
    pixel_aspect=self.pixel_aspect,
    screen_center=(self.screen_x, self.screen_y),
    screen_width=self.screen_width,
    limits~,
  )
}

///|
test "layers use the last dot and merge refuses ambiguous geometry or names" {
  let w = Window::new(0, 0, 0, 0)
  let make = fn(name : String) -> Image raise ExrError {
    Image::new(w, [
      Plane::from_values({ name, kind: F32, linear: false, }, w, [1.0]),
    ])
  }
  let combined = merge([make("R"), make("view.left.R"), make("view.left.G")])
  assert_eq(combined.layers(), ["", "view.left"])
  assert_eq(combined.select_layer("view.left").channels().length(), 2)
  assert_true(
    try {
      ignore(merge([make("R"), make("R")]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(merge([make("R"), make("G").translate(1, 0)]))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(
    combined.with_metadata([Attribute::text("comments", "new")]).metadata()[0].as_text(),
    "new",
  )
}
