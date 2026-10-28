///|
fn codec(name : String) -> @exr.Compression raise {
  match name {
    "none" => None
    "rle" => Rle
    "zips" => Zips
    "zip" => Zip
    _ => raise Failure("codec must be none/rle/zips/zip")
  }
}

///|
async fn load(path : String) -> @exr.ExrFile {
  if @fs.file_size(path[:]) > @exr.Limits::default().max_file_bytes.to_int64() {
    raise Failure("input file exceeds byte budget")
  }
  @exr.ExrFile::open(@fs.read_file(path[:]).binary())
}

///|
async fn run() -> Unit {
  let args = @env.args()
  if args.length() == 5 && args[1] == "rewrite" {
    let image = load(args[2]).read()
    let bytes = @exr.encode(image, compression=codec(args[4]))
    @fs.write_file(args[3][:], bytes, create_mode=CreateNew)
    println("rewritten EXR sample bits and metadata")
    return
  }
  if args.length() != 3 {
    raise Failure(
      "usage: moonexr inspect FILE | bits FILE | demo NEW | rewrite INPUT NEW none|rle|zips|zip",
    )
  }
  if args[1] == "demo" {
    let w = @exr.Window::new(-2, 3, 1, 5)
    let image = @exr.Image::new(
      w,
      [
        @exr.Plane::from_values(
          { name: "R", kind: F16, linear: false, },
          w,
          Array::makei(12, i => (i - 2).to_double() / 2.0),
        ),
        @exr.Plane::from_values(
          { name: "Z", kind: F32, linear: true, },
          w,
          Array::makei(12, i => (i * i).to_double()),
        ),
        @exr.Plane::from_values(
          { name: "id", kind: U32, linear: true, },
          w,
          Array::makei(12, i => 4294967295.0 - i.to_double()),
        ),
      ],
      metadata=[
        @exr.Attribute::text("comments", "MoonEXR original synthetic image"),
      ],
    )
    @fs.write_file(args[2][:], @exr.encode(image), create_mode=CreateNew)
    println("created EXR")
    return
  }
  let file = load(args[2])
  if args[1] == "inspect" {
    let h = file.header()
    let (x0, y0, x1, y1) = h.data_window().bounds()
    println(
      Json::object({
        "window": Json::array(
          [x0, y0, x1, y1].map(v => Json::number(v.to_double())),
        ),
        "channels": Json::array(h.channels().map(c => Json::string(c.name))),
        "chunks": Json::number(file.chunks().length().to_double()),
        "metadata": Json::array(h.metadata().map(a => Json::string(a.name))),
      }).stringify(),
    )
  } else if args[1] == "bits" {
    let img = file.read()
    let (x0, y0, _, _) = img.window().bounds()
    let channels : Map[String, Json] = Map([])
    for ch in img.channels() {
      let p = img.plane(ch.name)
      let values : Array[Json] = []
      for row = 0; row < img.window().height(); row = row + 1 {
        for column = 0; column < img.window().width(); column = column + 1 {
          values.push(
            Json::number(p.bits_at(x0 + column, y0 + row).to_double()),
          )
        }
      }
      channels[ch.name] = Json::array(values)
    }
    println(Json::object(channels).stringify())
  } else {
    raise Failure("unknown command")
  }
}

///|
async fn main {
  run() catch {
    @exr.ExrError::Invalid(message, offset) =>
      raise Failure("invalid EXR at \{offset}: \{message}")
    @exr.ExrError::Unsupported(message) =>
      raise Failure("unsupported EXR: \{message}")
    @exr.ExrError::Limit(message) =>
      raise Failure("EXR resource limit: \{message}")
    error => raise error
  }
}
