///|
pub struct Header {
  priv data_window : Window
  priv display_window : Window
  priv channels : Array[Channel]
  priv compression : Compression
  priv attributes : Array[Attribute]
  priv line_order : Int32
  priv end : Int32
}

///|
pub fn Header::data_window(self : Header) -> Window {
  self.data_window
}

///|
pub fn Header::display_window(self : Header) -> Window {
  self.display_window
}

///|
pub fn Header::channels(self : Header) -> Array[Channel] {
  self.channels.copy()
}

///|
pub fn Header::compression(self : Header) -> Compression {
  self.compression
}

///|
pub fn Header::line_order(self : Header) -> Int32 {
  self.line_order
}

///|
pub fn Header::metadata(self : Header) -> Array[Attribute] {
  self.attributes.filter(a => !reserved(a.name))
}

///|
pub fn Header::attribute(self : Header, name : String) -> Attribute? {
  for a in self.attributes {
    if a.name == name {
      return Some(a)
    }
  }
  None
}

///|
fn required(
  attrs : Map[String, Attribute],
  name : String,
  kind : String,
) -> Bytes raise ExrError {
  match attrs.get(name) {
    Some(a) if a.kind == kind => a.value
    _ => raise Invalid("missing/wrong attribute: " + name, 8)
  }
}

///|
fn read_channels(
  bytes : Bytes,
  maximum_name : Int32,
  limits : Limits,
) -> Array[Channel] raise ExrError {
  let r = reader(bytes)
  let channels : Array[Channel] = []
  while true {
    let name = r.cstring(maximum_name)
    if name == "" {
      break
    }
    if channels.length() >= limits.max_channels {
      raise Limit("channel count")
    }
    let kind = pixel_type(r.i32())
    let linear = r.u8()
    if linear > 1 || r.uint(3) != 0UL {
      raise Invalid("channel flags/reserved bytes", r.pos)
    }
    if r.i32() != 1 || r.i32() != 1 {
      raise Unsupported("subsampled channels")
    }
    if channels.length() > 0 &&
      name_compare(channels[channels.length() - 1].name, name) >= 0 {
      raise Invalid("channel names must be unique and sorted", r.pos)
    }
    channels.push({ name, kind, linear: linear == 1, })
  }
  if channels.is_empty() || r.pos != r.end {
    raise Invalid("empty/trailing channel list", r.pos)
  }
  channels
}

///|
fn parse_header(bytes : Bytes, limits : Limits) -> Header raise ExrError {
  limits.validate()
  if bytes.length() > limits.max_file_bytes {
    raise Limit("input file bytes")
  }
  let r = reader(bytes)
  if r.uint(4) != 20000630UL {
    raise Invalid("OpenEXR magic", 0)
  }
  let version = r.uint(4).to_uint()
  if (version & 255U) != 2U {
    raise Unsupported("OpenEXR version")
  }
  if (version & 0xfffffb00U) != 0U {
    raise Unsupported("tiled, deep, multipart or unknown file flags")
  }
  let maximum_name = if (version & 1024U) != 0U { 255 } else { 31 }
  let attrs : Map[String, Attribute] = Map([])
  let ordered : Array[Attribute] = []
  while true {
    if r.pos >= limits.max_header_bytes {
      raise Limit("header byte budget")
    }
    let name = r.cstring(maximum_name)
    if name == "" {
      break
    }
    if ordered.length() >= limits.max_attributes {
      raise Limit("attribute count")
    }
    let kind = r.cstring(maximum_name)
    valid_name(kind)
    let size = r.i32()
    if size < 0 || size > limits.max_header_bytes - r.pos {
      raise Limit("attribute/header bytes")
    }
    let attr = { name, kind, value: r.take(size), }
    if attrs.contains(name) {
      raise Invalid("duplicate header attribute: " + name, r.pos)
    }
    attrs[name] = attr
    ordered.push(attr)
  }
  if r.pos > limits.max_header_bytes {
    raise Limit("header byte budget")
  }
  let data_window = read_window(required(attrs, "dataWindow", "box2i"))
  let display_window = read_window(required(attrs, "displayWindow", "box2i"))
  if data_window.pixels() > limits.max_pixels {
    raise Limit("data window pixels")
  }
  let channels = read_channels(
    required(attrs, "channels", "chlist"),
    maximum_name,
    limits,
  )
  let encoded_compression = required(attrs, "compression", "compression")
  if encoded_compression.length() != 1 {
    raise Invalid("compression length", 0)
  }
  let codec = compression(encoded_compression[0].to_int())
  let order = required(attrs, "lineOrder", "lineOrder")
  if order.length() != 1 || order[0].to_int() > 1 {
    raise Unsupported("non-monotonic scanline order")
  }
  let aspect = required(attrs, "pixelAspectRatio", "float")
  let center = required(attrs, "screenWindowCenter", "v2f")
  let screen = required(attrs, "screenWindowWidth", "float")
  if aspect.length() != 4 || center.length() != 8 || screen.length() != 4 {
    raise Invalid("screen/aspect attribute size", 0)
  }
  let ratio = reader(aspect).f32()
  let width = reader(screen).f32()
  let xy = reader(center)
  if !finite(ratio) ||
    ratio <= 0.0 ||
    !finite(width) ||
    width < 0.0 ||
    !finite(xy.f32()) ||
    !finite(xy.f32()) {
    raise Invalid("invalid screen/aspect values", 0)
  }
  let mut stride = 0
  for ch in channels {
    stride = add(stride, ch.kind.bytes())
  }
  if mul(data_window.pixels(), stride) > limits.max_decoded_bytes {
    raise Limit("logical decoded image bytes")
  }
  if attrs.contains("tiles") ||
    attrs.contains("chunkCount") ||
    attrs.contains("maxSamplesPerPixel") {
    raise Unsupported("non-flat header structure")
  }
  {
    data_window,
    display_window,
    channels,
    compression: codec,
    attributes: ordered,
    line_order: order[0].to_int(),
    end: r.pos,
  }
}

///|
fn channel_bytes(channels : Array[Channel]) -> Bytes {
  let s = sink()
  for ch in channels {
    s.cstring(ch.name)
    s.i32(ch.kind.code())
    s.uint(if ch.linear { 1UL } else { 0UL }, 1)
    s.uint(0UL, 3)
    s.i32(1)
    s.i32(1)
  }
  s.uint(0UL, 1)
  s.finish()
}

///|
fn header_attributes(
  data : Window,
  display : Window,
  channels : Array[Channel],
  codec : Compression,
) -> Array[Attribute] {
  [
    { name: "channels", kind: "chlist", value: channel_bytes(channels), },
    {
      name: "compression",
      kind: "compression",
      value: Bytes::from_array([codec.code().to_byte()]),
    },
    { name: "dataWindow", kind: "box2i", value: window_bytes(data), },
    { name: "displayWindow", kind: "box2i", value: window_bytes(display), },
    { name: "lineOrder", kind: "lineOrder", value: b"\x00", },
    { name: "pixelAspectRatio", kind: "float", value: b"\x00\x00\x80\x3f", },
    {
      name: "screenWindowCenter",
      kind: "v2f",
      value: b"\x00\x00\x00\x00\x00\x00\x00\x00",
    },
    { name: "screenWindowWidth", kind: "float", value: b"\x00\x00\x80\x3f", },
  ]
}

///|
fn header_bytes(attrs : Array[Attribute]) -> Bytes {
  let out = sink()
  out.uint(20000630UL, 4)
  out.uint(1026UL, 4)
  for a in attrs {
    write_attribute(out, a)
  }
  out.uint(0UL, 1)
  out.finish()
}

///|
test "header preserves offset windows unknown attributes and flags" {
  let window = Window::new(-4, 7, 8, 10)
  let attrs = header_attributes(
    window,
    window,
    [{ name: "Z", kind: F32, linear: false, }],
    Zip,
  )
  attrs.push({ name: "custom", kind: "opaque", value: b"\xff\x00", })
  let h = parse_header(header_bytes(attrs), Limits::default())
  assert_eq(h.data_window(), window)
  assert_eq(h.channels()[0].name, "Z")
  assert_eq(h.compression(), Zip)
  assert_eq(h.metadata()[0].value, b"\xff\x00")
  attrs.push(attrs[0])
  assert_true(
    try {
      ignore(parse_header(header_bytes(attrs), Limits::default()))
      false
    } catch {
      _ => true
    },
  )
}
