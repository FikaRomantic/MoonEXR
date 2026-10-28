///|
test "public API minimal example writes a real file with exact ID channel" {
  let w = @moonexr.Window::new(-1, 2, 1, 3)
  let original : Array[Double] = [0.0, 1.0, 16777217.0, 4294967295.0, 42.0, 7.0]
  let ids = @moonexr.Plane::from_values(
    { name: "id", kind: U32, linear: true, },
    w,
    original,
  )
  original.clear()
  let image = @moonexr.Image::new(w, [ids], metadata=[
    @moonexr.Attribute::text("comments", "public API"),
  ])
  let bytes = @moonexr.encode(image)
  assert_true(bytes.length() > 8)
  assert_eq(bytes[0], b'\x76')
  assert_eq(bytes[1], b'\x2f')
  assert_eq(bytes[2], b'\x31')
  assert_eq(bytes[3], b'\x01')
  let file = @moonexr.ExrFile::open(bytes)
  assert_eq(file.header().data_window().bounds(), (-1, 2, 1, 3))
  assert_eq(file.read().plane("id").bits_at(-1, 3), 4294967295U)
  assert_eq(file.read().plane("id").bits_at(1, 2), 16777217U)
  assert_eq(
    file.header().attribute("comments").unwrap().as_text(),
    "public API",
  )
}

///|
test "public crop keeps display canvas and selected original sample bits" {
  let canvas = @moonexr.Window::new(-10, -10, 10, 10)
  let data = @moonexr.Window::new(-2, -2, 2, 2)
  let signal = @moonexr.Plane::from_values(
    { name: "sensor.signal", kind: F16, linear: true, },
    data,
    Array::makei(25, i => i.to_double() / 4.0),
  )
  let source = @moonexr.Image::new(data, [signal], display=canvas)
  let cropped = source.crop(@moonexr.Window::new(0, 0, 5, 5))
  assert_eq(cropped.window().bounds(), (0, 0, 2, 2))
  assert_eq(cropped.display_window(), canvas)
  assert_eq(cropped.plane("sensor.signal").value_at(0, 0), 3.0)
  let moved = cropped.translate(2, -1)
  assert_eq(moved.display_window().bounds(), (-8, -11, 12, 9))
  assert_eq(moved.plane("sensor.signal").value_at(2, -1), 3.0)
  assert_eq(
    cropped.plane("sensor.signal").sample_bits(),
    moved.plane("sensor.signal").sample_bits(),
  )
  assert_true(
    try {
      ignore(cropped.translate(2147483647, 0))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "public sampled type changes are explicit and cannot silently clamp UINT" {
  let w = @moonexr.Window::new(0, 0, 2, 0)
  let floats = @moonexr.Plane::from_values(
    { name: "Y", kind: F32, linear: false, },
    w,
    [1.0, 1.5, -1.0],
  )
  assert_true(
    try {
      ignore(floats.convert(U32))
      false
    } catch {
      _ => true
    },
  )
  let half = floats.convert(F16)
  assert_eq(half.channel().kind, F16)
  assert_eq(half.value_at(1, 0), 1.5)
  let changed = floats.map_values(v => v * 2.0)
  assert_eq(changed.value_at(1, 0), 3.0)
  assert_eq(floats.value_at(1, 0), 1.5)
  let image = @moonexr.Image::new(w, [floats]).replace_plane(half)
  assert_eq(image.channels()[0].kind, F16)
  let stats = changed.statistics()
  assert_eq(stats.finite_samples, 3)
  assert_eq(stats.minimum, Some(-2.0))
  assert_eq(stats.maximum, Some(3.0))
}

///|
test "public layer composition rejects collisions and mismatched metadata" {
  let w = @moonexr.Window::new(0, 0, 0, 0)
  let p = @moonexr.Plane::from_values(
    { name: "left.R", kind: F32, linear: false, },
    w,
    [1.0],
  )
  let left = @moonexr.Image::new(w, [p])
  let right = left.rename({ "left.R": "right.R" })
  let combined = @moonexr.merge([left, right])
  assert_eq(combined.layers(), ["left", "right"])
  assert_eq(combined.select_layer("right").channels()[0].name, "right.R")
  assert_true(
    try {
      ignore(@moonexr.merge([left, left]))
      false
    } catch {
      _ => true
    },
  )
  let metadata = [@moonexr.Attribute::integer("frame", 1)]
  assert_true(
    try {
      ignore(@moonexr.merge([left, right.with_metadata(metadata)]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(combined.rename({ "left.R": "right.R" }))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(combined.select(["left.R", "left.R"]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(combined.select_layer("absent"))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "public incremental writer can retry after incomplete finish and invalid push" {
  let w = @moonexr.Window::new(0, 0, 1, 2)
  let channel : @moonexr.Channel = { name: "Z", kind: F32, linear: true, }
  let writer = @moonexr.Writer::new(w, [channel])
  let batch = fn(row : Int32) -> @moonexr.Image raise {
    let row_window = @moonexr.Window::new(0, row, 1, row)
    @moonexr.Image::new(row_window, [
      @moonexr.Plane::from_values(channel, row_window, [row.to_double(), 9.0]),
    ])
  }
  assert_true(
    try {
      ignore(writer.finish())
      false
    } catch {
      _ => true
    },
  )
  assert_eq(writer.rows_received(), 0)
  writer.push(batch(0))
  assert_true(
    try {
      writer.push(batch(2))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(writer.rows_received(), 1)
  writer.push(batch(1))
  writer.push(batch(2))
  let bytes = writer.finish()
  assert_eq(writer.rows_received(), 3)
  let file = @moonexr.ExrFile::open(bytes)
  assert_eq(file.read().plane("Z").value_at(0, 2), 2.0)
  assert_true(
    try {
      writer.push(batch(0))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(writer.finish())
      false
    } catch {
      _ => true
    },
  )
}

///|
test "public scanner output contains every selected row exactly once" {
  let w = @moonexr.Window::new(4, -10, 5, 23)
  let p = @moonexr.Plane::from_values(
    { name: "index", kind: U32, linear: true, },
    w,
    Array::makei(68, i => i.to_double()),
  )
  let file = @moonexr.ExrFile::open(
    @moonexr.encode(@moonexr.Image::new(w, [p])),
  )
  let scan = file.scan(batch_rows=5)
  let mut y = -10
  let mut pixels = 0
  while scan.next() is Some(image) {
    let (x0, y0, x1, y1) = image.window().bounds()
    assert_eq((x0, x1), (4, 5))
    assert_eq(y0, y)
    assert_true(image.window().height() <= 5)
    assert_eq(image.plane("index").value_at(4, y0), pixels.to_double())
    y = y1 + 1
    pixels += image.window().pixels()
  }
  assert_eq(y, 24)
  assert_eq(pixels, 68)
  assert_eq(scan.chunks_decoded(), 3)
  assert_true(scan.next() is None)
  assert_true(scan.next() is None)
  assert_true(
    try {
      ignore(file.scan(batch_rows=0))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "public lossless float bit path retains negative zero and signaling NaN payload" {
  let w = @moonexr.Window::new(0, 0, 3, 0)
  let bits = b"\x00\x00\x00\x80\x01\x00\x80\x7f\x00\x00\x80\xff\x01\x00\x00\x00"
  let p = @moonexr.Plane::from_bits(
    { name: "raw", kind: F32, linear: false, },
    w,
    bits,
  )
  for codec in [@moonexr.Compression::None, Rle, Zips, Zip] {
    let restored = @moonexr.ExrFile::open(
      @moonexr.encode(@moonexr.Image::new(w, [p]), compression=codec),
    ).read()
    assert_eq(restored.plane("raw").sample_bits(), bits)
    assert_eq(restored.plane("raw").bits_at(1, 0), 0x7f800001U)
  }
  assert_eq(p.convert(F32).sample_bits(), bits)
  assert_eq(@moonexr.half_to_float_bits(0x8000), 0x80000000U)
  assert_eq(@moonexr.float_bits_to_half(0x80000000U), 0x8000)
}

///|
test "public histogram bounds are inclusive and float metadata rejects infinity" {
  let w = @moonexr.Window::new(0, 0, 5, 0)
  let p = @moonexr.Plane::from_values(
    { name: "Y", kind: F16, linear: false, },
    w,
    [-1.0, 0.0, 0.5, 1.0, 1.5, 2.0],
  )
  let histogram = p.histogram(0.0, 1.0, 2)
  assert_eq(histogram.bins, [1, 2])
  assert_eq(histogram.below, 1)
  assert_eq(histogram.above, 2)
  assert_eq(histogram.nonfinite, 0)
  let attr = @moonexr.Attribute::real("exposure", 2.0)
  assert_eq(attr.as_real(), 2.0)
  assert_true(
    try {
      ignore(attr.as_integer())
      false
    } catch {
      _ => true
    },
  )
  let infinity = @moonexr.half_value(0x7c00)
  assert_true(
    try {
      ignore(@moonexr.Attribute::real("exposure", infinity))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(@moonexr.Image::new(w, [p], pixel_aspect=1.0e-300))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "public preview exposes exposure and transparency policy explicitly" {
  let w = @moonexr.Window::new(0, 0, 0, 0)
  let make = fn(name : String, value : Double) -> @moonexr.Plane raise {
    @moonexr.Plane::from_values({ name, kind: F32, linear: false, }, w, [value])
  }
  let image = @moonexr.Image::new(w, [
    make("R", 0.25),
    make("G", 0.25),
    make("B", 0.25),
    make("A", 0.5),
  ])
  let ordinary = image.preview_rgba(alpha=Some("A"), options={
    exposure_stops: 0.0,
    gamma: 1.0,
    tone_map: Clamp,
    premultiplied_alpha: false,
  })
  assert_eq(ordinary, b"\x40\x40\x40\x80")
  let straight = image.preview_rgba(alpha=Some("A"), options={
    exposure_stops: 0.0,
    gamma: 1.0,
    tone_map: Clamp,
    premultiplied_alpha: true,
  })
  assert_eq(straight, b"\x80\x80\x80\x80")
  assert_eq(image.plane("R").value_at(0, 0), 0.25)
}

///|
test "public metadata containers are copied and reserved names rejected" {
  let w = @moonexr.Window::new(0, 0, 0, 0)
  let p = @moonexr.Plane::from_values(
    { name: "Y", kind: F32, linear: true, },
    w,
    [1.0],
  )
  let metadata = [@moonexr.Attribute::text("comments", "keep")]
  let image = @moonexr.Image::new(w, [p], metadata~)
  metadata.clear()
  image.metadata().clear()
  assert_eq(image.metadata().length(), 1)
  assert_eq(image.metadata()[0].as_text(), "keep")
  for
    name in [
      "channels", "dataWindow", "compression", "type", "tiles", "chunkCount",
    ] {
    assert_true(
      try {
        ignore(image.with_metadata([@moonexr.Attribute::text(name, "spoof")]))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(
        @moonexr.Plane::from_values(
          { name: "bad\u0000name", kind: F32, linear: false, },
          w,
          [1.0],
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}
