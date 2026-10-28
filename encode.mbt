///|
fn image_attributes(
  image : Image,
  codec : Compression,
) -> Array[Attribute] raise ExrError {
  let attrs = header_attributes(
    image.data_window,
    image.display_window,
    image.channels(),
    codec,
  )
  for i = 0; i < attrs.length(); i = i + 1 {
    if attrs[i].name == "pixelAspectRatio" {
      attrs[i] = Attribute::real("pixelAspectRatio", image.pixel_aspect)
    }
    if attrs[i].name == "screenWindowWidth" {
      attrs[i] = Attribute::real("screenWindowWidth", image.screen_width)
    }
    if attrs[i].name == "screenWindowCenter" {
      let s = sink()
      s.f32(image.screen_x)
      s.f32(image.screen_y)
      attrs[i] = { name: "screenWindowCenter", kind: "v2f", value: s.finish(), }
    }
  }
  let metadata = image.metadata.copy()
  metadata.sort_by((a, b) => name_compare(a.name, b.name))
  for attr in metadata {
    attrs.push(attr)
  }
  attrs
}

///|
/// Deterministic scanline output; compression is lossless on sample bits.
pub fn encode(
  image : Image,
  compression~ : Compression = Zip,
  limits~ : Limits = Limits::default(),
) -> Bytes raise ExrError {
  limits.validate()
  // Revalidate against this operation's budgets, which may differ from creation.
  ignore(
    Image::new(
      image.data_window,
      image.planes,
      display=image.display_window,
      metadata=image.metadata,
      pixel_aspect=image.pixel_aspect,
      screen_center=(image.screen_x, image.screen_y),
      screen_width=image.screen_width,
      limits~,
    ),
  )
  let header = header_bytes(image_attributes(image, compression))
  if header.length() > limits.max_header_bytes {
    raise Limit("encoded header bytes")
  }
  let height = image.data_window.height()
  let lines = compression.scanlines()
  let count = (height - 1) / lines + 1
  let prefix_size = add(header.length(), mul(count, 8))
  if prefix_size > limits.max_file_bytes {
    raise Limit("offset table/file budget")
  }
  let body = sink()
  let offsets : Array[Int32] = []
  let width = image.data_window.width()
  for i = 0; i < count; i = i + 1 {
    offsets.push(add(prefix_size, body.size()))
    let row0 = i * lines
    let rows = imin(lines, height - row0)
    let raw = sink()
    for row = row0; row < row0 + rows; row = row + 1 {
      for p in image.planes {
        let row_bytes = mul(width, p.channel.kind.bytes())
        let begin = mul(row, row_bytes)
        raw.raw(p.data[begin:begin + row_bytes].to_owned())
      }
    }
    let packed = pack(raw.finish(), compression)
    if add(add(prefix_size, body.size()), add(8, packed.length())) >
      limits.max_file_bytes {
      raise Limit("encoded file bytes")
    }
    body.i32((image.data_window.y0.to_int64() + row0.to_int64()).to_int())
    body.i32(packed.length())
    body.raw(packed)
  }
  let out = sink()
  out.raw(header)
  for offset in offsets {
    out.uint(offset.to_uint64(), 8)
  }
  out.raw(body.finish())
  out.finish()
}

///|
test "EXR multichannel lossless codecs crop projection and metadata roundtrip" {
  let w = Window::new(-5, -3, 7, 15)
  let count = w.pixels()
  let image = Image::new(
    w,
    [
      Plane::from_values(
        { name: "R", kind: F16, linear: false, },
        w,
        Array::makei(count, i => (i % 31).to_double() / 8.0),
      ),
      Plane::from_values(
        { name: "Z", kind: F32, linear: true, },
        w,
        Array::makei(count, i => (i - 20).to_double()),
      ),
      Plane::from_values(
        { name: "id", kind: U32, linear: true, },
        w,
        Array::makei(count, i => 4294967295.0 - i.to_double()),
      ),
    ],
    metadata=[
      Attribute::text("comments", "synthetic"),
      { name: "opaque", kind: "bytes", value: b"\xff\x00", },
    ],
    pixel_aspect=2.0,
    screen_center=(0.25, -0.5),
  )
  for codec in [None, Rle, Zips, Zip] {
    let encoded = encode(image, compression=codec)
    let file = ExrFile::open(encoded)
    let restored = file.read()
    assert_eq(restored.channels(), image.channels())
    for ch in image.channels() {
      assert_eq(
        restored.plane(ch.name).sample_bits(),
        image.plane(ch.name).sample_bits(),
      )
    }
    assert_eq(restored.metadata(), image.metadata())
    assert_eq(restored.pixel_aspect(), 2.0)
    assert_eq(restored.screen(), (0.25, -0.5, 1.0))
    let region = Window::new(-2, 0, 3, 3)
    let result = file.read_with_stats(
      region=Some(region),
      channels=Some(["id"]),
    )
    assert_eq(result.image.window(), region)
    assert_eq(result.image.channels().length(), 1)
    assert_eq(
      result.image.plane("id").bits_at(0, 2),
      image.plane("id").bits_at(0, 2),
    )
    assert_eq(result.chunks_decoded, if codec == Zip { 1 } else { 4 })
    assert_eq(encode(restored, compression=codec), encoded)
  }
}
