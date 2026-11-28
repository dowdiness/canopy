///|
#derive(Eq)
pub struct Model {
  priv id : String
  priv item_count : Int32
  priv focused : Int32?
}

///|
pub(all) enum Msg {
  FocusNext
  FocusPrevious
  FocusFirst
  FocusLast
  FocusItem(Int32)
  Activate(Int32)
  Close
  Key(String)
}

///|
fn normalized_count(item_count : Int32) -> Int32 {
  item_count.max(0)
}

///|
fn first_focus(item_count : Int32) -> Int32? {
  if item_count > 0 {
    Some(0)
  } else {
    None
  }
}

///|
fn Model::valid_index(self : Model, index : Int32) -> Bool {
  index >= 0 && index < self.item_count
}

///|
pub extend Model with Eq::{equal, not_equal}
