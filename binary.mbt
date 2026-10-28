///|
pub suberror ExrError {
  Invalid(String, Int32)
  Unsupported(String)
  Limit(String)
} derive(Debug)

///|
pub extend ExrError with @debug.Debug::{to_repr}

///|
pub(all) struct Limits {
  max_file_bytes : Int32
  max_header_bytes : Int32
  max_pixels : Int32
  max_channels : Int32
  max_attributes : Int32
  max_decoded_bytes : Int32
} derive(Debug, Eq)

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub fn Limits::default() -> Limits {
  {
    max_file_bytes: 268435456,
    max_header_bytes: 1048576,
    max_pixels: 16777216,
    max_channels: 64,
    max_attributes: 1024,
    max_decoded_bytes: 268435456,
  }
}

///|
fn Limits::validate(self : Limits) -> Unit raise ExrError {
  if self.max_file_bytes < 8 ||
    self.max_header_bytes < 1 ||
    self.max_pixels < 1 ||
    self.max_channels < 1 ||
    self.max_attributes < 1 ||
    self.max_decoded_bytes < 1 {
    raise Limit("invalid resource limits")
  }
}

///|
fn add(a : Int32, b : Int32) -> Int32 raise ExrError {
  if a < 0 || b < 0 || a > 2147483647 - b {
    raise Limit("integer sum")
  }
  a + b
}

///|
fn mul(a : Int32, b : Int32) -> Int32 raise ExrError {
  if a < 0 || b < 0 || (a != 0 && b > 2147483647 / a) {
    raise Limit("integer product")
  }
  a * b
}

///|
fn imin(a : Int32, b : Int32) -> Int32 {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn imax(a : Int32, b : Int32) -> Int32 {
  if a > b {
    a
  } else {
    b
  }
}

///|
priv struct Reader {
  data : Bytes
  mut pos : Int32
  end : Int32
}

///|
fn reader(data : Bytes) -> Reader {
  { data, pos: 0, end: data.length(), }
}

///|
fn Reader::take(self : Reader, n : Int32) -> Bytes raise ExrError {
  if n < 0 || n > self.end - self.pos {
    raise Invalid("truncated input", self.pos)
  }
  let bytes = self.data[self.pos:self.pos + n].to_owned()
  self.pos += n
  bytes
}

///|
fn Reader::u8(self : Reader) -> Int32 raise ExrError {
  if self.pos >= self.end {
    raise Invalid("truncated byte", self.pos)
  }
  let v = self.data[self.pos].to_int()
  self.pos += 1
  v
}

///|
fn Reader::uint(self : Reader, n : Int32) -> UInt64 raise ExrError {
  let b = self.take(n)
  let mut v = 0UL
  for i = 0; i < n; i = i + 1 {
    v = v | (b[i].to_uint64() << (8 * i))
  }
  v
}

///|
fn Reader::i32(self : Reader) -> Int32 raise ExrError {
  self.uint(4).to_uint().reinterpret_as_int()
}

///|
fn Reader::f32(self : Reader) -> Double raise ExrError {
  Float::reinterpret_from_uint(self.uint(4).to_uint()).to_double()
}

///|
fn Reader::cstring(self : Reader, maximum : Int32) -> String raise ExrError {
  let begin = self.pos
  while self.pos < self.end && self.data[self.pos] != 0 {
    if self.pos - begin >= maximum {
      raise Limit("name length")
    }
    self.pos += 1
  }
  if self.pos == self.end {
    raise Invalid("unterminated string", begin)
  }
  let result = @utf8.decode(self.data[begin:self.pos]) catch {
    _ => raise Invalid("invalid UTF-8 name", begin)
  }
  self.pos += 1
  result
}

///|
fn index(v : UInt64) -> Int32 raise ExrError {
  if v > 2147483647UL {
    raise Limit("file offset exceeds host index")
  }
  v.to_int()
}

///|
priv struct Sink {
  bytes : Array[Byte]
}

///|
fn sink() -> Sink {
  { bytes: [], }
}

///|
fn Sink::size(self : Sink) -> Int32 {
  self.bytes.length()
}

///|
fn Sink::raw(self : Sink, bytes : Bytes) -> Unit {
  for b in bytes {
    self.bytes.push(b)
  }
}

///|
fn Sink::uint(self : Sink, value : UInt64, n : Int32) -> Unit {
  for i = 0; i < n; i = i + 1 {
    self.bytes.push((value >> (8 * i)).to_byte())
  }
}

///|
fn Sink::i32(self : Sink, v : Int32) -> Unit {
  self.uint(v.reinterpret_as_uint().to_uint64(), 4)
}

///|
fn Sink::f32(self : Sink, v : Double) -> Unit {
  self.uint(Float::from_double(v).reinterpret_as_uint().to_uint64(), 4)
}

///|
fn Sink::cstring(self : Sink, value : String) -> Unit {
  self.raw(@utf8.encode(value))
  self.bytes.push(0)
}

///|
fn Sink::finish(self : Sink) -> Bytes {
  Bytes::from_array(self.bytes)
}

///|
fn finite(v : Double) -> Bool {
  v == v && v.abs() <= 1.7976931348623157e308
}

///|
test "binary little endian preserves signed positions and float bits" {
  let w = sink()
  w.i32(-2147483648)
  w.f32(-0.0)
  w.cstring("层.Z")
  let r = reader(w.finish())
  assert_eq(r.i32(), -2147483648)
  assert_eq(r.uint(4), 2147483648UL)
  assert_eq(r.cstring(255), "层.Z")
  assert_true(
    try {
      ignore(r.u8())
      false
    } catch {
      _ => true
    },
  )
}

///|
test "binary checked sizes and terminated names" {
  assert_true(
    try {
      ignore(mul(2147483647, 2))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(add(2147483647, 1))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(reader(b"abc").cstring(255))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(reader(b"abc\x00").cstring(2))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(mul(0, 2147483647), 0)
}
