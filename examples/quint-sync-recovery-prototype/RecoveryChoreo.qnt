module RecoveryChoreo {
  import RecoveryCore.* from "RecoveryCore"
  import choreo(processes = NODES) as choreo from "choreo"

  type Node = str
  type Message =
    | NetRequest({ sender: Node, id: int })
    | NetEmptyResponse({ sender: Node, id: int })
    | NetHelpfulResponse({ sender: Node, id: int })
  type NetEvent = NetWatchdog(int)
  type Extensions = { phase: int }
  type CustomEffect =
    | AdvancePhase
    | ConsumeMessage({ process: Node, message: Message })
    | ConsumeEvent({ process: Node, event: NetEvent })
    | NoConsume

  type ChoreoState = { core: State }
  type LocalState = choreo::LocalState[Node, ChoreoState]
  type LocalContext = choreo::LocalContext[Node, ChoreoState, Message, NetEvent, Extensions]
  type Transition = choreo::Transition[Node, ChoreoState, Message, NetEvent, CustomEffect]
  type GlobalContext = choreo::GlobalContext[Node, ChoreoState, Message, NetEvent, Extensions]
  type Display = { phase: int, status: str, target: str, requestId: int, attempt: int, sent: int, sentKinds: str, scheduled: int, applied: int, statusEvents: int, peerLeaves: int }

  pure val NODES = Set("alice", "bob", "carol")

  pure def initialize(n: Node): LocalState = {
    process_id: n,
    core: initial,
  }

  pure def display(ctx: GlobalContext): Display = {
    val a = ctx.system.get("alice").core
    {
      phase: ctx.extensions.phase,
      status: a.status,
      target: a.target,
      requestId: a.requestId,
      attempt: a.attempt,
      sent: a.sent,
      sentKinds: a.sentKinds,
      scheduled: a.scheduled,
      applied: a.applied,
      statusEvents: a.statusEvents,
      peerLeaves: a.peerLeaves,
    }
  }

  pure def core_effects(process: Node, effects: Set[Effect]): Set[choreo::Effect[Node, Message, NetEvent, CustomEffect]] = {
    effects.fold(Set(), (out, effect) => {
      match effect {
        | SendRequest(request) => out.union(Set(choreo::Send({ to: request.target, message: NetRequest({ sender: process, id: request.id }) })))
        | ScheduleWatchdog(id) => out.union(Set(choreo::TriggerEvent(NetWatchdog(id))))
      }
    })
  }

  pure def event_transition(ctx: LocalContext, event: Event, consumed: CustomEffect, advance: bool): Transition = {
    val d = apply_event(ctx.state.core, event)
    val consumed_effects = match consumed {
      | NoConsume => Set()
      | AdvancePhase => Set(choreo::CustomEffect(AdvancePhase))
      | ConsumeMessage(entry) => Set(choreo::CustomEffect(ConsumeMessage(entry)))
      | ConsumeEvent(entry) => Set(choreo::CustomEffect(ConsumeEvent(entry)))
    }
    val phase_effects = if (advance) { Set(choreo::CustomEffect(AdvancePhase)) } else { Set() }
    {
      post_state: { ...ctx.state, core: d.post_state },
      effects: core_effects(ctx.state.process_id, d.effects).union(consumed_effects).union(phase_effects),
    }
  }

  pure def request_response(ctx: LocalContext, request: Message, helpful: bool): Transition = {
    val req = match request { | NetRequest(r) => r | _ => { sender: "", id: 0 } }
    val sender = req.sender
    val id = req.id
    val response = if (helpful) { NetHelpfulResponse({ sender: ctx.state.process_id, id: id }) } else { NetEmptyResponse({ sender: ctx.state.process_id, id: id }) }
    {
      post_state: ctx.state,
      effects: Set(
        choreo::Send({ to: sender, message: response }),
        choreo::CustomEffect(ConsumeMessage({ process: ctx.state.process_id, message: request })),
        choreo::CustomEffect(AdvancePhase),
      ),
    }
  }

  pure def spontaneous_choices(ctx: LocalContext): Set[Transition] = {
    if (ctx.state.core.status == "Disconnected") {
      Set(event_transition(ctx, Open, NoConsume, false))
    } else if (ctx.state.process_id == "alice" and ctx.state.core.status == "Idle" and ctx.state.core.sent == 0) {
      Set(
        event_transition(ctx, ApplyFailed("bob"), NoConsume, false),
        event_transition(ctx, ApplyFailed("carol"), NoConsume, false),
      )
    } else {
      Set()
    }
  }

  pure def main_listener(ctx: LocalContext): Set[Transition] = {
    val requests = ctx.messages.filter(m => match m {
      | NetRequest(_) => true
      | _ => false
    })
    val responses = ctx.messages.filter(m => match m {
      | NetEmptyResponse(_) => true
      | NetHelpfulResponse(_) => true
      | _ => false
    })
    val request_choices = requests.map(m => Set(request_response(ctx, m, false), request_response(ctx, m, true))).fold(Set(), (out, choices) => out.union(choices))
    val response_choices = if (ctx.state.process_id == "alice") {
      responses.map(m => match m {
        | NetEmptyResponse(response) => event_transition(ctx, EmptyResponse(response), ConsumeMessage({ process: "alice", message: m }), false)
        | NetHelpfulResponse(response) => event_transition(ctx, HelpfulResponse(response), ConsumeMessage({ process: "alice", message: m }), false)
        | _ => event_transition(ctx, Open, NoConsume, false)
      })
    } else { Set() }
    val watchdog_choices = if (ctx.state.process_id == "alice") {
      ctx.events.map(e => event_transition(ctx, match e { | NetWatchdog(id) => Watchdog(id) }, ConsumeEvent({ process: "alice", event: e }), false))
    } else { Set() }
    spontaneous_choices(ctx).union(request_choices).union(response_choices).union(watchdog_choices)
  }

  pure def apply_custom_effect(ctx: GlobalContext, effect: CustomEffect): GlobalContext = {
    match effect {
      | AdvancePhase => { ...ctx, extensions: { phase: ctx.extensions.phase + 1 } }
      | ConsumeMessage(entry) => { ...ctx, messages: ctx.messages.setBy(entry.process, xs => xs.exclude(Set(entry.message))) }
      | ConsumeEvent(entry) => { ...ctx, events: ctx.events.setBy(entry.process, xs => xs.exclude(Set(entry.event))) }
      | NoConsume => ctx
    }
  }

  action init = choreo::init_with_displayer({
    system: NODES.mapBy(n => initialize(n)),
    messages: NODES.mapBy(n => Set()),
    events: NODES.mapBy(n => Set()),
    extensions: { phase: 0 },
  }, display)

  pure def open_alice(ctx: LocalContext): Set[Transition] =
    if (ctx.extensions.phase == 0 and ctx.state.core.status == "Disconnected") { Set(event_transition(ctx, Open, NoConsume, true)) } else { Set() }
  pure def open_bob(ctx: LocalContext): Set[Transition] =
    if (ctx.extensions.phase == 1 and ctx.state.core.status == "Disconnected") { Set(event_transition(ctx, Open, NoConsume, true)) } else { Set() }
  pure def open_carol(ctx: LocalContext): Set[Transition] =
    if (ctx.extensions.phase == 2 and ctx.state.core.status == "Disconnected") { Set(event_transition(ctx, Open, NoConsume, true)) } else { Set() }
  pure def start_alice(ctx: LocalContext): Set[Transition] =
    if (ctx.extensions.phase == 3 and ctx.state.core.status == "Idle") { Set(event_transition(ctx, ApplyFailed("bob"), NoConsume, true)) } else { Set() }

  pure def bob_empty(ctx: LocalContext): Set[Transition] = {
    val request = NetRequest({ sender: "alice", id: 1 })
    if (ctx.extensions.phase == 4 and ctx.messages.contains(request)) { Set(request_response(ctx, request, false)) } else { Set() }
  }
  pure def bob_helpful(ctx: LocalContext): Set[Transition] = {
    val request = NetRequest({ sender: "alice", id: 2 })
    if (ctx.extensions.phase == 7 and ctx.messages.contains(request)) { Set(request_response(ctx, request, true)) } else { Set() }
  }
  pure def alice_empty(ctx: LocalContext): Set[Transition] = {
    val response = NetEmptyResponse({ sender: "bob", id: 1 })
    if (ctx.extensions.phase == 5 and ctx.messages.contains(response)) { Set(event_transition(ctx, EmptyResponse({ sender: "bob", id: 1 }), ConsumeMessage({ process: "alice", message: response }), true)) } else { Set() }
  }
  pure def alice_stale(ctx: LocalContext): Set[Transition] = {
    val event = NetWatchdog(1)
    if (ctx.extensions.phase == 6 and ctx.events.contains(event)) { Set(event_transition(ctx, Watchdog(1), ConsumeEvent({ process: "alice", event: event }), true)) } else { Set() }
  }
  pure def alice_helpful(ctx: LocalContext): Set[Transition] = {
    val response = NetHelpfulResponse({ sender: "bob", id: 2 })
    if (ctx.extensions.phase == 8 and ctx.messages.contains(response)) { Set(event_transition(ctx, HelpfulResponse({ sender: "bob", id: 2 }), ConsumeMessage({ process: "alice", message: response }), true)) } else { Set() }
  }

  action openAlice = choreo::step_with_displayer((ctx) => if (ctx.state.process_id == "alice") { open_alice(ctx) } else { Set() }, apply_custom_effect, display)
  action openBob = choreo::step_with_displayer((ctx) => if (ctx.state.process_id == "bob") { open_bob(ctx) } else { Set() }, apply_custom_effect, display)
  action openCarol = choreo::step_with_displayer((ctx) => if (ctx.state.process_id == "carol") { open_carol(ctx) } else { Set() }, apply_custom_effect, display)
  action aliceStartsRecovery = choreo::step_with_displayer((ctx) => if (ctx.state.process_id == "alice") { start_alice(ctx) } else { Set() }, apply_custom_effect, display)
  action bobRepliesEmpty = choreo::step_with_displayer((ctx) => if (ctx.state.process_id == "bob") { bob_empty(ctx) } else { Set() }, apply_custom_effect, display)
  action aliceReceivesEmpty = choreo::step_with_displayer((ctx) => if (ctx.state.process_id == "alice") { alice_empty(ctx) } else { Set() }, apply_custom_effect, display)
  action aliceFiresStaleTimeout1 = choreo::step_with_displayer((ctx) => if (ctx.state.process_id == "alice") { alice_stale(ctx) } else { Set() }, apply_custom_effect, display)
  action bobRepliesHelpful = choreo::step_with_displayer((ctx) => if (ctx.state.process_id == "bob") { bob_helpful(ctx) } else { Set() }, apply_custom_effect, display)
  action aliceReceivesHelpful = choreo::step_with_displayer((ctx) => if (ctx.state.process_id == "alice") { alice_helpful(ctx) } else { Set() }, apply_custom_effect, display)

  // Deliberate model mutation used only by modelMutationStep. It bypasses the
  // core to prove that the safety invariant rejects a fifth attempt.
  pure def unsafe_retry(ctx: LocalContext): Set[Transition] =
    if (ctx.extensions.phase == 4 and ctx.state.core.status == "Recovering") {
      Set({
        post_state: { ...ctx.state, core: { ...ctx.state.core, attempt: 5 } },
        effects: Set(choreo::CustomEffect(AdvancePhase)),
      })
    } else {
      Set()
    }

  action unsafeAttemptFive = choreo::step_with_displayer((ctx) => if (ctx.state.process_id == "alice") { unsafe_retry(ctx) } else { Set() }, apply_custom_effect, display)

  action step = choreo::step_with_displayer(main_listener, apply_custom_effect, display)

  val s = choreo::s
  val safety = NODES.forall(n => {
    val c = s.system.get(n).core
    c.attempt >= 0 and c.attempt <= 4 and c.requestId >= 0 and c.requestId <= 4 and
    c.sent == c.scheduled and c.sent >= 0 and c.sent <= 4 and
    c.applied >= 0 and c.applied <= 3 and c.statusEvents >= 0 and c.statusEvents <= 6 and
    c.peerLeaves >= 0 and c.peerLeaves <= 1 and
    (c.status == "Disconnected" implies c.attempt == 0) and
    (c.status == "Idle" implies c.attempt == 0) and
    (c.status == "Recovering" implies c.attempt >= 1 and c.attempt <= 4) and
    (c.target == "" or c.target != n)
  })

  action replayStep = any {
    openAlice,
    openBob,
    openCarol,
    aliceStartsRecovery,
    bobRepliesEmpty,
    aliceReceivesEmpty,
    aliceFiresStaleTimeout1,
    bobRepliesHelpful,
    aliceReceivesHelpful,
  }

  action modelMutationStep = any {
    openAlice,
    openBob,
    openCarol,
    aliceStartsRecovery,
    unsafeAttemptFive,
  }

  run replay = init
    .then(openAlice)
    .then(openBob)
    .then(openCarol)
    .then(aliceStartsRecovery)
    .then(bobRepliesEmpty)
    .then(aliceReceivesEmpty)
    .then(aliceFiresStaleTimeout1)
    .then(bobRepliesHelpful)
    .then(aliceReceivesHelpful)
}
