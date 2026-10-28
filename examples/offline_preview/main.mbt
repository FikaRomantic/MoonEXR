///|
fn main raise {
  let window = @exr.Window::new(0, 0, 7, 15)
  let make = fn(name : String, scale : Double) -> @exr.Image raise {
    @exr.Image::new(window, [
      @exr.Plane::from_values(
        { name, kind: F32, linear: false, },
        window,
        Array::makei(128, i => (i % 8).to_double() * scale),
      ),
    ])
  }
  let source = @exr.merge([make("R", 0.5), make("G", 0.25), make("B", 0.125)])
  let bytes = @exr.encode(source)
  let file = @exr.ExrFile::open(bytes)
  let request = @exr.Window::new(2, 5, 5, 10)
  let plan = file.plan(request)
  assert_eq(plan.length(), 1)
  let selected = file.read_with_stats(region=Some(request))
  assert_eq(selected.chunks_decoded, 1)
  let default_preview = selected.image.preview_rgba()
  let brighter = selected.image.preview_rgba(options={
    ..@exr.PreviewOptions::default(),
    exposure_stops: 1.0,
  })
  assert_eq(default_preview.length(), 4 * 6 * 4)
  assert_true(brighter[0] > default_preview[0])
  let histogram = selected.image.plane("R").histogram(0.0, 4.0, 8)
  assert_eq(histogram.nonfinite, 0)
  assert_eq(histogram.below, 0)
  assert_eq(histogram.above, 0)
  let before = selected.image.plane("R").sample_bits()
  ignore(selected.image.preview_rgba())
  assert_eq(selected.image.plane("R").sample_bits(), before)
  println(
    "offline preview: native/JS/Wasm-compatible region selection, histogram and exposure preview verified",
  )
}
