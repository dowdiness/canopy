///|
/// The parts of a key press that decide what it does.
pub(all) struct KeyPress {
  key : String
  /// Ctrl, Meta, or Alt is held; such shortcuts stay the browser's.
  modified : Bool
  /// The key confirms or edits an IME composition.
  composing : Bool
}

///|
/// Read the key press an event describes.
pub fn key_press(event : @dom.KeyboardEvent) -> KeyPress {
  {
    key: event.key(),
    modified: event.ctrl_key() || event.meta_key() || event.alt_key(),
    composing: event.is_composing(),
  }
}
