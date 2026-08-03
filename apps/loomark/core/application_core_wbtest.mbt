///| The pure core proposes source work without owning canonical source.

///|
test "source request yields an ordered replacement decision" {
  let state = ApplicationState(Raw)
  let transition = reduce(
    state,
    ApplicationEvent::RequestCanonicalSource(source="# New\r\n"),
  )

  assert_true(transition.state() == state)
  assert_eq(transition.decisions().to_array(), [
    ApplicationDecision::ReplaceCanonicalSource("# New\r\n"),
  ])
}

///|
test "mode selection changes only the proposed mode" {
  let state = ApplicationState(Raw)
  let transition = reduce(state, ApplicationEvent::SelectMode(mode=Preview))

  assert_true(transition.state().mode() == Preview)
  assert_true(transition.decisions().is_empty())

  let repeated = reduce(
    transition.state(),
    ApplicationEvent::SelectMode(mode=Preview),
  )
  assert_true(repeated.state() == transition.state())
  assert_true(repeated.decisions().is_empty())
}

///|
test "snapshot restore proposes source replacement without storing source" {
  let state = ApplicationState(Raw)
  let snapshot = ApplicationStateSnapshot(
    version=1,
    source="# New\r\n",
    mode=Preview,
  )
  let transition = reduce(
    state,
    ApplicationEvent::RestoreSnapshot(snapshot~, canonical_source="# Old\n"),
  )

  assert_true(transition.state().mode() == Preview)
  assert_eq(transition.decisions().to_array(), [
    ApplicationDecision::ReplaceCanonicalSource("# New\r\n"),
  ])
}

///|
test "snapshot restore with equal source emits no replacement" {
  let state = ApplicationState(Raw)
  let snapshot = ApplicationStateSnapshot(
    version=1,
    source="# Same\n",
    mode=Preview,
  )
  let transition = reduce(
    state,
    ApplicationEvent::RestoreSnapshot(snapshot~, canonical_source="# Same\n"),
  )

  assert_true(transition.state().mode() == Preview)
  assert_true(transition.decisions().is_empty())
}

///|
test "unsupported snapshot version rejects without changing state" {
  let state = ApplicationState(Raw)
  let snapshot = ApplicationStateSnapshot(
    version=99,
    source="# New\n",
    mode=Preview,
  )
  let transition = reduce(
    state,
    ApplicationEvent::RestoreSnapshot(snapshot~, canonical_source="# Old\n"),
  )

  assert_true(transition.state() == state)
  assert_eq(transition.decisions().to_array(), [
    ApplicationDecision::SnapshotRejected(
      SnapshotError::UnsupportedSnapshotVersion(99),
    ),
  ])
}

///|
test "state snapshot carries caller source separately from live state" {
  let state = ApplicationState(Block)
  let snapshot = state.snapshot("A🤣B\r\n")

  assert_eq(snapshot.version(), SNAPSHOT_VERSION)
  assert_eq(snapshot.source(), "A🤣B\r\n")
  assert_true(snapshot.mode() == Block)
  assert_true(state.mode() == Block)
}

///|
test "focus decision accepts a compatible typed locator" {
  let locator = FocusLocator(target=RawEditor, source_revision=0)
  match decide_focus(ApplicationState(Raw), 0, locator) {
    FocusDecision::Compatible(FocusTarget::RawEditor) => ()
    _ => fail("expected a compatible Raw focus locator")
  }
}

///|
test "focus decision rejects stale source revisions" {
  let locator = FocusLocator(target=RawEditor, source_revision=1)
  match decide_focus(ApplicationState(Raw), 2, locator) {
    FocusDecision::Rejected(FocusDecisionError::Stale) => ()
    _ => fail("expected stale focus locator")
  }
}

///|
test "focus decision rejects mode-inapplicable controls" {
  let locator = FocusLocator(target=RawEditor, source_revision=0)
  match decide_focus(ApplicationState(Preview), 0, locator) {
    FocusDecision::Rejected(FocusDecisionError::ModeInapplicable) => ()
    _ => fail("expected mode-inapplicable focus locator")
  }
}

///|
test "focus decision accepts the Block editor target only in Block mode" {
  let locator = FocusLocator(target=BlockEditor, source_revision=0)
  match decide_focus(ApplicationState(Block), 0, locator) {
    FocusDecision::Compatible(FocusTarget::BlockEditor) => ()
    _ => fail("expected a compatible Block focus locator")
  }
  match decide_focus(ApplicationState(Preview), 0, locator) {
    FocusDecision::Rejected(FocusDecisionError::ModeInapplicable) => ()
    _ => fail("expected a mode-inapplicable Block focus locator")
  }
}
