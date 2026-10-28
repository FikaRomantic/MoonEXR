///|
pub struct ReadResult {
  image : Image
  chunks_decoded : Int32
  bytes_decoded : Int32
}

///|
fn selected_channels(
  channels : Array[Channel],
  selection : Array[String]?,
) -> Array[Channel] raise ExrError {
  match selection {
    None => channels.copy()
    Some(names) => {
      if names.is_empty() {
        raise Invalid("empty channel selection", 0)
      }
      let seen : Map[String, Bool] = Map([])
      let selected : Array[Channel] = []
      for name in names {
        if seen.contains(name) {
          raise Invalid("duplicate selected channel", 0)
        }
        seen[name] = true
        let mut found = false
        for ch in channels {
          if ch.name == name {
            selected.push(ch)
            found = true
            break
          }
        }
        if !found {
          raise Invalid("missing selected channel: " + name, 0)
        }
      }
      selected.sort_by((a, b) => name_compare(a.name, b.name))
      selected
    }
  }
}

///|
pub fn ExrFile::read(
  self : ExrFile,
  region~ : Window? = None,
  channels~ : Array[String]? = None,
) -> Image raise ExrError {
  self.read_with_stats(region~, channels~).image
}

///|
pub fn ExrFile::read_with_stats(
  self : ExrFile,
  region~ : Window? = None,
  channels~ : Array[String]? = None,
) -> ReadResult raise ExrError {
  let h = self.header
  let window = match region {
    None => h.data_window
    Some(w) =>
      match w.intersection(h.data_window) {
        Some(inside) => inside
        None => raise Invalid("region does not intersect data window", 0)
      }
  }
  let selected = selected_channels(h.channels, channels)
  let buffers : Array[Array[Byte]] = []
  let destinations : Map[String, Int32] = Map([])
  for i = 0; i < selected.length(); i = i + 1 {
    destinations[selected[i].name] = i
    buffers.push(
      Array::make(mul(window.pixels(), selected[i].kind.bytes()), b'\x00'),
    )
  }
  let chunks = self.plan(window)
  let mut bytes_decoded = 0
  for info in chunks {
    let raw = self.unpack_chunk(info)
    bytes_decoded = add(bytes_decoded, raw.length())
    let r = reader(raw)
    for row = 0; row < info.rows; row = row + 1 {
      let y = (info.y.to_int64() + row.to_int64()).to_int()
      for ch in h.channels {
        let width = ch.kind.bytes()
        let row_bytes = mul(h.data_window.width(), width)
        match destinations.get(ch.name) {
          Some(destination) if y >= window.y0 && y <= window.y1 => {
            let start = add(r.pos, mul(window.x0 - h.data_window.x0, width))
            let count = mul(window.width(), width)
            let into = mul(mul(y - window.y0, window.width()), width)
            for i = 0; i < count; i = i + 1 {
              buffers[destination][into + i] = raw[start + i]
            }
          }
          _ => ()
        }
        r.pos += row_bytes
      }
    }
    if r.pos != r.end {
      raise Invalid("chunk layout byte count", info.offset)
    }
  }
  let planes = selected.mapi((i, ch) => {
    Plane::from_bits(
      ch,
      window,
      Bytes::from_array(buffers[i]),
      limits=self.limits,
    )
  })
  let center = reader(h.attribute("screenWindowCenter").unwrap().value)
  let image = Image::new(
    window,
    planes,
    display=h.display_window,
    metadata=h.metadata(),
    pixel_aspect=h.attribute("pixelAspectRatio").unwrap().as_real(),
    screen_center=(center.f32(), center.f32()),
    screen_width=h.attribute("screenWindowWidth").unwrap().as_real(),
    limits=self.limits,
  )
  { image, chunks_decoded: chunks.length(), bytes_decoded, }
}
