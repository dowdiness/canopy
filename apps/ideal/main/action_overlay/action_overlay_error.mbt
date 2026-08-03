///|
/// Typed failures that the action overlay can surface. Closed because there are
/// exactly three known error sources; migrate to `extenum` if plugin packages
/// ever need overlay-specific typed failures.
pub(all) enum OverlayError {
  EmptyName
  BuildActionFailed(String)
  ApplyActionFailed(String)
} derive(Debug)

///|
/// Single source of truth for all user-facing overlay error copy.
pub fn format_overlay_error(err : OverlayError) -> String {
  match err {
    EmptyName => "Enter a name to continue"
    BuildActionFailed(msg) => "Build failed: \{msg}"
    ApplyActionFailed(msg) => "Apply failed: \{msg}"
  }
}
