///|
fn publication_fixture(message : String) -> @loom_core.DiagnosticSet {
  @loom_core.DiagnosticSet::single(
    @loom_core.Diagnostic(
      source=@loom_core.DiagnosticSource::parser(),
      severity=@loom_core.Diagnostic::lexer_error("fixture").severity(),
      message~,
    ),
  )
}

///|
fn publication_channel(
  producer : String,
  name? : String = "diagnostics",
) -> DiagnosticPublicationChannel {
  DiagnosticPublicationChannel::new(DiagnosticProducerId::new(producer), name)
}

///|
fn publication_state() -> DiagnosticPublicationState {
  DiagnosticPublicationState::new(DiagnosticConfigurationId::new("config-0"))
}

///|
fn source_revision(source : String, revision : Int) -> DiagnosticSourceRevision {
  DiagnosticSourceRevision::new(DiagnosticSourceId::new(source), revision)
}

///|
fn with_source(
  state : DiagnosticPublicationState,
  source : String,
  revision : Int,
) -> DiagnosticPublicationState {
  state.set_source_revision(DiagnosticSourceId::new(source), revision)
}

///|
fn messages(diagnostics : @loom_core.DiagnosticSet) -> Array[String] {
  diagnostics.items().map(diagnostic => diagnostic.message())
}

///|
fn rich_publication_fixture() -> @loom_core.DiagnosticSet {
  let source = @loom_core.SourceId("A")
  @loom_core.DiagnosticSet::single(
    @loom_core.Diagnostic(
      source=@loom_core.DiagnosticSource::parser(),
      severity=@loom_core.Diagnostic::lexer_error("fixture").severity(),
      code=Some(@loom_core.DiagnosticCode("fixture.rich")),
      message="retained",
      labels=[
        @loom_core.DiagnosticLabel(
          @loom_core.LabelStyle::Primary,
          @loom_core.SourceSpan(
            source,
            try! @loom_core.TextRange::from_offsets(1, 3),
          ),
          Some("primary"),
        ),
        @loom_core.DiagnosticLabel(
          @loom_core.LabelStyle::Secondary,
          @loom_core.SourceSpan(
            source,
            try! @loom_core.TextRange::from_offsets(4, 5),
          ),
          Some("secondary"),
        ),
      ],
    ),
  )
}

///|
test "publication rejects the original completion after A0 A1 A0" {
  let source_a = DiagnosticSourceId::new("A")
  let parser = publication_channel("parser")
  let a0_text = "same source"
  let state = with_source(
    DiagnosticPublicationState::new(DiagnosticConfigurationId::new("config-0")),
    "A",
    0,
  )
  let a1_text = "changed source"
  let (state, parser_ticket, _) = state.issue(
    parser,
    [source_revision("A", 0)],
    [],
  )
  let (state, _) = state.complete(
    parser_ticket,
    publication_fixture("parser-current"),
  )
  let (state, old_ticket, _) = state.issue(
    DiagnosticPublicationChannel::new(
      DiagnosticProducerId::new("semantic"),
      "diagnostics",
    ),
    [DiagnosticSourceRevision::new(source_a, 0)],
    [],
  )
  let state = state.set_source_revision(source_a, 1)
  inspect(a1_text != a0_text, content="true")
  let state = state.set_source_revision(source_a, 2)
  let host_text_after_return = a0_text
  inspect(host_text_after_return == a0_text, content="true")
  let (state, decision) = state.complete(old_ticket, publication_fixture("old"))
  inspect(decision is DiagnosticPublicationDecision::Rejected, content="true")
  let (state, current_ticket, _) = state.issue(
    publication_channel("semantic"),
    [DiagnosticSourceRevision::new(source_a, 2)],
    [],
  )
  let (state, current_decision) = state.complete(
    current_ticket,
    publication_fixture("semantic-current"),
  )
  inspect(
    current_decision is DiagnosticPublicationDecision::Accepted,
    content="true",
  )
  debug_inspect(
    messages(state.display(parser)),
    content="[\"parser-current\", \"semantic-current\"]",
  )
}

///|
test "current completion replaces one channel and preserves other publications" {
  let parser = publication_channel("parser")
  let semantic = publication_channel("semantic")
  let lint = publication_channel("lint")
  let state = with_source(publication_state(), "A", 0)
  let (state, parser_ticket, _) = state.issue(
    parser,
    [source_revision("A", 0)],
    [],
  )
  let (state, _) = state.complete(parser_ticket, publication_fixture("parser"))
  let (state, semantic_old, _) = state.issue(
    semantic,
    [source_revision("A", 0)],
    [],
  )
  let (state, _) = state.complete(
    semantic_old,
    publication_fixture("semantic-old"),
  )
  let (state, lint_ticket, _) = state.issue(lint, [source_revision("A", 0)], [])
  let (state, _) = state.complete(lint_ticket, publication_fixture("lint"))
  let (state, semantic_new, _) = state.issue(
    semantic,
    [source_revision("A", 0)],
    [],
  )
  let (state, decision) = state.complete(
    semantic_new,
    publication_fixture("semantic-new"),
  )
  inspect(decision is DiagnosticPublicationDecision::Accepted, content="true")
  debug_inspect(
    messages(state.display(parser)),
    content="[\"parser\", \"lint\", \"semantic-new\"]",
  )
}

///|
test "display sorts producer and channel as a lexicographic pair" {
  let parser = publication_channel("parser")
  let first = publication_channel("a", name="b:c")
  let second = publication_channel("a:b", name="c")
  let state = with_source(publication_state(), "A", 0)
  // Insert reverse pair order. Both concatenated colon keys would be "a:b:c".
  let (state, second_ticket, _) = state.issue(
    second,
    [source_revision("A", 0)],
    [],
  )
  let (state, _) = state.complete(second_ticket, publication_fixture("second"))
  let (state, first_ticket, _) = state.issue(first, [source_revision("A", 0)], [])
  let (state, _) = state.complete(first_ticket, publication_fixture("first"))
  debug_inspect(
    messages(state.display(parser)),
    content="[\"first\", \"second\"]",
  )
}

///|
test "producer restart cancels active channels in lexical pair order" {
  let producer = DiagnosticProducerId::new("semantic")
  let later = DiagnosticPublicationChannel::new(producer, "z-channel")
  let earlier = DiagnosticPublicationChannel::new(producer, "a-channel")
  let state = with_source(publication_state(), "A", 0)
  // Reverse insertion must not determine cancellation command order.
  let (state, later_ticket, _) = state.issue(later, [source_revision("A", 0)], [])
  let (state, earlier_ticket, _) = state.issue(
    earlier,
    [source_revision("A", 0)],
    [],
  )
  let (_, commands) = state.restart_producer(producer)
  guard commands
    is [
      DiagnosticPublicationCommand::Cancel(first),
      DiagnosticPublicationCommand::Cancel(second),
    ] else {
    fail("expected ordered restart cancellations")
  }
  inspect(first == earlier_ticket, content="true")
  inspect(second == later_ticket, content="true")
}

///|
test "coverage invalidation is precise for source dependency configuration and two sources" {
  let semantic = publication_channel("semantic")
  let state = with_source(with_source(publication_state(), "A", 0), "B", 0)
  let state = state.set_dependency_identity(
    DiagnosticDependencyId::new("project"),
    "dep-0",
  )
  let (state, unrelated, _) = state.issue(semantic, [source_revision("A", 0)], [])
  let state = with_source(state, "unrelated", 1)
  let (state, unrelated_decision) = state.complete(
    unrelated,
    publication_fixture("current"),
  )
  inspect(
    unrelated_decision is DiagnosticPublicationDecision::Accepted,
    content="true",
  )
  let (state, dependency_ticket, _) = state.issue(
    semantic,
    [source_revision("A", 0)],
    [
      DiagnosticDependencyRevision::new(
        DiagnosticDependencyId::new("project"),
        "dep-0",
      ),
    ],
  )
  let state = state.set_dependency_identity(
    DiagnosticDependencyId::new("project"),
    "dep-1",
  )
  let (state, dependency_decision) = state.complete(
    dependency_ticket,
    publication_fixture("stale-dependency"),
  )
  inspect(
    dependency_decision is DiagnosticPublicationDecision::Rejected,
    content="true",
  )
  let (state, config_ticket, _) = state.issue(
    semantic,
    [source_revision("A", 0)],
    [],
  )
  let state = state.set_configuration(
    DiagnosticConfigurationId::new("config-1"),
  )
  let (state, config_decision) = state.complete(
    config_ticket,
    publication_fixture("stale-config"),
  )
  inspect(
    config_decision is DiagnosticPublicationDecision::Rejected,
    content="true",
  )
  let (state, two_source_ticket, _) = state.issue(
    semantic,
    [source_revision("A", 0), source_revision("B", 0)],
    [],
  )
  let state = with_source(state, "B", 1)
  let (state, two_source_decision) = state.complete(
    two_source_ticket,
    publication_fixture("stale-B"),
  )
  inspect(
    two_source_decision is DiagnosticPublicationDecision::Rejected,
    content="true",
  )
  debug_inspect(
    messages(state.display(publication_channel("parser"))),
    content="[\"current\"]",
  )
}

///|
test "newer cancellation restart and duplicate completions never revive older work" {
  let parser = publication_channel("parser")
  let semantic = publication_channel("semantic")
  let state = with_source(publication_state(), "A", 0)
  let (state, old, _) = state.issue(semantic, [source_revision("A", 0)], [])
  let (state, newer, commands) = state.issue(
    semantic,
    [source_revision("A", 0)],
    [],
  )
  inspect(commands.length(), content="2")
  let (state, newer_decision) = state.complete(
    newer,
    publication_fixture("newer"),
  )
  inspect(
    newer_decision is DiagnosticPublicationDecision::Accepted,
    content="true",
  )
  let (state, old_decision) = state.complete(old, publication_fixture("old"))
  inspect(
    old_decision is DiagnosticPublicationDecision::Rejected,
    content="true",
  )
  let (state, duplicate) = state.complete(
    newer,
    publication_fixture("duplicate"),
  )
  inspect(duplicate is DiagnosticPublicationDecision::Rejected, content="true")
  let (state, cancelled, _) = state.issue(semantic, [source_revision("A", 0)], [])
  let (state, cancellation) = state.cancel(cancelled)
  inspect(cancellation.length(), content="1")
  let (state, cancelled_decision) = state.complete(
    cancelled,
    publication_fixture("cancelled"),
  )
  inspect(
    cancelled_decision is DiagnosticPublicationDecision::Rejected,
    content="true",
  )
  let (state, before_restart, _) = state.issue(
    semantic,
    [source_revision("A", 0)],
    [],
  )
  let (state, restart_commands) = state.restart_producer(
    DiagnosticProducerId::new("semantic"),
  )
  inspect(restart_commands.length(), content="1")
  let (state, restart_decision) = state.complete(
    before_restart,
    publication_fixture("pre-restart"),
  )
  inspect(
    restart_decision is DiagnosticPublicationDecision::Rejected,
    content="true",
  )
  debug_inspect(messages(state.display(parser)), content="[\"newer\"]")
}

///|
/// Thin deterministic fake shell: it records execution of core commands, then
/// deliberately delivers the stale completion after the current one.
priv struct FakePublicationShell {
  mut state : DiagnosticPublicationState
  started : Array[DiagnosticPublicationTicket]
  cancelled : Array[DiagnosticPublicationTicket]
}

///|
fn FakePublicationShell::FakePublicationShell(
  state : DiagnosticPublicationState,
) -> FakePublicationShell {
  { state, started: [], cancelled: [] }
}

///|
fn FakePublicationShell::execute(
  self : FakePublicationShell,
  commands : Array[DiagnosticPublicationCommand],
) -> Unit {
  commands.each(command => {
    match command {
      DiagnosticPublicationCommand::Start(ticket) => self.started.push(ticket)
      DiagnosticPublicationCommand::Cancel(ticket) =>
        self.cancelled.push(ticket)
    }
  })
}

///|
fn FakePublicationShell::issue(
  self : FakePublicationShell,
  channel : DiagnosticPublicationChannel,
) -> DiagnosticPublicationTicket {
  let (state, ticket, commands) = self.state.issue(
    channel,
    [source_revision("A", 0)],
    [],
  )
  self.state = state
  self.execute(commands)
  ticket
}

///|
fn FakePublicationShell::cancel(
  self : FakePublicationShell,
  ticket : DiagnosticPublicationTicket,
) -> Unit {
  let (state, commands) = self.state.cancel(ticket)
  self.state = state
  self.execute(commands)
}

///|
fn FakePublicationShell::restart(
  self : FakePublicationShell,
  producer : DiagnosticProducerId,
) -> Unit {
  let (state, commands) = self.state.restart_producer(producer)
  self.state = state
  self.execute(commands)
}

///|
fn FakePublicationShell::complete(
  self : FakePublicationShell,
  ticket : DiagnosticPublicationTicket,
  diagnostics : @loom_core.DiagnosticSet,
) -> DiagnosticPublicationDecision {
  let (state, decision) = self.state.complete(ticket, diagnostics)
  self.state = state
  decision
}

///|
test "fake async shell executes issue cancellation restart and reordered completion commands" {
  let semantic = publication_channel("semantic")
  let shell = FakePublicationShell::FakePublicationShell(
    with_source(publication_state(), "A", 0),
  )
  let old = shell.issue(semantic)
  let current = shell.issue(semantic)
  inspect(old != current, content="true")
  guard shell.started is [first_started, second_started] else {
    fail("expected two starts")
  }
  guard shell.cancelled is [superseded] else {
    fail("expected old cancellation")
  }
  inspect(first_started == old, content="true")
  inspect(second_started == current, content="true")
  inspect(superseded == old, content="true")
  let current_decision = shell.complete(current, publication_fixture("current"))
  let late_decision = shell.complete(old, publication_fixture("late"))
  inspect(
    current_decision is DiagnosticPublicationDecision::Accepted,
    content="true",
  )
  inspect(
    late_decision is DiagnosticPublicationDecision::Rejected,
    content="true",
  )
  let explicitly_cancelled = shell.issue(semantic)
  shell.cancel(explicitly_cancelled)
  let cancelled_decision = shell.complete(
    explicitly_cancelled,
    publication_fixture("cancelled"),
  )
  inspect(
    cancelled_decision is DiagnosticPublicationDecision::Rejected,
    content="true",
  )
  let previous_generation = shell.issue(semantic)
  shell.restart(DiagnosticProducerId::new("semantic"))
  let restart_decision = shell.complete(
    previous_generation,
    publication_fixture("pre-restart"),
  )
  inspect(
    restart_decision is DiagnosticPublicationDecision::Rejected,
    content="true",
  )
  inspect(shell.started.length(), content="4")
  inspect(shell.cancelled.length(), content="3")
  guard shell.cancelled is [_, explicit_cancel_command, restart_cancel_command] else {
    fail("expected recorded cancellation commands")
  }
  inspect(explicit_cancel_command == explicitly_cancelled, content="true")
  inspect(restart_cancel_command == previous_generation, content="true")
  debug_inspect(
    messages(shell.state.display(publication_channel("parser"))),
    content="[\"current\"]",
  )
}

///|
test "producer and source identities remain independent across publications" {
  let parser = publication_channel("parser")
  let semantic = publication_channel("semantic")
  let lint = publication_channel("lint")
  let state = with_source(with_source(publication_state(), "A", 0), "B", 0)
  let (state, semantic_ticket, _) = state.issue(
    semantic,
    [source_revision("A", 0), source_revision("B", 0)],
    [],
  )
  let (state, _) = state.complete(
    semantic_ticket,
    publication_fixture("semantic-A-B"),
  )
  let (state, lint_ticket, _) = state.issue(lint, [source_revision("A", 0)], [])
  let (state, lint_decision) = state.complete(
    lint_ticket,
    publication_fixture("lint-A"),
  )
  inspect(
    lint_decision is DiagnosticPublicationDecision::Accepted,
    content="true",
  )
  debug_inspect(
    messages(state.display(parser)),
    content="[\"lint-A\", \"semantic-A-B\"]",
  )
}

///|
test "accepted diagnostics retain Loom values and own a defensive copy" {
  let parser = publication_channel("parser")
  let semantic = publication_channel("semantic")
  let state = with_source(publication_state(), "A", 0)
  let produced = rich_publication_fixture()
  let (state, ticket, _) = state.issue(semantic, [source_revision("A", 0)], [])
  let (state, decision) = state.complete(ticket, produced)
  inspect(decision is DiagnosticPublicationDecision::Accepted, content="true")
  produced.push(@loom_core.Diagnostic::lexer_error("late producer mutation"))
  let published = state.display(parser)
  guard published.items() is [diagnostic] else {
    fail("expected one copied diagnostic")
  }
  inspect(diagnostic.message(), content="retained")
  guard diagnostic.labels() is [primary, secondary] else {
    fail("expected both labels")
  }
  inspect(primary.style() is @loom_core.LabelStyle::Primary, content="true")
  inspect(secondary.style() is @loom_core.LabelStyle::Secondary, content="true")
  inspect(
    primary.span().source_id() == @loom_core.SourceId("A"),
    content="true",
  )
  inspect(primary.span().range().start().value(), content="1")
  inspect(primary.span().range().end().value(), content="3")
  inspect(published.length(), content="1")
  published.push(@loom_core.Diagnostic::lexer_error("late display mutation"))
  debug_inspect(messages(state.display(parser)), content="[\"retained\"]")
}
