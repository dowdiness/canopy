///|
fn Model::with_focus(self : Model, focused : Int?) -> Model {
  { ..self, focused, }
}

///|
fn Model::focus_next(self : Model) -> Model {
  if self.item_count == 0 {
    self.with_focus(None)
  } else {
    let next = match self.focused {
      Some(index) => (index + 1) % self.item_count
      None => 0
    }
    self.with_focus(Some(next))
  }
}

///|
fn Model::focus_previous(self : Model) -> Model {
  if self.item_count == 0 {
    self.with_focus(None)
  } else {
    let previous = match self.focused {
      Some(index) => (index + self.item_count - 1) % self.item_count
      None => self.item_count - 1
    }
    self.with_focus(Some(previous))
  }
}

///|
fn Model::focus_first(self : Model) -> Model {
  self.with_focus(first_focus(self.item_count))
}

///|
fn Model::focus_last(self : Model) -> Model {
  if self.item_count > 0 {
    self.with_focus(Some(self.item_count - 1))
  } else {
    self.with_focus(None)
  }
}

///|
fn Model::focus_item(self : Model, index : Int) -> Model {
  if self.valid_index(index) {
    self.with_focus(Some(index))
  } else {
    self
  }
}

///|
/// Create menu behavior state for a stable menu id and item count.
pub fn Model::new(id~ : String, item_count~ : Int) -> Model {
  let item_count = normalized_count(item_count)
  { id, item_count, focused: first_focus(item_count) }
}

///|
/// Reset the item count and move focus back to the first item when present.
pub fn Model::reset(self : Model, item_count~ : Int) -> Model {
  Model::new(id=self.id, item_count~)
}

///|
/// Apply one menu behavior message.
///
/// Navigation messages update roving focus. Activation, close, and text-key
/// messages are output signals for the consumer and leave behavior state
/// unchanged.
pub fn Model::update(self : Model, msg : Msg) -> Model {
  match msg {
    FocusNext => self.focus_next()
    FocusPrevious => self.focus_previous()
    FocusFirst => self.focus_first()
    FocusLast => self.focus_last()
    FocusItem(index) => self.focus_item(index)
    Activate(_) | Close | Key(_) => self
  }
}

///|
/// Whether handling this message should be followed by `Model::focus_cmd()`.
pub fn Msg::requests_focus(self : Msg) -> Bool {
  match self {
    FocusNext | FocusPrevious | FocusFirst | FocusLast => true
    FocusItem(_) | Activate(_) | Close | Key(_) => false
  }
}
