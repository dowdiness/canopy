///|
/// Typed wrapper for a CodeMirror keymap extension. Factory
/// constructors (`default_keymap()`, `vim()`, `from_raw(...)`) land
/// in P2.3; this scaffold exists so the main package's `mount` /
/// `set_keymap` signatures can reference `@keymap.Keymap` from the
/// first public release.

///|
#warnings("-unused_constructor")
pub struct Keymap(@js_ffi.Extension)

///|
#cfg(target="js")
pub fn Keymap::to_extension(self : Keymap) -> @js_ffi.Extension {
  self.0
}
