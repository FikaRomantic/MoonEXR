///|
pub(all) struct PlaneStatistics {
  samples : Int32
  finite_samples : Int32
  nan_samples : Int32
  positive_infinities : Int32
  negative_infinities : Int32
  negative_zeros : Int32
  minimum : Double?
  maximum : Double?
  mean : Double?
  population_variance : Double?
} derive(Debug)

///|
pub extend PlaneStatistics with @debug.Debug::{to_repr}

///|
/// Welford's online finite-only moments. Extreme values can overflow variance;
/// in that case variance is None, rather than an apparently valid infinity.
pub fn Plane::statistics(self : Plane) -> PlaneStatistics raise ExrError {
  let mut count = 0
  let mut nan = 0
  let mut positive = 0
  let mut negative = 0
  let mut minus_zero = 0
  let mut minimum : Double? = None
  let mut maximum : Double? = None
  let mut mean = 0.0
  let mut m2 = 0.0
  let r = reader(self.data)
  while r.pos < r.end {
    let bits = r.uint(self.channel.kind.bytes()).to_uint()
    let value = match self.channel.kind {
      U32 => bits.to_double()
      F16 => half_value(bits.reinterpret_as_int())
      F32 => Float::reinterpret_from_uint(bits).to_double()
    }
    if value.is_nan() {
      nan += 1
    } else if value.is_pos_inf() {
      positive += 1
    } else if value.is_neg_inf() {
      negative += 1
    } else {
      if value == 0.0 &&
        (
          (self.channel.kind == F16 && bits == 32768U) ||
          (self.channel.kind == F32 && bits == 2147483648U)
        ) {
        minus_zero += 1
      }
      count += 1
      minimum = Some(
        match minimum {
          None => value
          Some(x) => if value < x { value } else { x }
        },
      )
      maximum = Some(
        match maximum {
          None => value
          Some(x) => if value > x { value } else { x }
        },
      )
      let delta = value - mean
      mean += delta / count.to_double()
      m2 += delta * (value - mean)
    }
  }
  {
    samples: self.window.pixels(),
    finite_samples: count,
    nan_samples: nan,
    positive_infinities: positive,
    negative_infinities: negative,
    negative_zeros: minus_zero,
    minimum,
    maximum,
    mean: if count > 0 && finite(mean) {
      Some(mean)
    } else {
      None
    },
    population_variance: if count > 0 && finite(m2) {
      Some(m2 / count.to_double())
    } else {
      None
    },
  }
}

///|
pub(all) struct Histogram {
  lower : Double
  upper : Double
  bins : Array[Int32]
  below : Int32
  above : Int32
  nonfinite : Int32
}

///|
pub fn Plane::histogram(
  self : Plane,
  lower : Double,
  upper : Double,
  bins : Int32,
) -> Histogram raise ExrError {
  if !finite(lower) ||
    !finite(upper) ||
    lower >= upper ||
    !finite(upper - lower) ||
    bins < 1 ||
    bins > 65536 {
    raise Invalid("histogram range/bin budget", 0)
  }
  let counts = Array::make(bins, 0)
  let mut below = 0
  let mut above = 0
  let mut nonfinite = 0
  let (x0, y0, _, _) = self.window.bounds()
  for row = 0; row < self.window.height(); row = row + 1 {
    for col = 0; col < self.window.width(); col = col + 1 {
      let value = self.value_at(x0 + col, y0 + row)
      if !finite(value) {
        nonfinite += 1
      } else if value < lower {
        below += 1
      } else if value > upper {
        above += 1
      } else {
        let slot = imin(
          bins - 1,
          ((value - lower) / (upper - lower) * bins.to_double()).to_int(),
        )
        counts[slot] += 1
      }
    }
  }
  { lower, upper, bins: counts, below, above, nonfinite, }
}

///|
test "statistics separate finite moments NaNs infinities and negative zero" {
  let w = Window::new(0, 0, 7, 0)
  let p = Plane::from_values({ name: "Y", kind: F32, linear: false, }, w, [
    1.0,
    2.0,
    3.0,
    -0.0,
    0.0,
    Float::reinterpret_from_uint(0x7fc00000U).to_double(),
    Float::reinterpret_from_uint(0x7f800000U).to_double(),
    Float::reinterpret_from_uint(0xff800000U).to_double(),
  ])
  let stats = p.statistics()
  assert_eq(stats.samples, 8)
  assert_eq(stats.finite_samples, 5)
  assert_eq(stats.negative_zeros, 1)
  assert_eq(stats.nan_samples, 1)
  assert_eq(stats.positive_infinities, 1)
  assert_eq(stats.negative_infinities, 1)
  assert_eq(stats.mean, Some(1.2))
  assert_true((stats.population_variance.unwrap() - 1.36).abs() < 0.000001)
  let h = p.histogram(0.0, 2.0, 2)
  assert_eq(h.bins, [2, 2])
  assert_eq(h.above, 1)
  assert_eq(h.nonfinite, 3)
}
