// Functional core: decisions over plain values read by the shell.

///|
using @browser {type KeyPress}

///|
priv enum Direction {
  Up
  Down
  Left
  Right
  First
  Last
}

///|
priv enum CardKeyAction {
  MoveFocus(Direction)
  FocusSearch
  OpenNewDocument
  LetBrowserHandle
}

///|
fn card_key_action(press : KeyPress) -> CardKeyAction {
  guard !press.modified && !press.composing else { LetBrowserHandle }
  match press.key {
    "ArrowUp" => MoveFocus(Up)
    "ArrowDown" => MoveFocus(Down)
    "ArrowLeft" => MoveFocus(Left)
    "ArrowRight" => MoveFocus(Right)
    "Home" => MoveFocus(First)
    "End" => MoveFocus(Last)
    "/" => FocusSearch
    "n" | "N" => OpenNewDocument
    _ => LetBrowserHandle
  }
}

///|
/// Every action except `LetBrowserHandle` replaces the key's default.
fn CardKeyAction::replaces_default(self : CardKeyAction) -> Bool {
  !(self is LetBrowserHandle)
}

///|
/// Escape leaves a field, except while it confirms an IME composition.
fn is_leaving_key(press : KeyPress) -> Bool {
  press.key == "Escape" && !press.composing
}

///|
/// Narrowest grid that still fits one card.
const MIN_GRID_WIDTH : Int = 160

///|
/// The grid width to lay cards out at, from the measured width of the
/// index's content box. Narrow windows still get room for one card.
fn grid_width_of(measured : Double) -> Int {
  measured.to_int().max(MIN_GRID_WIDTH)
}

///|
/// A card's box in grid pixels.
priv struct CardRect[K] {
  id : K
  left : Int
  top : Int
  width : Int
  height : Int
}

///|
fn[K] CardRect::right(self : CardRect[K]) -> Int {
  self.left + self.width
}

///|
fn[K] CardRect::bottom(self : CardRect[K]) -> Int {
  self.top + self.height
}

///|
/// The card an arrow key moves to from the focused card: the nearest card in
/// that direction that shares a column (Up/Down) or a row (Left/Right). At an
/// edge, Left and Right continue in reading order. `None` means no card lies
/// that way, so focus stays.
fn[K] neighbour(
  cards : Cursor[CardRect[K]],
  direction : Direction,
) -> CardRect[K]? {
  let from = cards.current
  let middle = (from.top + from.bottom()) / 2
  let mut best : (CardRect[K], Double)? = None
  for card in cards.others() {
    let shares_column = card.right().min(from.right()) -
      card.left.max(from.left) >
      1
    let shares_row = card.bottom().min(from.bottom()) - card.top.max(from.top) >
      1
    let column_drift = (card.left - from.left).abs().to_double() / 1000.0
    let row_drift = ((card.top + card.bottom()) / 2 - middle).abs().to_double() /
      1000.0
    let distance : Double? = match direction {
      Down if card.top >= from.bottom() && shares_column =>
        Some((card.top - from.bottom()).to_double() + column_drift)
      Up if card.bottom() <= from.top && shares_column =>
        Some((from.top - card.bottom()).to_double() + column_drift)
      Right if card.left >= from.right() && shares_row =>
        Some((card.left - from.right()).to_double() + row_drift)
      Left if card.right() <= from.left && shares_row =>
        Some((from.left - card.right()).to_double() + row_drift)
      _ => None
    }
    match (distance, best) {
      (Some(d), None) => best = Some((card, d))
      (Some(d), Some((_, b))) if d < b => best = Some((card, d))
      _ => ()
    }
  }
  match (best, direction) {
    (Some((card, _)), _) => Some(card)
    (None, First) => Some(cards.first())
    (None, Last) => Some(cards.last())
    (None, Right) => cards.next()
    (None, Left) => cards.previous()
    (None, Up | Down) => None
  }
}
