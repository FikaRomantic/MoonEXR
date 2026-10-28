///|
pub(all) enum Compression {
  None
  Rle
  Zips
  Zip
} derive(Debug, Eq)

///|
pub extend Compression with @debug.Debug::{to_repr}

///|
pub extend Compression with Eq::{equal, not_equal}

///|
pub fn Compression::scanlines(self : Compression) -> Int32 {
  if self == Zip {
    16
  } else {
    1
  }
}

///|
fn Compression::code(self : Compression) -> Int32 {
  match self {
    None => 0
    Rle => 1
    Zips => 2
    Zip => 3
  }
}

///|
fn compression(code : Int32) -> Compression raise ExrError {
  match code {
    0 => None
    1 => Rle
    2 => Zips
    3 => Zip
    _ => raise Unsupported("compression codec")
  }
}

///|
fn adler32(bytes : Bytes) -> UInt32 {
  let mut a = 1U
  let mut b = 0U
  for v in bytes {
    a = (a + v.to_uint()) % 65521U
    b = (b + a) % 65521U
  }
  (b << 16) | a
}

///|
fn zlib_encode(bytes : Bytes) -> Bytes {
  let out = sink()
  out.raw(b"\x78\x9c")
  out.raw(@flate.deflate_all(bytes))
  let check = adler32(bytes)
  for i = 3; i >= 0; i = i - 1 {
    out.uint(((check >> (i * 8)) & 255U).to_uint64(), 1)
  }
  out.finish()
}

///|
fn zlib_decode(bytes : Bytes, expected : Int32) -> Bytes raise ExrError {
  if bytes.length() < 6 {
    raise Invalid("truncated zlib stream", 0)
  }
  let cmf = bytes[0].to_int()
  let flg = bytes[1].to_int()
  if (cmf & 15) != 8 ||
    cmf >> 4 > 7 ||
    ((cmf << 8) + flg) % 31 != 0 ||
    (flg & 32) != 0 {
    raise Invalid("unsupported zlib header/dictionary", 0)
  }
  let end = bytes.length() - 4
  let raw = @flate.inflate_exact(bytes[2:end], max_output=expected) catch {
    _ => raise Invalid("invalid/oversized DEFLATE chunk", 2)
  }
  if raw.length() != expected {
    raise Invalid("zlib decoded byte count", 0)
  }
  let mut checksum = 0U
  for i = end; i < bytes.length(); i = i + 1 {
    checksum = (checksum << 8) | bytes[i].to_uint()
  }
  if checksum != adler32(raw) {
    raise Invalid("zlib Adler32 mismatch", end)
  }
  raw
}

///|
fn pack(raw : Bytes, codec : Compression) -> Bytes {
  if codec == None {
    return raw
  }
  let shuffled = predict(raw)
  let encoded = if codec == Rle {
    rle_encode(shuffled)
  } else {
    zlib_encode(shuffled)
  }
  if encoded.length() < raw.length() {
    encoded
  } else {
    raw
  }
}

///|
fn unpack(
  bytes : Bytes,
  codec : Compression,
  expected : Int32,
) -> Bytes raise ExrError {
  if bytes.length() == expected {
    return bytes
  }
  if expected <= 0 || bytes.length() > expected || codec == None {
    raise Invalid("chunk encoded byte count", 0)
  }
  unpredict(
    if codec == Rle {
      rle_decode(bytes, expected)
    } else {
      zlib_decode(bytes, expected)
    },
  )
}

///|
test "compression codecs use raw fallback and exact decoded lengths" {
  for n in [2, 4, 25, 512, 4096] {
    for codec in [None, Rle, Zips, Zip] {
      let raw = Bytes::from_array(Array::makei(n, i => (i / 128).to_byte()))
      assert_eq(unpack(pack(raw, codec), codec, n), raw)
      let noisy = Bytes::from_array(
        Array::makei(n, i => ((i * 111 + i * i) % 256).to_byte()),
      )
      assert_eq(unpack(pack(noisy, codec), codec, n), noisy)
    }
  }
  assert_eq(pack(b"\x00\xff", Zip), b"\x00\xff")
  let z = zlib_encode(b"hello hello hello")
  assert_eq(zlib_decode(z, 17), b"hello hello hello")
  assert_true(
    try {
      ignore(zlib_decode(z, 16))
      false
    } catch {
      _ => true
    },
  )
}
