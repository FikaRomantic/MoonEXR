///|
test "official EXR fixtures preserve every channel bit on all four backends" {
  for name in ["none", "rle", "zips", "zip", "decreasing"] {
    let file = ExrFile::open(official_fixture(name))
    let image = file.read()
    let h = file.header()
    assert_eq(h.channels().map(c => c.name), ["R", "Z", "object.id"])
    let (x0, y0, _, _) = image.window().bounds()
    assert_eq(image.plane("object.id").bits_at(x0, y0), 4294967295U)
    if name != "decreasing" {
      assert_eq(image.window(), Window::new(-3, -5, 3, 13))
      assert_eq(image.display_window(), Window::new(-10, -10, 10, 20))
      assert_eq(image.pixel_aspect(), 1.5)
      assert_eq(image.screen(), (0.25, -0.5, 2.0))
      assert_eq(image.plane("R").bits_at(-2, -5), 32768U)
      assert_eq(image.plane("R").bits_at(-1, -5), 31744U)
      assert_eq(image.plane("Z").bits_at(-2, -5), 0x7fc00001U)
      assert_eq(image.plane("Z").bits_at(-3, -5), 0x80000000U)
      assert_eq(
        h.attribute("comments").unwrap().as_text(),
        "Original synthetic MoonEXR test",
      )
    } else {
      assert_eq(h.line_order(), 1)
    }
    for channel in image.channels() {
      for codec in [None, Rle, Zips, Zip] {
        let rewritten = ExrFile::open(encode(image, compression=codec)).read()
        assert_eq(
          rewritten.plane(channel.name).sample_bits(),
          image.plane(channel.name).sample_bits(),
        )
      }
    }
  }
}

///|
test "official ZIP block plans and chunk scanner clip in absolute coordinates" {
  let file = ExrFile::open(official_fixture("zip"))
  assert_eq(file.chunks().length(), 2)
  assert_eq(file.chunks()[0].y, -5)
  assert_eq(file.chunks()[1].y, 11)
  assert_eq(file.chunks()[1].rows, 3)
  let scan = file.scan(
    region=Some(Window::new(-2, 8, 2, 12)),
    channels=Some(["Z"]),
    batch_rows=2,
  )
  let mut output_y = 8
  let complete = file.read()
  while scan.next() is Some(image) {
    assert_eq(image.channels().length(), 1)
    assert_eq(image.window().y0, output_y)
    for row = 0; row < image.window().height(); row = row + 1 {
      for x = -2; x <= 2; x = x + 1 {
        assert_eq(
          image.plane("Z").bits_at(x, output_y + row),
          complete.plane("Z").bits_at(x, output_y + row),
        )
      }
    }
    output_y += image.window().height()
  }
  assert_eq(output_y, 13)
  assert_eq(scan.chunks_decoded(), 2)
  assert_eq(file.plan(Window::new(100, 100, 101, 101)).length(), 0)
  assert_true(
    try {
      ignore(file.read(region=Some(Window::new(100, 100, 101, 101))))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "every truncated official file prefix is rejected before successful full read" {
  let bytes = official_fixture("zip")
  for size = 0; size < bytes.length(); size = size + 1 {
    assert_true(
      try {
        ignore(ExrFile::open(bytes[0:size].to_owned()).read())
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "official tiled files and altered storage flags are rejected" {
  assert_true(
    try {
      ignore(ExrFile::open(official_fixture("tiled")))
      false
    } catch {
      _ => true
    },
  )
  let base = official_fixture("zip")
  for flags in [0x200U, 0x800U, 0x1000U, 0x2000U, 0x100U] {
    let s = sink()
    s.uint(20000630UL, 4)
    s.uint((2U | flags).to_uint64(), 4)
    s.raw(base[8:].to_owned())
    assert_true(
      try {
        ignore(ExrFile::open(s.finish()))
        false
      } catch {
        _ => true
      },
    )
  }
}
