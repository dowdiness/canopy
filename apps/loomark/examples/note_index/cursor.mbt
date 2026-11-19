///|
using @vector {type Vector}

///|
/// A non-empty sequence with one item in focus. Holding one proves there is
/// something to show and something holding the tab stop, so code that receives
/// a cursor never checks for an empty list or a missing focus.
priv struct Cursor[T] {
  before : Vector[T]
  current : T
  after : Vector[T]
} derive(Eq)

///|
/// Focus the first item `is_wanted` accepts, or else the first item.
/// `None` means there are no items: the only case without a focus.
fn[T] Cursor::focus_on(
  items : Vector[T],
  is_wanted : (T) -> Bool,
) -> Cursor[T]? {
  let mut at = 0
  for i in 0..<items.length() {
    if is_wanted(items[i]) {
      at = i
      break
    }
  }
  Cursor::at(items, at)
}

///|
/// Focus the item at `at`, or `None` when there is none.
fn[T] Cursor::at(items : Vector[T], at : Int) -> Cursor[T]? {
  items
  .get(at)
  .map(current => {
    before: items.take(at),
    current,
    after: items.drop(at + 1),
  })
}

///|
/// Maps in reading order, so a stateful `to_item` such as a packer sees the
/// items in the order they are shown.
fn[T, U] Cursor::map(self : Cursor[T], to_item : (T) -> U) -> Cursor[U] {
  let before = self.before.map(to_item)
  let current = to_item(self.current)
  let after = self.after.map(to_item)
  { before, current, after, }
}

///|
fn[T] Cursor::to_array(self : Cursor[T]) -> Array[T] {
  [..self.before.to_array(), self.current, ..self.after.to_array()]
}

///|
fn[T] Cursor::length(self : Cursor[T]) -> Int {
  self.before.length() + 1 + self.after.length()
}

///|
fn[T] Cursor::first(self : Cursor[T]) -> T {
  self.before.get(0).unwrap_or(self.current)
}

///|
fn[T] Cursor::last(self : Cursor[T]) -> T {
  self.after.peek().unwrap_or(self.current)
}

///|
/// The item before the focus in reading order; none at the start.
fn[T] Cursor::previous(self : Cursor[T]) -> T? {
  self.before.peek()
}

///|
/// The item after the focus in reading order; none at the end.
fn[T] Cursor::next(self : Cursor[T]) -> T? {
  self.after.get(0)
}

///|
/// Every item except the focused one.
fn[T] Cursor::others(self : Cursor[T]) -> Vector[T] {
  self.before.concat(self.after)
}

///|
/// Maps every item in reading order, or `None` as soon as one maps to `None`.
fn[T, U] Cursor::map_all(self : Cursor[T], to_item : (T) -> U?) -> Cursor[U]? {
  let all = []
  for item in self.to_array() {
    guard to_item(item) is Some(mapped) else { return None }
    all.push(mapped)
  }
  Cursor::at(Vector(all), self.before.length())
}
