///|
pub(all) struct SampleDifference {
  samples : Int32
  changed_bits : Int32
  finite_pairs : Int32
  maximum_absolute_error : Double?
} derive(Debug)

///|
pub extend SampleDifference with @debug.Debug::{to_repr}

///|
/// Compare identical channel types/windows, keeping NaN payload and signed-zero differences.
pub fn Plane::compare_samples(
  self : Plane,
  other : Plane,
) -> SampleDifference raise ExrError {
  if self.window != other.window || self.channel.kind != other.channel.kind {
    raise Invalid("comparison window or sample type", 0)
  }
  let (xmin, ymin, xmax, ymax) = self.window.bounds()
  let mut changed = 0
  let mut pairs = 0
  let mut maximum = 0.0
  for y = ymin; y <= ymax; y = y + 1 {
    for x = xmin; x <= xmax; x = x + 1 {
      if self.bits_at(x, y) != other.bits_at(x, y) {
        changed += 1
      }
      let a = self.value_at(x, y)
      let b = other.value_at(x, y)
      if finite(a) && finite(b) {
        pairs += 1
        let delta = if a >= b { a - b } else { b - a }
        if delta > maximum {
          maximum = delta
        }
      }
      // Avoid incrementing an Int32 maximum coordinate.
      if x == xmax {
        break
      }
    }
    if y == ymax {
      break
    }
  }
  {
    samples: self.window.pixels(),
    changed_bits: changed,
    finite_pairs: pairs,
    maximum_absolute_error: if pairs > 0 {
      Some(maximum)
    } else {
      None
    },
  }
}

///|
pub(all) struct MaskedStatistics {
  selected : Int32
  finite_samples : Int32
  nonfinite_samples : Int32
  minimum : Double?
  maximum : Double?
  mean : Double?
} derive(Debug)

///|
pub extend MaskedStatistics with @debug.Debug::{to_repr}

///|
/// Nonzero UINT32 mask selects samples. No thresholding or modification of stored planes.
pub fn Plane::masked_statistics(
  self : Plane,
  mask : Plane,
) -> MaskedStatistics raise ExrError {
  if self.window != mask.window || mask.channel.kind != U32 {
    raise Invalid("mask needs same window and UINT32 samples", 0)
  }
  let (xmin, ymin, xmax, ymax) = self.window.bounds()
  let mut selected = 0
  let mut count = 0
  let mut minimum : Double? = None
  let mut maximum : Double? = None
  let mut mean = 0.0
  for y = ymin; y <= ymax; y = y + 1 {
    for x = xmin; x <= xmax; x = x + 1 {
      if mask.bits_at(x, y) != 0U {
        selected += 1
        let value = self.value_at(x, y)
        if finite(value) {
          count += 1
          minimum = Some(
            match minimum {
              Some(m) => if value < m { value } else { m }
              None => value
            },
          )
          maximum = Some(
            match maximum {
              Some(m) => if value > m { value } else { m }
              None => value
            },
          )
          // Weighted form avoids overflowing value - mean for opposite extremes.
          mean = mean * ((count - 1).to_double() / count.to_double()) +
            value / count.to_double()
        }
      }
      if x == xmax {
        break
      }
    }
    if y == ymax {
      break
    }
  }
  {
    selected,
    finite_samples: count,
    nonfinite_samples: selected - count,
    minimum,
    maximum,
    mean: if count > 0 && finite(mean) {
      Some(mean)
    } else {
      None
    },
  }
}
