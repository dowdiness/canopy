///|
/// Typed wrapper for a CodeMirror keymap extension. Ecosystem factory
/// constructors (`default_keymap()`, `vim()`) are deferred until a
/// synchronous CM6 module access design exists.

///|
pub struct Keymap(@js_ffi.Extension)

///|
/// Wrap a pre-built CodeMirror extension as a Keymap. See `Theme::custom`
/// for usage notes; the `default_keymap` and `vim` factories are
/// deferred per plan rev 3.6.
#cfg(target="js")
pub fn Keymap::from_raw(extension : @js_ffi.Extension) -> Keymap {
  Keymap(extension)
}

///|
#cfg(target="js")
pub fn Keymap::to_extension(self : Keymap) -> @js_ffi.Extension {
  self.0
}
