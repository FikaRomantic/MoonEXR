///|
fn small_image(
  width : Int32,
  height : Int32,
  origin_x : Int32,
  origin_y : Int32,
) -> Image raise ExrError {
  let w = Window::new(
    origin_x,
    origin_y,
    origin_x + width - 1,
    origin_y + height - 1,
  )
  let count = w.pixels()
  Image::new(w, [
    Plane::from_values(
      { name: "A", kind: F16, linear: false, },
      w,
      Array::makei(count, i => (i % 17).to_double() / 16.0),
    ),
    Plane::from_values(
      { name: "depth.Z", kind: F32, linear: true, },
      w,
      Array::makei(count, i => (i * 37 - 11).to_double() / 4.0),
    ),
    Plane::from_values(
      { name: "object.id", kind: U32, linear: true, },
      w,
      Array::makei(count, i => 4294967295.0 - i.to_double()),
    ),
  ])
}

///|
test "all small clipping windows equal coordinate lookup in original image" {
  let image = small_image(4, 5, -2, -3)
  for codec in [None, Rle, Zips, Zip] {
    let file = ExrFile::open(encode(image, compression=codec))
    for x0 = -3; x0 < 3; x0 = x0 + 1 {
      for y0 = -4; y0 < 3; y0 = y0 + 1 {
        for width = 1; width <= 3; width = width + 1 {
          let request = Window::new(x0, y0, x0 + width - 1, y0 + 1)
          match image.window().intersection(request) {
            None => assert_eq(file.plan(request).length(), 0)
            Some(actual) => {
              let decoded = file.read(
                region=Some(request),
                channels=Some(["object.id", "depth.Z"]),
              )
              let cropped = image.crop(request).select(["object.id", "depth.Z"])
              assert_eq(decoded.window(), actual)
              for name in ["object.id", "depth.Z"] {
                assert_eq(
                  decoded.plane(name).sample_bits(),
                  cropped.plane(name).sample_bits(),
                )
              }
            }
          }
        }
      }
    }
  }
}

///|
test "raw sample bits survive all compression codecs across sizes and row orders" {
  let seeds = [
    0U, 0x80000000U, 0x7fffffffU, 0x7fc00001U, 0xffc00001U, 0x7f800000U, 0xff800000U,
    1U,
  ]
  for height in [1, 2, 15, 16, 17, 31, 32, 33] {
    let window = Window::new(-7, -9, -3, height - 10)
    let f = sink()
    let h = sink()
    let u = sink()
    for i = 0; i < window.pixels(); i = i + 1 {
      f.uint(seeds[i % seeds.length()].to_uint64(), 4)
      h.uint(((i * 131 + 32768) & 65535).to_uint64(), 2)
      u.uint(4294967295UL - i.to_uint64(), 4)
    }
    let image = Image::new(window, [
      Plane::from_bits(
        { name: "float", kind: F32, linear: false, },
        window,
        f.finish(),
      ),
      Plane::from_bits(
        { name: "half", kind: F16, linear: false, },
        window,
        h.finish(),
      ),
      Plane::from_bits(
        { name: "uint", kind: U32, linear: true, },
        window,
        u.finish(),
      ),
    ])
    for codec in [None, Rle, Zips, Zip] {
      let file = ExrFile::open(encode(image, compression=codec))
      for name in ["float", "half", "uint"] {
        assert_eq(
          file.read().plane(name).sample_bits(),
          image.plane(name).sample_bits(),
        )
      }
      assert_eq(file.chunks().length(), (height - 1) / codec.scanlines() + 1)
    }
  }
}

///|
test "channel directories and metadata accessors cannot mutate a live file" {
  let file = ExrFile::open(official_fixture("zip"))
  let h = file.header()
  let channels = h.channels()
  channels.clear()
  let attrs = h.metadata()
  attrs.clear()
  let chunks = file.chunks()
  chunks.clear()
  assert_eq(h.channels().length(), 3)
  assert_true(h.metadata().length() > 0)
  assert_eq(file.chunks().length(), 2)
  assert_eq(file.read().channels().length(), 3)
  let img = file.read()
  img.channels().clear()
  img.metadata().clear()
  assert_eq(img.channels().length(), 3)
}

///|
test "metadata canonicalization makes output independent of insertion order" {
  let image = small_image(2, 3, 0, 0)
  let a = Attribute::text("a", "first")
  let b = Attribute::integer("b", 5)
  assert_eq(
    encode(image.with_metadata([a, b])),
    encode(image.with_metadata([b, a])),
  )
  let long_name = "layer.long_component_name_more_than_thirty_one_characters.R"
  let renamed = image.select(["A"]).rename({ "A": long_name })
  let restored = ExrFile::open(encode(renamed)).read()
  assert_eq(restored.channels()[0].name, long_name)
}

///|
test "incremental push budget failure rolls back already encoded chunks" {
  let image = small_image(5, 20, 0, 0)
  let prefix = header_bytes(image_attributes(image, None)).length() + 20 * 8
  let per_row = 5 * (2 + 4 + 4) + 8
  let limits = { ..Limits::default(), max_file_bytes: prefix + per_row * 2, }
  let writer = Writer::new(
    image.window(),
    image.channels(),
    compression=None,
    limits~,
  )
  writer.push(image.crop(Window::new(0, 0, 4, 0)))
  assert_eq(writer.rows_received(), 1)
  assert_true(
    try {
      writer.push(image.crop(Window::new(0, 1, 4, 3)))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(writer.rows_received(), 1)
  writer.push(image.crop(Window::new(0, 1, 4, 1)))
  assert_eq(writer.rows_received(), 2)
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
test "unsupported codecs and arbitrary line order never silently change semantics" {
  let attrs = test_attributes()
  for codec in [4, 5, 6, 7, 8, 9, 255] {
    let altered = attrs.map(a => {
      if a.name == "compression" {
        { ..a, value: Bytes::from_array([codec.to_byte()]), }
      } else {
        a
      }
    })
    assert_true(
      try {
        ignore(parse_header(header_bytes(altered), Limits::default()))
        false
      } catch {
        _ => true
      },
    )
  }
  let altered = attrs.map(a => {
    if a.name == "lineOrder" {
      { ..a, value: b"\x02", }
    } else {
      a
    }
  })
  assert_true(
    try {
      ignore(parse_header(header_bytes(altered), Limits::default()))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "nonfinite-only statistics have no fabricated finite min mean or variance" {
  let w = Window::new(0, 0, 2, 0)
  let p = Plane::from_bits(
    { name: "Y", kind: F32, linear: false, },
    w,
    b"\x00\x00\x80\x7f\x00\x00\x80\xff\x01\x00\xc0\x7f",
  )
  let s = p.statistics()
  assert_eq(s.finite_samples, 0)
  assert_eq(s.minimum, None)
  assert_eq(s.maximum, None)
  assert_eq(s.mean, None)
  assert_eq(s.population_variance, None)
  let hist = p.histogram(-1.0, 1.0, 2)
  assert_eq(hist.bins, [0, 0])
  assert_eq(hist.nonfinite, 3)
}

///|
test "invalid histogram preview and conversion requests fail before output creation" {
  let image = small_image(2, 2, -1, -1)
  let plane = image.plane("depth.Z")
  for count in [0, -1, 65537] {
    assert_true(
      try {
        ignore(plane.histogram(0.0, 1.0, count))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(plane.histogram(2.0, 1.0, 2))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(image.preview_rgba(rgb=["A"]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(image.preview_rgba(rgb=["A", "A", "absent"]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        image.preview_rgba(rgb=["A", "A", "A"], options={
          ..PreviewOptions::default(),
          exposure_stops: 65.0,
        }),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(plane.convert(U32))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(
    image.plane("object.id").convert(U32).sample_bits(),
    image.plane("object.id").sample_bits(),
  )
}

///|
/// Resource preflight must happen before invoking an application callback.
test "derived image budgets are checked before mapping or accumulating metadata" {
  let image = small_image(4, 4, 0, 0)
  let calls = Ref(0)
  assert_true(
    try {
      ignore(
        image
        .plane("A")
        .map_values(
          v => {
            calls.val += 1
            v
          },
          limits={ ..Limits::default(), max_pixels: 1, },
        ),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_eq(calls.val, 0)
  assert_true(
    try {
      ignore(
        image.crop(image.window(), limits={
          ..Limits::default(),
          max_decoded_bytes: 1,
        }),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        image
        .plane("A")
        .convert(F32, limits={ ..Limits::default(), max_pixels: 1, }),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        Writer::new(
          image.window(),
          image.channels(),
          metadata=[Attribute::text("comments", "one")],
          limits={ ..Limits::default(), max_attributes: 8, },
        ),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        Writer::new(
          image.window(),
          image.channels(),
          metadata=[Attribute::text("comments", "payload exceeds tiny budget")],
          limits={ ..Limits::default(), max_header_bytes: 32, },
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}
