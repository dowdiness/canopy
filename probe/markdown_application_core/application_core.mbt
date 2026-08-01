///|
/// Application modes exercised by this isolated prototype.
pub(all) enum ApplicationMode {
  Raw
  Preview
} derive(Eq, Debug)

///|
/// Current snapshot encoding understood by the prototype reducer.
pub const SNAPSHOT_VERSION : Int = 1

///|
/// Immutable application state at the pure reducer seam.
pub struct ApplicationState {
  priv source : String
  priv mode : ApplicationMode
} derive(Eq, Debug)

///|
pub fn ApplicationState::new(
  source : String,
  mode : ApplicationMode,
) -> ApplicationState {
  { source, mode }
}

///|
pub fn ApplicationState::source(self : Self) -> String {
  self.source
}

///|
pub fn ApplicationState::mode(self : Self) -> ApplicationMode {
  self.mode
}

///|
/// Immutable route/session restoration value owned by the prototype core.
pub struct ApplicationSnapshot {
  priv version : Int
  priv source : String
  priv mode : ApplicationMode
} derive(Eq, Debug)

///|
/// Construct a decoded snapshot value for the prototype reducer to validate.
pub fn ApplicationSnapshot::new(
  version : Int,
  source : String,
  mode : ApplicationMode,
) -> ApplicationSnapshot {
  { version, source, mode }
}

///|
pub fn ApplicationState::snapshot(self : Self) -> ApplicationSnapshot {
  { version: SNAPSHOT_VERSION, source: self.source, mode: self.mode }
}

///|
/// Input events accepted by the prototype reducer.
pub(all) enum ApplicationEvent {
  CanonicalSourceCommitted(String)
  SelectMode(ApplicationMode)
  RestoreSnapshot(ApplicationSnapshot)
} derive(Eq, Debug)

///|
/// Snapshot validation failures reported by the pure reducer.
pub(all) enum SnapshotError {
  UnsupportedSnapshotVersion(Int)
} derive(Eq, Debug)

///|
/// Effects for the future imperative shell to execute.
pub(all) enum ApplicationDecision {
  ReplaceCanonicalSource(String)
  SnapshotRejected(SnapshotError)
} derive(Eq, Debug)

///|
/// Result of one deterministic application transition.
pub struct Transition {
  priv state : ApplicationState
  priv decisions : @vector.Vector[ApplicationDecision]
}

///|
pub fn Transition::state(self : Self) -> ApplicationState {
  self.state
}

///|
pub fn Transition::decisions(
  self : Self,
) -> @vector.Vector[ApplicationDecision] {
  self.decisions
}

///|
/// Apply one event without reading or performing external effects.
pub fn reduce(state : ApplicationState, event : ApplicationEvent) -> Transition {
  match event {
    CanonicalSourceCommitted(source) =>
      { state: { ..state, source, }, decisions: @vector.new() }
    SelectMode(mode) => { state: { ..state, mode, }, decisions: @vector.new() }
    RestoreSnapshot(snapshot) =>
      if snapshot.version != SNAPSHOT_VERSION {
        {
          state,
          decisions: @vector.singleton(
            SnapshotRejected(UnsupportedSnapshotVersion(snapshot.version)),
          ),
        }
      } else {
        let restored = { source: snapshot.source, mode: snapshot.mode }
        if snapshot.source == state.source {
          { state: restored, decisions: @vector.new() }
        } else {
          {
            state: restored,
            decisions: @vector.singleton(
              ReplaceCanonicalSource(snapshot.source),
            ),
          }
        }
      }
  }
}
