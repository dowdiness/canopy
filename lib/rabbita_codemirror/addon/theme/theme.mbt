///|
/// Typed wrapper for a CodeMirror theme extension. Factory
/// constructors (`dark()`, `light()`, `custom(...)`) land in P2.3;
/// this scaffold exists so the main package's `mount` /
/// `set_theme` signatures can reference `@theme.Theme` from the
/// first public release.

///|
#warnings("-unused_constructor")
pub struct Theme(@js_ffi.Extension)

///|
#cfg(target="js")
pub fn Theme::to_extension(self : Theme) -> @js_ffi.Extension {
  self.0
}
