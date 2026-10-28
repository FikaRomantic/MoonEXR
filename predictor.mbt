///|
/// OpenEXR lossless byte shuffle followed by a modulo-256 predictor.
fn predict(raw : Bytes) -> Bytes {
  let n = raw.length()
  let half = (n + 1) / 2
  let shuffled = Array::make(n, b'\x00')
  for i = 0; i < n; i = i + 1 {
    shuffled[if i % 2 == 0 { i / 2 } else { half + i / 2 }] = raw[i]
  }
  let out = Array::make(n, b'\x00')
  for i = 0; i < n; i = i + 1 {
    out[i] = if i == 0 {
      shuffled[i]
    } else {
      (shuffled[i].to_int() - shuffled[i - 1].to_int() + 128).to_byte()
    }
  }
  Bytes::from_array(out)
}

///|
fn unpredict(encoded : Bytes) -> Bytes {
  let n = encoded.length()
  let half = (n + 1) / 2
  let unpacked = Array::make(n, b'\x00')
  let mut previous = 0
  for i = 0; i < n; i = i + 1 {
    previous = if i == 0 {
      encoded[i].to_int()
    } else {
      (previous + encoded[i].to_int() - 128) & 255
    }
    unpacked[i] = previous.to_byte()
  }
  Bytes::from_array(
    Array::makei(n, i => unpacked[if i % 2 == 0 { i / 2 } else { half + i / 2 }]),
  )
}

///|
test "EXR predictor specified odd and even byte ordering" {
  assert_eq(predict(b"\x01\x02\x03\x04\x05"), b"\x01\x82\x82\x7d\x82")
  for n = 0; n < 512; n = n + 1 {
    let bytes = Bytes::from_array(
      Array::makei(n, i => ((i * i + i * 33) & 255).to_byte()),
    )
    assert_eq(unpredict(predict(bytes)), bytes)
  }
}
