///|
fn main raise {
  let window = @exr.Window::new(100, 200, 131, 232)
  let channels : Array[@exr.Channel] = [
    { name: "sample.id", kind: U32, linear: true, },
    { name: "sensor.signal", kind: F32, linear: true, },
  ]
  let writer = @exr.Writer::new(window, channels, metadata=[
    @exr.Attribute::text("sensor.units", "relative intensity"),
    @exr.Attribute::integer("acquisition.frame", 7),
  ])
  let mut row = 0
  while row < window.height() {
    let n = if window.height() - row < 5 { window.height() - row } else { 5 }
    let batch_window = @exr.Window::new(100, 200 + row, 131, 200 + row + n - 1)
    let image = @exr.Image::new(batch_window, [
      @exr.Plane::from_values(
        channels[0],
        batch_window,
        Array::makei(32 * n, i => 4294967295.0 - (row * 32 + i).to_double()),
      ),
      @exr.Plane::from_values(
        channels[1],
        batch_window,
        Array::makei(32 * n, i => (row * 32 + i).to_double() / 2.0),
      ),
    ])
    writer.push(image)
    row += n
  }
  let file = @exr.ExrFile::open(writer.finish())
  let scan = file.scan(channels=Some(["sensor.signal"]), batch_rows=3)
  let mut pixels = 0
  let mut sum = 0.0
  while scan.next() is Some(batch) {
    let plane = batch.plane("sensor.signal")
    let stats = plane.statistics()
    pixels += stats.samples
    sum += stats.mean.unwrap() * stats.finite_samples.to_double()
  }
  assert_eq(pixels, 1056)
  assert_eq(sum, 278520.0)
  assert_eq(scan.chunks_decoded(), 3)
  assert_eq(file.read().plane("sample.id").bits_at(100, 200), 4294967295U)
  assert_eq(
    file.header().attribute("sensor.units").unwrap().as_text(),
    "relative intensity",
  )
  println(
    "scientific imaging: row-batch acquisition, exact UINT IDs, metadata and chunk-backed finite analysis verified",
  )
}
