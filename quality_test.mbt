///|
test "bit difference detects exact UINT32, signed zero and NaN payloads" {
  let w = @moonexr.Window::new(-1, 0, 1, 0)
  let a = @moonexr.Plane::from_values(
    { name: "id", kind: U32, linear: true, },
    w,
    [16777217.0, 0.0, 4294967295.0],
  )
  let b = @moonexr.Plane::from_values(
    { name: "id", kind: U32, linear: true, },
    w,
    [16777218.0, 0.0, 4294967295.0],
  )
  let diff = a.compare_samples(b)
  assert_eq(diff.changed_bits, 1)
  assert_eq(diff.maximum_absolute_error, Some(1.0))
  let f = @moonexr.Plane::from_bits(
    { name: "f", kind: F32, linear: true, },
    w,
    b"\x00\x00\x00\x80\x01\x00\xc0\x7f\x00\x00\x80\x3f",
  )
  let g = @moonexr.Plane::from_bits(
    { name: "g", kind: F32, linear: true, },
    w,
    b"\x00\x00\x00\x00\x02\x00\xc0\x7f\x00\x00\x80\x3f",
  )
  assert_eq(f.compare_samples(g).changed_bits, 2)
  assert_eq(f.compare_samples(g).finite_pairs, 2)
  assert_eq(f.compare_samples(g).maximum_absolute_error, Some(0.0))
  assert_true(
    try {
      ignore(a.compare_samples(f))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "masked statistics distinguish excluded pixels and nonfinite selected samples" {
  let w = @moonexr.Window::new(0, 0, 3, 0)
  let a = @moonexr.Plane::from_values(
    { name: "depth", kind: F32, linear: true, },
    w,
    [2.0, 100.0, 6.0, 0x7ff0000000000000UL.reinterpret_as_double()],
  )
  let mask = @moonexr.Plane::from_values(
    { name: "object", kind: U32, linear: true, },
    w,
    [1.0, 0.0, 1.0, 1.0],
  )
  let s = a.masked_statistics(mask)
  assert_eq(s.selected, 3)
  assert_eq(s.nonfinite_samples, 1)
  assert_eq(s.mean, Some(4.0))
  assert_eq(s.minimum, Some(2.0))
  let empty = mask.map_values(_ => 0.0, output_type=U32)
  assert_eq(a.masked_statistics(empty).mean, None)
  assert_true(
    try {
      ignore(a.masked_statistics(a))
      false
    } catch {
      _ => true
    },
  )
}
