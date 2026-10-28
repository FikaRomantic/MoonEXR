///|
fn rle_decode(bytes : Bytes, expected : Int32) -> Bytes raise ExrError {
  let r = reader(bytes)
  let out = sink()
  while r.pos < r.end {
    let control = r.u8()
    if control >= 128 {
      let count = 256 - control
      if count > expected - out.size() {
        raise Invalid("RLE literal exceeds chunk", r.pos)
      }
      out.raw(r.take(count))
    } else {
      let count = control + 1
      if count > expected - out.size() {
        raise Invalid("RLE run exceeds chunk", r.pos)
      }
      let value = r.u8()
      for i = 0; i < count; i = i + 1 {
        out.uint(value.to_uint64(), 1)
      }
    }
  }
  if out.size() != expected {
    raise Invalid("RLE decoded byte count", r.pos)
  }
  out.finish()
}

///|
fn rle_encode(bytes : Bytes) -> Bytes {
  let out = sink()
  let mut at = 0
  while at < bytes.length() {
    let mut end = at + 1
    while end < bytes.length() && end - at < 128 && bytes[end] == bytes[at] {
      end += 1
    }
    if end - at >= 3 {
      out.uint((end - at - 1).to_uint64(), 1)
      out.uint(bytes[at].to_uint64(), 1)
      at = end
    } else {
      let start = at
      at += 1
      while at < bytes.length() && at - start < 127 {
        if at + 2 < bytes.length() &&
          bytes[at] == bytes[at + 1] &&
          bytes[at] == bytes[at + 2] {
          break
        }
        at += 1
      }
      out.uint((256 - (at - start)).to_uint64(), 1)
      out.raw(bytes[start:at].to_owned())
    }
  }
  out.finish()
}

///|
test "RLE literal repeat boundaries and signed -128 are interoperable" {
  assert_eq(rle_decode(b"\x02a\xfeBC", 5), b"aaaBC")
  assert_eq(rle_encode(b"aaaBC"), b"\x02a\xfeBC")
  let data = Bytes::from_array(Array::makei(128, i => i.to_byte()))
  let out = sink()
  out.uint(128UL, 1)
  out.raw(data)
  assert_eq(rle_decode(out.finish(), 128), data)
  for n in [1, 2, 3, 126, 127, 128, 129, 256, 1000] {
    let repeated = Bytes::from_array(Array::make(n, b'a'))
    assert_eq(rle_decode(rle_encode(repeated), n), repeated)
    let literals = Bytes::from_array(Array::makei(n, i => i.to_byte()))
    assert_eq(rle_decode(rle_encode(literals), n), literals)
  }
}

///|
test "RLE rejects expansion mismatch truncation and trailing packets" {
  for bytes in [b"\xff", b"\x7f", b"\x7fa", b"\xffa\x00b"] {
    assert_true(
      try {
        ignore(rle_decode(bytes, 1))
        false
      } catch {
        _ => true
      },
    )
  }
}
