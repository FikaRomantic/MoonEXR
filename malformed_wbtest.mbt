///|
fn replace_at(bytes : Bytes, offset : Int32, replacement : Bytes) -> Bytes {
  let out = sink()
  out.raw(bytes[0:offset].to_owned())
  out.raw(replacement)
  out.raw(bytes[offset + replacement.length():].to_owned())
  out.finish()
}

///|
fn integer_bytes(value : Int32, width : Int32) -> Bytes {
  let s = sink()
  s.uint(value.reinterpret_as_uint().to_uint64(), width)
  s.finish()
}

///|
fn test_attributes() -> Array[Attribute] raise ExrError {
  let w = Window::new(-1, -2, 2, 17)
  header_attributes(w, w, [{ name: "Z", kind: F32, linear: true, }], Zip)
}

///|
test "mandatory header attributes are all required with exact types and sizes" {
  let attrs = test_attributes()
  for i = 0; i < attrs.length(); i = i + 1 {
    let missing = attrs.copy()
    ignore(missing.remove(i))
    assert_true(
      try {
        ignore(parse_header(header_bytes(missing), Limits::default()))
        false
      } catch {
        _ => true
      },
    )
    let mistyped = attrs.copy()
    mistyped[i] = { ..attrs[i], kind: "opaque", }
    assert_true(
      try {
        ignore(parse_header(header_bytes(mistyped), Limits::default()))
        false
      } catch {
        _ => true
      },
    )
    let truncated = attrs.copy()
    truncated[i] = { ..attrs[i], value: b"", }
    assert_true(
      try {
        ignore(parse_header(header_bytes(truncated), Limits::default()))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "duplicate channel and attribute names and unsorted channel lists fail" {
  let channel : Channel = { name: "Z", kind: F32, linear: true, }
  let w = Window::new(0, 0, 0, 0)
  for
    channels in [
      [channel, channel],
      [channel, { name: "A", kind: F32, linear: false, }],
    ] {
    assert_true(
      try {
        ignore(
          parse_header(
            header_bytes(header_attributes(w, w, channels, Zip)),
            Limits::default(),
          ),
        )
        false
      } catch {
        _ => true
      },
    )
  }
  let attrs = test_attributes()
  attrs.push(Attribute::text("comments", "one"))
  attrs.push(Attribute::text("comments", "two"))
  assert_true(
    try {
      ignore(parse_header(header_bytes(attrs), Limits::default()))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "subsampling linear flags and reserved channel bytes are validated" {
  let channels = channel_bytes([{ name: "Z", kind: F32, linear: true, }])
  for
    changed in [
      replace_at(channels, 6, b"\x02"),
      replace_at(channels, 7, b"\x01"),
      replace_at(channels, 10, integer_bytes(2, 4)),
      replace_at(channels, 14, integer_bytes(0, 4)),
    ] {
    assert_true(
      try {
        ignore(read_channels(changed, 255, Limits::default()))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(
    try {
      ignore(
        read_channels(
          channels[0:channels.length() - 1].to_owned(),
          255,
          Limits::default(),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(read_channels(b"\x00\x00", 255, Limits::default()))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "chunk table refuses offsets into header duplicate ranges and row mismatch" {
  let bytes = official_fixture("zip")
  let h = parse_header(bytes, Limits::default())
  let file = ExrFile::open(bytes)
  let first = file.chunks()[0]
  let bad_offsets = [0, 8, h.end, bytes.length() - 4, 2147483647]
  for offset in bad_offsets {
    let modified = replace_at(bytes, h.end, integer_bytes(offset, 8))
    assert_true(
      try {
        ignore(ExrFile::open(modified))
        false
      } catch {
        _ => true
      },
    )
  }
  let duplicate = replace_at(bytes, h.end + 8, integer_bytes(first.offset, 8))
  assert_true(
    try {
      ignore(ExrFile::open(duplicate))
      false
    } catch {
      _ => true
    },
  )
  let wrong_y = replace_at(bytes, first.offset, integer_bytes(first.y + 1, 4))
  assert_true(
    try {
      ignore(ExrFile::open(wrong_y))
      false
    } catch {
      _ => true
    },
  )
  for size in [-1, 0, first.decoded_bytes + 1] {
    let invalid = replace_at(bytes, first.offset + 4, integer_bytes(size, 4))
    assert_true(
      try {
        ignore(ExrFile::open(invalid))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "compressed corruption fails lazily and scanners remain failed" {
  let bytes = official_fixture("zip")
  let first = ExrFile::open(bytes).chunks()[0]
  assert_true(first.encoded_bytes < first.decoded_bytes)
  let modified = replace_at(bytes, first.offset + 8, b"\x00\x00")
  let file = ExrFile::open(modified)
  // The second chunk remains independently readable without decoding the first.
  let good = file.read(region=Some(Window::new(-3, 11, 3, 13)))
  assert_eq(good.window().height(), 3)
  let scan = file.scan()
  for i = 0; i < 3; i = i + 1 {
    assert_true(
      try {
        ignore(scan.next())
        false
      } catch {
        _ => true
      },
    )
  }
  assert_eq(scan.chunks_decoded(), 0)
}

///|
test "zlib headers checksums trailing bytes and expansion bounds are strict" {
  let raw = Bytes::from_array(Array::make(1024, b'a'))
  let compressed = zlib_encode(raw)
  let broken_checksum = replace_at(compressed, compressed.length() - 1, b"\x00")
  assert_true(
    try {
      ignore(zlib_decode(broken_checksum, raw.length()))
      false
    } catch {
      _ => true
    },
  )
  let bad_header = replace_at(compressed, 0, b"\x78\x20")
  assert_true(
    try {
      ignore(zlib_decode(bad_header, raw.length()))
      false
    } catch {
      _ => true
    },
  )
  let extra = sink()
  extra.raw(compressed[0:compressed.length() - 4].to_owned())
  extra.raw(b"junk")
  extra.raw(compressed[compressed.length() - 4:].to_owned())
  assert_true(
    try {
      ignore(zlib_decode(extra.finish(), raw.length()))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(zlib_decode(compressed, 100))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(zlib_decode(compressed, 1025))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "resource budgets stop file header channel and logical image allocations" {
  let bytes = official_fixture("zip")
  let limits = Limits::default()
  for
    configured in [
      { ..limits, max_file_bytes: bytes.length() - 1, },
      { ..limits, max_header_bytes: 50, },
      { ..limits, max_pixels: 132, },
      { ..limits, max_channels: 2, },
      { ..limits, max_attributes: 2, },
      { ..limits, max_chunks: 1, },
      { ..limits, max_decoded_bytes: 10, },
      { ..limits, max_channels: 0, },
    ] {
    assert_true(
      try {
        ignore(ExrFile::open(bytes, limits=configured))
        false
      } catch {
        _ => true
      },
    )
  }
  let image = ExrFile::open(bytes).read()
  assert_true(
    try {
      ignore(encode(image, limits={ ..limits, max_file_bytes: 20, }))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        image.preview_rgba(rgb=["R", "R", "R"], limits={
          ..limits,
          max_decoded_bytes: 10,
        }),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "unknown metadata payload survives but never changes structural interpretation" {
  let image = ExrFile::open(official_fixture("zip")).read()
  let attr : Attribute = {
    name: "application.payload",
    kind: "unknownType",
    value: b"\x00\xff\x01",
  }
  let output = ExrFile::open(encode(image.with_metadata([attr])))
  assert_eq(output.header().metadata(), [attr])
  assert_eq(output.read().metadata(), [attr])
  assert_true(
    try {
      ignore(image.with_metadata([Attribute::text("dataWindow", "spoof")]))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "maximum signed coordinates are valid for singleton image and scan" {
  for x in [-2147483648, 2147483647] {
    for y in [-2147483648, 2147483647] {
      let window = Window::new(x, y, x, y)
      let image = Image::new(window, [
        Plane::from_values({ name: "Y", kind: F32, linear: true, }, window, [
          2.0,
        ]),
      ])
      let file = ExrFile::open(encode(image))
      assert_eq(file.read().plane("Y").value_at(x, y), 2.0)
      let scan = file.scan(batch_rows=1)
      assert_eq(scan.next().unwrap().window(), window)
      assert_true(scan.next() is None)
    }
  }
}
