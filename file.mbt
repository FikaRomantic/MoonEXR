///|
pub(all) struct ChunkInfo {
  y : Int32
  rows : Int32
  offset : Int32
  encoded_bytes : Int32
  decoded_bytes : Int32
} derive(Debug, Eq)

///|
pub extend ChunkInfo with @debug.Debug::{to_repr}

///|
pub extend ChunkInfo with Eq::{equal, not_equal}

///|
pub struct ExrFile {
  priv bytes : Bytes
  priv header : Header
  priv chunks : Array[ChunkInfo]
  priv limits : Limits
}

///|
pub fn ExrFile::open(
  bytes : Bytes,
  limits~ : Limits = Limits::default(),
) -> ExrFile raise ExrError {
  let h = parse_header(bytes, limits)
  let lines = h.compression.scanlines()
  let height = h.data_window.height()
  let count = (height - 1) / lines + 1
  if count > limits.max_chunks {
    raise Limit("chunk directory entries")
  }
  let table_end = add(h.end, mul(count, 8))
  if table_end > bytes.length() {
    raise Invalid("truncated chunk offset table", h.end)
  }
  let table = reader(bytes[h.end:table_end].to_owned())
  let chunks : Array[ChunkInfo] = []
  let mut stride = 0
  for ch in h.channels {
    stride = add(stride, ch.kind.bytes())
  }
  let row_bytes = mul(h.data_window.width(), stride)
  for i = 0; i < count; i = i + 1 {
    let offset = index(table.uint(8))
    if offset < table_end || offset > bytes.length() - 8 {
      raise Invalid("chunk offset outside file body", offset)
    }
    let r = reader(bytes[offset:offset + 8].to_owned())
    let y = r.i32()
    let encoded_bytes = r.i32()
    let expected_y = (h.data_window.y0.to_int64() + mul(i, lines).to_int64()).to_int()
    if y != expected_y {
      raise Invalid("offset table row mismatch", offset)
    }
    let rows = imin(lines, height - i * lines)
    let decoded_bytes = mul(row_bytes, rows)
    if encoded_bytes <= 0 ||
      encoded_bytes > decoded_bytes ||
      encoded_bytes > bytes.length() - offset - 8 {
      raise Invalid("chunk payload size", offset + 4)
    }
    if h.compression == None && encoded_bytes != decoded_bytes {
      raise Invalid("uncompressed chunk size", offset + 4)
    }
    chunks.push({ y, rows, offset, encoded_bytes, decoded_bytes, })
  }
  let physical = chunks.copy()
  physical.sort_by((a, b) => a.offset.compare(b.offset))
  let mut previous_end = table_end
  for c in physical {
    if c.offset < previous_end {
      raise Invalid("duplicate/overlapping chunk range", c.offset)
    }
    previous_end = add(add(c.offset, 8), c.encoded_bytes)
  }
  { bytes, header: h, chunks, limits, }
}

///|
pub fn ExrFile::header(self : ExrFile) -> Header {
  self.header
}

///|
pub fn ExrFile::chunks(self : ExrFile) -> Array[ChunkInfo] {
  self.chunks.copy()
}

///|
/// Exact encoded chunks needed for a region; full input Bytes are still retained.
pub fn ExrFile::plan(self : ExrFile, region : Window) -> Array[ChunkInfo] {
  match self.header.data_window.intersection(region) {
    None => []
    Some(w) => {
      let first = ((w.y0.to_int64() - self.header.data_window.y0.to_int64()) /
      self.header.compression.scanlines().to_int64()).to_int()
      let last = ((w.y1.to_int64() - self.header.data_window.y0.to_int64()) /
      self.header.compression.scanlines().to_int64()).to_int()
      Array::makei(last - first + 1, i => self.chunks[first + i])
    }
  }
}

///|
fn ExrFile::unpack_chunk(
  self : ExrFile,
  info : ChunkInfo,
) -> Bytes raise ExrError {
  let begin = info.offset + 8
  unpack(
    self.bytes[begin:begin + info.encoded_bytes].to_owned(),
    self.header.compression,
    info.decoded_bytes,
  )
}
