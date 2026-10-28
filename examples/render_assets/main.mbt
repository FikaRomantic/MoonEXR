///|
fn main raise {
  let window = @exr.Window::new(-4, -2, 11, 7)
  let plane = fn(
    name : String,
    kind : @exr.PixelType,
    scale : Double,
  ) -> @exr.Plane raise {
    @exr.Plane::from_values(
      { name, kind, linear: false, },
      window,
      Array::makei(window.pixels(), i => (i % 16).to_double() * scale),
    )
  }
  let image = @exr.Image::new(
    window,
    [
      plane("beauty.R", F16, 0.5),
      plane("beauty.G", F16, 0.25),
      plane("beauty.B", F16, 0.125),
      plane("depth.Z", F32, 10.0),
    ],
    metadata=[@exr.Attribute::text("comments", "Original render pass exchange")],
  )
  let file = @exr.ExrFile::open(@exr.encode(image))
  let roi = @exr.Window::new(0, 0, 7, 3)
  let selected = file.read(
    region=Some(roi),
    channels=Some(["beauty.R", "beauty.G", "beauty.B"]),
  )
  assert_eq(selected.layers(), ["beauty"])
  let preview = selected.preview_rgba(rgb=["beauty.R", "beauty.G", "beauty.B"])
  assert_eq(preview.length(), 8 * 4 * 4)
  assert_true(selected.plane("beauty.R").statistics().maximum.unwrap() > 1.0)
  assert_eq(
    selected.plane("beauty.R").bits_at(2, 1),
    image.plane("beauty.R").bits_at(2, 1),
  )
  let exported = @exr.ExrFile::open(@exr.encode(selected, compression=Rle)).read()
  assert_eq(exported.display_window(), window)
  assert_eq(exported.channels().length(), 3)
  println(
    "render assets: layer projection, absolute ROI, HDR sample preservation and explicit RGBA preview verified",
  )
}
