///|
/// Deterministic, provider-independent replay of fixed generative-UI input
/// envelopes. The source owns only an immutable event log and a replay cursor;
/// lifecycle and renderer policy stay with their respective owners.
pub struct GenerativeUiReplaySource {
  priv events : Array[GenerativeUiInput]
  priv mut cursor : Int
}

///|
pub fn GenerativeUiReplaySource::GenerativeUiReplaySource(
  events~ : Array[GenerativeUiInput],
) -> GenerativeUiReplaySource {
  { events: events.copy(), cursor: 0 }
}

///|
/// Return the next fixed input event, or `None` after the replay is exhausted.
pub fn GenerativeUiReplaySource::next(
  self : GenerativeUiReplaySource,
) -> GenerativeUiInput? {
  match self.events.get(self.cursor) {
    Some(event) => {
      self.cursor += 1
      Some(event)
    }
    None => None
  }
}

///|
pub fn GenerativeUiReplaySource::is_exhausted(
  self : GenerativeUiReplaySource,
) -> Bool {
  self.cursor >= self.events.length()
}

///|
/// Rewind the source so the exact same event sequence can be replayed.
pub fn GenerativeUiReplaySource::reset(self : GenerativeUiReplaySource) -> Unit {
  self.cursor = 0
}
