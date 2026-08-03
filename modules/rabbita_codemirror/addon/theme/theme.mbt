///|
/// Typed wrapper for a CodeMirror theme extension. Ecosystem factory
/// constructors (`dark()`, `light()`) are deferred until a synchronous
/// CM6 module access design exists.

///|
pub struct Theme(@js_ffi.Extension)

///|
/// Wrap a pre-built CodeMirror extension as a Theme. The Extension is
/// typically constructed by the consumer after they've loaded the
/// CodeMirror module, or via `@js_ffi.js_extension_combine([])` for "no
/// theme" (CM6 default styling).
///
/// Named factories that bind to specific CM6 ecosystem extensions
/// (`dark`, `light`, `default_keymap`, `vim`) are deferred - see plan
/// rev 3.6 for the design tension and the Q5-style decision table.
#cfg(target="js")
pub fn Theme::custom(extension : @js_ffi.Extension) -> Theme {
  Theme(extension)
}

///|
#cfg(target="js")
pub fn Theme::to_extension(self : Theme) -> @js_ffi.Extension {
  self.0
}
