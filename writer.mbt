///|
pub struct Writer {
  priv header : Header
  priv header_bytes : Bytes
  priv limits : Limits
  priv body : Sink
  priv offsets : Array[Int32]
  priv mut buffers : Array[Array[Byte]]
  priv mut rows_received : Int32
  priv mut pending_rows : Int32
  priv mut closed : Bool
}

///|
/// Receive contiguous row batches, retain encoded output and at most one pending
/// chunk of raw samples. Does not write to a filesystem and does not retain inputs.
/// Global metadata/geometry are fixed here; batches carry samples, not new headers.
pub fn Writer::new(
  window : Window,
  channels : Array[Channel],
  display~ : Window = window,
  metadata~ : Array[Attribute] = [],
  compression~ : Compression = Zip,
  limits~ : Limits = Limits::default(),
) -> Writer raise ExrError {
  limits.validate()
  let ordered = channels.copy()
  ordered.sort_by((a, b) => name_compare(a.name, b.name))
  if ordered.is_empty() || ordered.length() > limits.max_channels {
    raise Limit("writer channel count")
  }
  let names : Map[String, Bool] = Map([])
  for ch in ordered {
    valid_name(ch.name)
    if names.contains(ch.name) {
      raise Invalid("duplicate writer channel", 0)
    }
    names[ch.name] = true
  }
  let attrs = header_attributes(window, display, ordered, compression)
  let metadata = metadata.copy()
  metadata.sort_by((a, b) => name_compare(a.name, b.name))
  for attr in metadata {
    attr.validate(limits.max_header_bytes)
    if reserved(attr.name) {
      raise Invalid("reserved writer metadata", 0)
    }
    attrs.push(attr)
  }
  let head = header_bytes(attrs)
  let parsed = parse_header(head, limits)
  let count = (window.height() - 1) / compression.scanlines() + 1
  if add(head.length(), mul(count, 8)) > limits.max_file_bytes {
    raise Limit("writer prefix bytes")
  }
  {
    header: parsed,
    header_bytes: head,
    limits,
    body: sink(),
    offsets: [],
    buffers: ordered.map(_ => []),
    rows_received: 0,
    pending_rows: 0,
    closed: false,
  }
}

///|
pub fn Writer::rows_received(self : Writer) -> Int32 {
  self.rows_received
}

///|
/// Atomic push: validation/encoding failures leave existing content unchanged.
/// A batch must have no optional metadata to avoid silently dropping attributes.
pub fn Writer::push(self : Writer, batch : Image) -> Unit raise ExrError {
  if self.closed {
    raise Invalid("writer is closed", 0)
  }
  let h = self.header
  let w = batch.data_window
  let y = h.data_window.y0.to_int64() + self.rows_received.to_int64()
  if w.x0 != h.data_window.x0 ||
    w.x1 != h.data_window.x1 ||
    w.y0.to_int64() != y ||
    w.height() > h.data_window.height() - self.rows_received {
    raise Invalid("batch must contain next contiguous full-width rows", 0)
  }
  if batch.channels() != h.channels || !batch.metadata.is_empty() {
    raise Invalid(
      "batch channels differ or batch metadata would be discarded", 0,
    )
  }
  let buffers = self.buffers.map(a => a.copy())
  let staged = sink()
  let positions : Array[Int32] = []
  let mut pending = self.pending_rows
  let lines = h.compression.scanlines()
  let total = add(self.rows_received, w.height())
  let chunk_count = (h.data_window.height() - 1) / lines + 1
  let prefix = add(self.header_bytes.length(), mul(chunk_count, 8))
  for row = 0; row < w.height(); row = row + 1 {
    for c = 0; c < h.channels.length(); c = c + 1 {
      let width = mul(w.width(), h.channels[c].kind.bytes())
      let start = mul(row, width)
      for b in batch.planes[c].data[start:start + width] {
        buffers[c].push(b)
      }
    }
    pending += 1
    if pending == lines ||
      self.rows_received + row + 1 == h.data_window.height() {
      let raw = sink()
      for pending_row = 0; pending_row < pending; pending_row = pending_row + 1 {
        for c = 0; c < h.channels.length(); c = c + 1 {
          let width = mul(w.width(), h.channels[c].kind.bytes())
          let start = mul(pending_row, width)
          for j = 0; j < width; j = j + 1 {
            raw.bytes.push(buffers[c][start + j])
          }
        }
      }
      let packed = pack(raw.finish(), h.compression)
      let offset = add(self.body.size(), staged.size())
      if add(prefix, add(offset, add(8, packed.length()))) >
        self.limits.max_file_bytes {
        raise Limit("incremental writer file bytes")
      }
      positions.push(offset)
      let first_y = h.data_window.y0.to_int64() +
        self.rows_received.to_int64() +
        row.to_int64() +
        1L -
        pending.to_int64()
      staged.i32(first_y.to_int())
      staged.i32(packed.length())
      staged.raw(packed)
      for buffer in buffers {
        buffer.clear()
      }
      pending = 0
    }
  }
  // All fallible work precedes state mutation.
  self.body.raw(staged.finish())
  for position in positions {
    self.offsets.push(position)
  }
  self.buffers = buffers
  self.pending_rows = pending
  self.rows_received = total
}

///|
pub fn Writer::finish(self : Writer) -> Bytes raise ExrError {
  if self.closed {
    raise Invalid("writer is closed", 0)
  }
  if self.rows_received != self.header.data_window.height() ||
    self.pending_rows != 0 {
    raise Invalid("writer has not received every row", 0)
  }
  let prefix = add(self.header_bytes.length(), mul(self.offsets.length(), 8))
  let out = sink()
  out.raw(self.header_bytes)
  for position in self.offsets {
    out.uint(add(prefix, position).to_uint64(), 8)
  }
  out.raw(self.body.finish())
  let result = out.finish()
  self.closed = true
  self.body.bytes.clear()
  self.offsets.clear()
  self.buffers.clear()
  result
}

///|
test "incremental writer matches whole-image codec bytes across irregular row batches" {
  let w = Window::new(-3, -8, 1, 28)
  let p = Plane::from_values(
    { name: "Z", kind: F32, linear: true, },
    w,
    Array::makei(w.pixels(), i => (i % 21).to_double()),
  )
  let image = Image::new(w, [p])
  for codec in [None, Rle, Zips, Zip] {
    let writer = Writer::new(w, image.channels(), compression=codec)
    assert_true(
      try {
        ignore(writer.finish())
        false
      } catch {
        _ => true
      },
    )
    let mut row = 0
    while row < w.height() {
      let n = imin(7, w.height() - row)
      writer.push(
        image.crop(Window::new(w.x0, w.y0 + row, w.x1, w.y0 + row + n - 1)),
      )
      row += n
    }
    assert_eq(writer.rows_received(), w.height())
    assert_eq(writer.finish(), encode(image, compression=codec))
    assert_true(
      try {
        ignore(writer.finish())
        false
      } catch {
        _ => true
      },
    )
    assert_true(
      try {
        writer.push(image)
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "incremental writer refuses gaps and metadata atomically" {
  let w = Window::new(0, 0, 0, 2)
  let make = fn(y : Int32) -> Image raise ExrError {
    let w = Window::new(0, y, 0, y)
    Image::new(w, [
      Plane::from_values({ name: "Y", kind: F16, linear: false, }, w, [
        y.to_double(),
      ]),
    ])
  }
  let writer = Writer::new(w, make(0).channels())
  assert_true(
    try {
      writer.push(make(1))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(writer.rows_received(), 0)
  writer.push(make(0))
  assert_true(
    try {
      writer.push(
        make(1).with_metadata([Attribute::text("comments", "do not drop")]),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_eq(writer.rows_received(), 1)
  writer.push(make(1))
  writer.push(make(2))
  assert_eq(
    ExrFile::open(writer.finish()).read().plane("Y").value_at(0, 2),
    2.0,
  )
}
