///|
/// A non-empty sequence with one item in focus. Holding one proves there is
/// something to show and something holding the tab stop, so code that receives
/// a cursor never checks for an empty list or a missing focus.
priv struct Cursor[T] {
  before : Array[T]
  current : T
  after : Array[T]
} derive(Eq)

///|
/// Focus the first item `is_wanted` accepts, or else the first item.
/// `None` means there are no items: the only case without a focus.
fn[T] Cursor::focus_on(items : Array[T], is_wanted : (T) -> Bool) -> Cursor[T]? {
  let at = match items.search_by(is_wanted) {
    Some(i) => i
    None => 0
  }
  match items.get(at) {
    Some(current) =>
      Some({
        before: items[:at].to_owned(),
        current,
        after: items[at + 1:].to_owned(),
      })
    None => None
  }
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
  [..self.before, self.current, ..self.after]
}

///|
fn[T] Cursor::length(self : Cursor[T]) -> Int {
  self.before.length() + 1 + self.after.length()
}

///|
fn[T] Cursor::first(self : Cursor[T]) -> T {
  match self.before {
    [first, ..] => first
    [] => self.current
  }
}

///|
fn[T] Cursor::last(self : Cursor[T]) -> T {
  match self.after {
    [.., last] => last
    [] => self.current
  }
}

///|
/// The item before the focus in reading order; none at the start.
fn[T] Cursor::previous(self : Cursor[T]) -> T? {
  self.before.last()
}

///|
/// The item after the focus in reading order; none at the end.
fn[T] Cursor::next(self : Cursor[T]) -> T? {
  self.after.get(0)
}

///|
/// Every item except the focused one.
fn[T] Cursor::others(self : Cursor[T]) -> Array[T] {
  [..self.before, ..self.after]
}

///|
/// Maps every item in reading order, or `None` as soon as one maps to `None`.
fn[T, U] Cursor::map_all(self : Cursor[T], to_item : (T) -> U?) -> Cursor[U]? {
  let all = []
  for item in self.to_array() {
    guard to_item(item) is Some(mapped) else { return None }
    all.push(mapped)
  }
  let at = self.before.length()
  Some({
    before: all[:at].to_owned(),
    current: all[at],
    after: all[at + 1:].to_owned(),
  })
}
