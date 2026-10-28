///|
pub struct Window {
  priv x0 : Int32
  priv y0 : Int32
  priv x1 : Int32
  priv y1 : Int32
} derive(Debug, Eq)

///|
pub extend Window with @debug.Debug::{to_repr}

///|
pub extend Window with Eq::{equal, not_equal}

///|
pub fn Window::new(
  x0 : Int32,
  y0 : Int32,
  x1 : Int32,
  y1 : Int32,
) -> Window raise ExrError {
  let w = x1.to_int64() - x0.to_int64() + 1L
  let h = y1.to_int64() - y0.to_int64() + 1L
  if w <= 0L || h <= 0L || w > 2147483647L || h > 2147483647L {
    raise Invalid("empty or overflowing window", 0)
  }
  { x0, y0, x1, y1, }
}

///|
pub fn Window::bounds(self : Window) -> (Int32, Int32, Int32, Int32) {
  (self.x0, self.y0, self.x1, self.y1)
}

///|
pub fn Window::width(self : Window) -> Int32 {
  (self.x1.to_int64() - self.x0.to_int64() + 1L).to_int()
}

///|
pub fn Window::height(self : Window) -> Int32 {
  (self.y1.to_int64() - self.y0.to_int64() + 1L).to_int()
}

///|
pub fn Window::pixels(self : Window) -> Int32 raise ExrError {
  mul(self.width(), self.height())
}

///|
pub fn Window::contains(self : Window, x : Int32, y : Int32) -> Bool {
  x >= self.x0 && x <= self.x1 && y >= self.y0 && y <= self.y1
}

///|
pub fn Window::intersection(self : Window, other : Window) -> Window? {
  let x0 = imax(self.x0, other.x0)
  let y0 = imax(self.y0, other.y0)
  let x1 = imin(self.x1, other.x1)
  let y1 = imin(self.y1, other.y1)
  if x0 > x1 || y0 > y1 {
    None
  } else {
    Some({ x0, y0, x1, y1, })
  }
}

///|
fn Window::offset(self : Window, x : Int32, y : Int32) -> Int32 raise ExrError {
  if !self.contains(x, y) {
    raise Invalid("coordinate outside data window", 0)
  }
  add(mul(y - self.y0, self.width()), x - self.x0)
}

///|
fn read_window(bytes : Bytes) -> Window raise ExrError {
  if bytes.length() != 16 {
    raise Invalid("box2i length", 0)
  }
  let r = reader(bytes)
  Window::new(r.i32(), r.i32(), r.i32(), r.i32())
}

///|
fn window_bytes(box : Window) -> Bytes {
  let s = sink()
  s.i32(box.x0)
  s.i32(box.y0)
  s.i32(box.x1)
  s.i32(box.y1)
  s.finish()
}

///|
test "inclusive windows retain negative coordinates and intersection" {
  let a = Window::new(-3, -2, 2, 1)
  assert_eq(a.width(), 6)
  assert_eq(a.height(), 4)
  assert_eq(a.pixels(), 24)
  assert_eq(a.offset(2, 1), 23)
  assert_eq(
    a.intersection(Window::new(1, 0, 8, 5)),
    Some(Window::new(1, 0, 2, 1)),
  )
  assert_eq(a.intersection(Window::new(3, 0, 8, 5)), None)
  assert_eq(read_window(window_bytes(a)), a)
}

///|
test "window dimensions and linear indices reject overflow" {
  assert_true(
    try {
      ignore(Window::new(-2147483648, 0, 2147483647, 0))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(Window::new(2, 0, 1, 0))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(Window::new(0, 0, 99999, 99999).pixels())
      false
    } catch {
      _ => true
    },
  )
  let singleton = Window::new(2147483647, -2147483648, 2147483647, -2147483648)
  assert_eq(singleton.pixels(), 1)
  assert_eq(singleton.offset(2147483647, -2147483648), 0)
}
