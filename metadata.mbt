///|
pub(all) struct Attribute {
  name : String
  kind : String
  value : Bytes
} derive(Debug, Eq)

///|
pub extend Attribute with @debug.Debug::{to_repr}

///|
pub extend Attribute with Eq::{equal, not_equal}

///|
fn reserved(name : String) -> Bool {
  match name {
    "channels"
    | "compression"
    | "dataWindow"
    | "displayWindow"
    | "lineOrder"
    | "pixelAspectRatio"
    | "screenWindowCenter"
    | "screenWindowWidth"
    | "tiles"
    | "type"
    | "name"
    | "version"
    | "chunkCount"
    | "maxSamplesPerPixel" => true
    _ => false
  }
}

///|
fn Attribute::validate(
  self : Attribute,
  maximum : Int32,
) -> Unit raise ExrError {
  valid_name(self.name)
  valid_name(self.kind)
  if self.value.length() > maximum {
    raise Limit("attribute payload")
  }
}

///|
pub fn Attribute::text(
  name : String,
  text : String,
) -> Attribute raise ExrError {
  valid_name(name)
  { name, kind: "string", value: @utf8.encode(text), }
}

///|
pub fn Attribute::as_text(self : Attribute) -> String raise ExrError {
  if self.kind != "string" {
    raise Invalid("attribute is not string", 0)
  }
  @utf8.decode(self.value) catch {
    _ => raise Invalid("invalid UTF-8 text attribute", 0)
  }
}

///|
pub fn Attribute::integer(
  name : String,
  value : Int32,
) -> Attribute raise ExrError {
  valid_name(name)
  let b = sink()
  b.i32(value)
  { name, kind: "int", value: b.finish(), }
}

///|
pub fn Attribute::as_integer(self : Attribute) -> Int32 raise ExrError {
  if self.kind != "int" || self.value.length() != 4 {
    raise Invalid("attribute is not int", 0)
  }
  reader(self.value).i32()
}

///|
pub fn Attribute::real(
  name : String,
  value : Double,
) -> Attribute raise ExrError {
  valid_name(name)
  if !finite(value) || Float::from_double(value).is_inf() {
    raise Invalid("finite float attribute required", 0)
  }
  let b = sink()
  b.f32(value)
  { name, kind: "float", value: b.finish(), }
}

///|
pub fn Attribute::as_real(self : Attribute) -> Double raise ExrError {
  if self.kind != "float" || self.value.length() != 4 {
    raise Invalid("attribute is not float", 0)
  }
  reader(self.value).f32()
}

///|
/// Eight xy coordinates: red, green, blue and white, in that order.
pub fn Attribute::chromaticities(
  values : Array[Double],
) -> Attribute raise ExrError {
  if values.length() != 8 {
    raise Invalid("chromaticities need eight xy values", 0)
  }
  let b = sink()
  for v in values {
    if !finite(v) || Float::from_double(v).is_inf() {
      raise Invalid("finite chromaticities required", 0)
    }
    b.f32(v)
  }
  { name: "chromaticities", kind: "chromaticities", value: b.finish(), }
}

///|
pub fn Attribute::as_chromaticities(
  self : Attribute,
) -> Array[Double] raise ExrError {
  if self.kind != "chromaticities" || self.value.length() != 32 {
    raise Invalid("chromaticities type/size", 0)
  }
  let r = reader(self.value)
  Array::makei(8, _ => r.f32())
}

///|
fn write_attribute(out : Sink, attr : Attribute) -> Unit {
  out.cstring(attr.name)
  out.cstring(attr.kind)
  out.i32(attr.value.length())
  out.raw(attr.value)
}

///|
test "typed metadata helpers retain Unicode text and unknown bytes" {
  let a = Attribute::text("comments", "光谱\x00内嵌")
  assert_eq(a.as_text(), "光谱\x00内嵌")
  assert_eq(Attribute::integer("frame", -123).as_integer(), -123)
  assert_eq(Attribute::real("exposure", 2.5).as_real(), 2.5)
  let coords = [0.64, 0.33, 0.3, 0.6, 0.15, 0.06, 0.3127, 0.329]
  let c = Attribute::chromaticities(coords).as_chromaticities()
  assert_true((c[0] - coords[0]).abs() < 0.000001)
  assert_true(
    try {
      ignore(a.as_integer())
      false
    } catch {
      _ => true
    },
  )
  assert_true(reserved("compression"))
  assert_false(reserved("custom.data"))
}
