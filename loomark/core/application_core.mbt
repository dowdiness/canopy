///|
/// Modes owned by the pure Loomark application core.
pub(all) enum ApplicationMode {
  Raw
  Block
  Preview
} derive(Eq, Debug)

///|
/// Version of the application-owned snapshot value.
pub const SNAPSHOT_VERSION : Int = 1

///|
/// Application state contains mode decisions only, never canonical source.
pub struct ApplicationState {
  priv mode : ApplicationMode
} derive(Eq, Debug)

///|
pub fn ApplicationState::ApplicationState(
  mode : ApplicationMode,
) -> ApplicationState {
  { mode, }
}

///|
pub fn ApplicationState::mode(self : Self) -> ApplicationMode {
  self.mode
}

///|
/// The application-owned portion of a restorable session snapshot.
pub struct ApplicationStateSnapshot {
  priv version : Int
  priv source : String
  priv mode : ApplicationMode
} derive(Eq, Debug)

///|
/// Construct a decoded snapshot for reducer validation.
pub fn ApplicationStateSnapshot::ApplicationStateSnapshot(
  version~ : Int,
  source~ : String,
  mode~ : ApplicationMode,
) -> ApplicationStateSnapshot {
  { version, source, mode }
}

///|
pub fn ApplicationStateSnapshot::version(self : Self) -> Int {
  self.version
}

///|
pub fn ApplicationStateSnapshot::source(self : Self) -> String {
  self.source
}

///|
pub fn ApplicationStateSnapshot::mode(self : Self) -> ApplicationMode {
  self.mode
}

///|
pub fn ApplicationState::snapshot(
  self : Self,
  source : String,
) -> ApplicationStateSnapshot {
  { version: SNAPSHOT_VERSION, source, mode: self.mode }
}

///|
/// A logical focus target contains no DOM or session identity.
pub(all) enum FocusTarget {
  RawEditor
  BlockEditor
  PreviewControl
} derive(Eq, Debug)

///|
/// An opaque logical focus locator validated by the imperative shell.
pub struct FocusLocator {
  priv target : FocusTarget
  priv source_revision : Int
} derive(Eq, Debug)

///|
pub fn FocusLocator::FocusLocator(
  target~ : FocusTarget,
  source_revision~ : Int,
) -> FocusLocator {
  { target, source_revision }
}

///|
/// Reasons a typed logical locator is not compatible with current state.
pub(all) enum FocusDecisionError {
  Stale
  ModeInapplicable
} derive(Eq, Debug)

///|
/// Pure focus proposal for the imperative DOM shell.
pub(all) enum FocusDecision {
  Compatible(FocusTarget)
  Rejected(FocusDecisionError)
} derive(Eq, Debug)

///|
fn focus_target_mode(target : FocusTarget) -> ApplicationMode {
  match target {
    RawEditor => Raw
    BlockEditor => Block
    PreviewControl => Preview
  }
}

///|
/// Decide whether a typed logical focus locator may be restored.
pub fn decide_focus(
  state : ApplicationState,
  source_revision : Int,
  locator : FocusLocator,
) -> FocusDecision {
  if locator.source_revision != source_revision {
    FocusDecision::Rejected(FocusDecisionError::Stale)
  } else if focus_target_mode(locator.target) != state.mode() {
    FocusDecision::Rejected(FocusDecisionError::ModeInapplicable)
  } else {
    FocusDecision::Compatible(locator.target)
  }
}

///|
/// Snapshot validation failures reported as immutable decisions.
pub(all) enum SnapshotError {
  UnsupportedSnapshotVersion(Int)
} derive(Eq, Debug)

///|
/// Ordered decisions for the imperative editor/browser shell.
pub(all) enum ApplicationDecision {
  ReplaceCanonicalSource(String)
  SnapshotRejected(SnapshotError)
} derive(Eq, Debug)

///|
/// Events accepted by the pure reducer.
pub(all) enum ApplicationEvent {
  RequestCanonicalSource(source~ : String)
  SelectMode(mode~ : ApplicationMode)
  RestoreSnapshot(
    snapshot~ : ApplicationStateSnapshot,
    canonical_source~ : String
  )
} derive(Eq, Debug)

///|
/// Proposed next state and ordered shell decisions from one reduction.
pub struct ProposedTransition {
  priv state : ApplicationState
  priv decisions : @vector.Vector[ApplicationDecision]
}

///|
pub fn ProposedTransition::state(self : Self) -> ApplicationState {
  self.state
}

///|
pub fn ProposedTransition::decisions(
  self : Self,
) -> @vector.Vector[ApplicationDecision] {
  self.decisions
}

///|
/// Purely reduce an application event; no source/editor/runtime effect occurs.
pub fn reduce(
  state : ApplicationState,
  event : ApplicationEvent,
) -> ProposedTransition {
  match event {
    RequestCanonicalSource(source~) =>
      {
        state,
        decisions: @vector.singleton(
          ApplicationDecision::ReplaceCanonicalSource(source),
        ),
      }
    SelectMode(mode~) => { state: { mode, }, decisions: @vector.new() }
    RestoreSnapshot(snapshot~, canonical_source~) =>
      if snapshot.version != SNAPSHOT_VERSION {
        {
          state,
          decisions: @vector.singleton(
            ApplicationDecision::SnapshotRejected(
              SnapshotError::UnsupportedSnapshotVersion(snapshot.version),
            ),
          ),
        }
      } else {
        {
          state: { mode: snapshot.mode },
          decisions: if snapshot.source != canonical_source {
            @vector.singleton(
              ApplicationDecision::ReplaceCanonicalSource(snapshot.source),
            )
          } else {
            @vector.new()
          },
        }
      }
  }
}
