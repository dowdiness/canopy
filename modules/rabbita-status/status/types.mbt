///|
/// Semantic tone for a short app-feedback status message.
///
/// Consumers own message copy and domain mapping. The behavior only exposes the
/// stable tone vocabulary used by `Tone::attrs` for `data-tone`.
pub(all) enum Tone {
  Info
  Success
  Error
} derive(Eq)

///|
fn Tone::data_value(self : Tone) -> String {
  match self {
    Info => "info"
    Success => "success"
    Error => "error"
  }
}
