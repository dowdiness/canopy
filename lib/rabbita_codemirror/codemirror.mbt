///|
/// Public API for the CodeMirror–Rabbita binding.
///
/// Mirrors the function-based pattern used by `rabbita/rabbita/websocket/*`:
/// lifecycle and mutation ops return `@cmd.Cmd`, subscription helpers return
/// `@sub.Sub`, and the per-editor handle the consumer's Model holds is a
/// plain `String` id. All JS handles live in this package's private
/// `editors` registry; this package owns no `extern "js"` declarations —
/// those live in the `js/` subpackage.
