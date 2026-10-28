///|
pub struct Scan {
  priv file : ExrFile
  priv region : Window
  priv channels : Array[String]?
  priv batch_rows : Int32
  priv ranges : Array[ChunkInfo]
  priv mut next_chunk : Int32
  priv mut pending : Image?
  priv mut pending_row : Int32
  priv mut failed : Bool
  priv mut decoded : Int32
}

///|
/// Iterate selected rows in increasing absolute y, independent of physical order.
/// One selected chunk stays decoded until consumed. This does not stream file IO.
pub fn ExrFile::scan(
  self : ExrFile,
  region~ : Window? = None,
  channels~ : Array[String]? = None,
  batch_rows~ : Int32 = 16,
) -> Scan raise ExrError {
  if batch_rows < 1 {
    raise Invalid("batch_rows must be positive", 0)
  }
  let w = match region {
    None => self.header.data_window
    Some(w) =>
      match self.header.data_window.intersection(w) {
        Some(w) => w
        None => raise Invalid("scan region is disjoint", 0)
      }
  }
  ignore(selected_channels(self.header.channels, channels))
  {
    file: self,
    region: w,
    channels: channels.map(a => a.copy()),
    batch_rows,
    ranges: self.plan(w),
    next_chunk: 0,
    pending: None,
    pending_row: 0,
    failed: false,
    decoded: 0,
  }
}

///|
pub fn Scan::chunks_decoded(self : Scan) -> Int32 {
  self.decoded
}

///|
pub fn Scan::next(self : Scan) -> Image? raise ExrError {
  if self.failed {
    raise Invalid("scanner permanently failed after decoding error", 0)
  }
  errdefer {
    self.failed = true
    self.pending = None
  }
  self.advance()
}

///|
fn Scan::advance(self : Scan) -> Image? raise ExrError {
  if self.pending is None {
    if self.next_chunk == self.ranges.length() {
      return None
    }
    let chunk = self.ranges[self.next_chunk]
    let y0 = imax(self.region.y0, chunk.y)
    let y1 = imin(
      self.region.y1,
      (chunk.y.to_int64() + chunk.rows.to_int64() - 1L).to_int(),
    )
    let w = Window::new(self.region.x0, y0, self.region.x1, y1)
    self.pending = Some(self.file.read(region=Some(w), channels=self.channels))
    self.next_chunk += 1
    self.pending_row = y0
    self.decoded += 1
  }
  let image = self.pending.unwrap()
  let w = image.data_window
  let rows = imin(self.batch_rows, w.y1 - self.pending_row + 1)
  let region = Window::new(
    w.x0,
    self.pending_row,
    w.x1,
    (self.pending_row.to_int64() + rows.to_int64() - 1L).to_int(),
  )
  let result = image.crop(region, limits=self.file.limits)
  if region.y1 == w.y1 {
    self.pending = None
  } else {
    self.pending_row += rows
  }
  Some(result)
}

///|
test "chunk scanner limits returned rows and does not decode a chunk twice" {
  let w = Window::new(-1, -20, 1, 17)
  let p = Plane::from_values(
    { name: "Z", kind: F32, linear: true, },
    w,
    Array::makei(w.pixels(), i => i.to_double()),
  )
  let file = ExrFile::open(encode(Image::new(w, [p])))
  let selection = ["Z"]
  let scan = file.scan(channels=Some(selection), batch_rows=3)
  selection.clear()
  let mut rows = 0
  let mut next_y = -20
  while scan.next() is Some(image) {
    assert_true(image.window().height() <= 3)
    assert_eq(image.window().y0, next_y)
    assert_eq(image.plane("Z").bits_at(-1, next_y), p.bits_at(-1, next_y))
    rows += image.window().height()
    next_y += image.window().height()
  }
  assert_eq(rows, 38)
  assert_eq(scan.chunks_decoded(), 3)
  assert_true(scan.next() is None)
}
