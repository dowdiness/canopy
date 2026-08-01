///|
test "supported snapshot restore replaces source and mode atomically" {
  let initial = ApplicationState::new("# Old\n", Raw)
  let snapshot = ApplicationState::new("# New\r\n", Preview).snapshot()

  let transition = reduce(initial, RestoreSnapshot(snapshot))

  inspect(transition.state().source(), content="# New\r\n")
  assert_true(transition.state().mode() == Preview)
  assert_eq(transition.decisions().to_array(), [
    ReplaceCanonicalSource("# New\r\n"),
  ])
}

///|
test "committed source preserves text and current mode" {
  let state = ApplicationState::new("before", Preview)
  let source = "# LF\n## CRLF\r\n### CR\rend"

  let transition = reduce(state, CanonicalSourceCommitted(source))

  inspect(transition.state().source(), content="# LF\n## CRLF\r\n### CR\rend")
  assert_true(transition.state().mode() == Preview)
  assert_true(transition.decisions().is_empty())
}

///|
test "committing the current source is idempotent" {
  let state = ApplicationState::new("canonical", Raw)

  let transition = reduce(state, CanonicalSourceCommitted("canonical"))

  assert_true(transition.state() == state)
  assert_true(transition.decisions().is_empty())
}

///|
test "mode selection preserves source and repeated selection is idempotent" {
  let initial = ApplicationState::new("canonical", Raw)

  let changed = reduce(initial, SelectMode(Preview))
  inspect(changed.state().source(), content="canonical")
  assert_true(changed.state().mode() == Preview)
  assert_true(changed.decisions().is_empty())

  let unchanged = reduce(changed.state(), SelectMode(Preview))
  assert_true(unchanged.state() == changed.state())
  assert_true(unchanged.decisions().is_empty())
}

///|
test "unsupported snapshot version leaves state unchanged" {
  let initial = ApplicationState::new("canonical", Raw)
  let snapshot = ApplicationSnapshot::new(99, "replacement", Preview)

  let transition = reduce(initial, RestoreSnapshot(snapshot))

  assert_true(transition.state() == initial)
  assert_eq(transition.decisions().to_array(), [
    SnapshotRejected(UnsupportedSnapshotVersion(99)),
  ])
}

///|
test "restoring the current snapshot is idempotent" {
  let state = ApplicationState::new("canonical\r\n", Preview)

  let transition = reduce(state, RestoreSnapshot(state.snapshot()))

  assert_true(transition.state() == state)
  assert_true(transition.decisions().is_empty())
}

///|
test "snapshot restore does not replace an unchanged source" {
  let state = ApplicationState::new("canonical", Raw)
  let snapshot = ApplicationState::new("canonical", Preview).snapshot()

  let transition = reduce(state, RestoreSnapshot(snapshot))

  inspect(transition.state().source(), content="canonical")
  assert_true(transition.state().mode() == Preview)
  assert_true(transition.decisions().is_empty())
}

///|
test "snapshot restore accepts an empty source without changing mode" {
  let state = ApplicationState::new("canonical", Raw)
  let snapshot = ApplicationState::new("", Raw).snapshot()

  let transition = reduce(state, RestoreSnapshot(snapshot))

  inspect(transition.state().source(), content="")
  assert_true(transition.state().mode() == Raw)
  assert_eq(transition.decisions().to_array(), [ReplaceCanonicalSource("")])
}
