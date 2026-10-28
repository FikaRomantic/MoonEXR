///|
fn main raise {
  let window = @exr.Window::new(-128, -128, 127, 255)
  let channel : @exr.Channel = { name: "depth.Z", kind: F32, linear: true, }
  let writer = @exr.Writer::new(window, [channel])
  for row = 0; row < 384; row = row + 1 {
    let w = @exr.Window::new(-128, row - 128, 127, row - 128)
    let plane = @exr.Plane::from_values(
      channel,
      w,
      Array::makei(256, col => (row * 256 + col).to_double()),
    )
    writer.push(@exr.Image::new(w, [plane]))
  }
  let bytes = writer.finish()
  let file = @exr.ExrFile::open(bytes)
  let region = @exr.Window::new(-128, 240, 127, 255)
  let output = file.read_with_stats(region=Some(region))
  assert_eq(file.chunks().length(), 24)
  assert_eq(output.chunks_decoded, 1)
  assert_eq(output.image.window().pixels(), 4096)
  assert_eq(output.image.plane("depth.Z").value_at(127, 255), 98303.0)
  assert_eq(output.image.plane("depth.Z").statistics().mean, Some(96255.5))
  println(
    "scale: 98304 pixels, 24 chunks; selected 4096 pixels from one chunk; bytes=\{bytes.length()}",
  )
}
