///|
fn main raise {
  let w = @exr.Window::new(0, 0, 2, 0)
  let depth = @exr.Plane::from_values(
    { name: "depth", kind: F32, linear: true, },
    w,
    [2.0, 99.0, 6.0],
  )
  let mask = @exr.Plane::from_values(
    { name: "object_id", kind: U32, linear: true, },
    w,
    [1.0, 0.0, 1.0],
  )
  assert_eq(depth.masked_statistics(mask).mean, Some(4.0))
  let image = @exr.Image::new(w, [depth, mask])
  let restored = @exr.ExrFile::open(@exr.encode(image, compression=Zip)).read()
  assert_eq(depth.compare_samples(restored.plane("depth")).changed_bits, 0)
  println(
    "EXR quality gate: object mask excludes background and ZIP exchange preserves exact sample bits",
  )
}
