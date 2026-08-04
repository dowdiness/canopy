///|
pub struct Model {
  priv id : String
  priv item_count : Int
  priv focused : Int?
}

///|
pub(all) enum Msg {
  FocusNext
  FocusPrevious
  FocusFirst
  FocusLast
  FocusItem(Int)
  Activate(Int)
  Close
  Key(String)
}

///|
fn normalized_count(item_count : Int) -> Int {
  item_count.max(0)
}

///|
fn first_focus(item_count : Int) -> Int? {
  if item_count > 0 {
    Some(0)
  } else {
    None
  }
}

///|
fn Model::valid_index(self : Model, index : Int) -> Bool {
  index >= 0 && index < self.item_count
}
