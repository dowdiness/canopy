module RecoveryChoreo {
  import RecoveryCore.* from "RecoveryCore"
  import choreo(processes = NODES) as choreo from "choreo"

  type Node = str
  type Message =
    | NetRequest({ sender: Node, id: int })
    | NetEmptyResponse({ sender: Node, id: int })
    | NetHelpfulResponse({ sender: Node, id: int })
  type NetEvent = NetWatchdog(int)

  // This command is the stable trace contract consumed by MoonBit. Generic
  // Choreo actions are all named `step`, so replay must not infer behavior from
  // mbt::actionTaken or opaque transition records.
  type Command =
    | Init
    | OpenPeer({ peer: Node })
    | StartRecovery({ target: Node })
    | RespondEmpty({ sender: Node, id: int })
    | RespondHelpful({ sender: Node, id: int })
    | DeliverEmpty({ sender: Node, id: int })
    | DeliverHelpful({ sender: Node, id: int })
    | FireWatchdog({ id: int })
    | SyncAppliedCommand
    | UnsafeAttemptFive

  type Extensions = { phase: int, command: Command }
  type CustomEffect =
    | AdvancePhase
    | RecordCommand(Command)
    | ConsumeMessage({ process: Node, message: Message })
    | ConsumeEvent({ process: Node, event: NetEvent })
    | NoConsume

  type ChoreoState = { core: State }
  type LocalState = choreo::LocalState[Node, ChoreoState]
  type LocalContext = choreo::LocalContext[Node, ChoreoState, Message, NetEvent, Extensions]
  type Transition = choreo::Transition[Node, ChoreoState, Message, NetEvent, CustomEffect]
  type GlobalContext = choreo::GlobalContext[Node, ChoreoState, Message, NetEvent, Extensions]
  type Display = {
    phase: int,
    status: str,
    target: str,
    requestId: int,
    attempt: int,
    sent: int,
    sentKinds: str,
    scheduled: int,
    applied: int,
    statusEvents: int,
    peerLeaves: int,
  }

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

  pure def core_effects(
    process: Node,
    effects: Set[Effect],
  ): Set[choreo::Effect[Node, Message, NetEvent, CustomEffect]] = {
    effects.fold(Set(), (out, effect) => {
      match effect {
        | SendRequest(request) => out.union(Set(choreo::Send({
            to: request.target,
            message: NetRequest({ sender: process, id: request.id }),
          })))
        | ScheduleWatchdog(id) =>
            out.union(Set(choreo::TriggerEvent(NetWatchdog(id))))
      }
    })
  }

  pure def event_transition(
    ctx: LocalContext,
    event: Event,
    consumed: CustomEffect,
    command: Command,
  ): Transition = {
    val decision = apply_event(ctx.state.core, event)
    val consumed_effects = match consumed {
      | NoConsume => Set()
      | AdvancePhase => Set(choreo::CustomEffect(AdvancePhase))
      | RecordCommand(cmd) => Set(choreo::CustomEffect(RecordCommand(cmd)))
      | ConsumeMessage(entry) =>
          Set(choreo::CustomEffect(ConsumeMessage(entry)))
      | ConsumeEvent(entry) => Set(choreo::CustomEffect(ConsumeEvent(entry)))
    }
    {
      post_state: { ...ctx.state, core: decision.post_state },
      effects: core_effects(ctx.state.process_id, decision.effects)
        .union(consumed_effects)
        .union(Set(
          choreo::CustomEffect(AdvancePhase),
          choreo::CustomEffect(RecordCommand(command)),
        )),
    }
  }

  pure def request_response(
    ctx: LocalContext,
    request: Message,
    helpful: bool,
  ): Transition = {
    val req = match request {
      | NetRequest(value) => value
      | _ => { sender: "", id: 0 }
    }
    val response = if (helpful) {
      NetHelpfulResponse({ sender: ctx.state.process_id, id: req.id })
    } else {
      NetEmptyResponse({ sender: ctx.state.process_id, id: req.id })
    }
    val command = if (helpful) {
      RespondHelpful({ sender: ctx.state.process_id, id: req.id })
    } else {
      RespondEmpty({ sender: ctx.state.process_id, id: req.id })
    }
    {
      post_state: ctx.state,
      effects: Set(
        choreo::Send({ to: req.sender, message: response }),
        choreo::CustomEffect(ConsumeMessage({
          process: ctx.state.process_id,
          message: request,
        })),
        choreo::CustomEffect(AdvancePhase),
        choreo::CustomEffect(RecordCommand(command)),
      ),
    }
  }

  pure def spontaneous_choices(ctx: LocalContext): Set[Transition] = {
    if (ctx.state.core.status == "Disconnected") {
      Set(event_transition(
        ctx,
        Open,
        NoConsume,
        OpenPeer({ peer: ctx.state.process_id }),
      ))
    } else if (
      ctx.state.process_id == "alice" and
      (ctx.state.core.status == "Error(Exhausted)" or
        ctx.state.core.status == "Error(TargetLeft)")
    ) {
      Set(event_transition(
        ctx,
        SyncApplied,
        NoConsume,
        SyncAppliedCommand,
      ))
    } else if (
      ctx.state.process_id == "alice" and ctx.state.core.status == "Idle" and
      ctx.state.core.recoveries < 2
    ) {
      Set(
        event_transition(
          ctx,
          ApplyFailed("bob"),
          NoConsume,
          StartRecovery({ target: "bob" }),
        ),
        event_transition(
          ctx,
          ApplyFailed("carol"),
          NoConsume,
          StartRecovery({ target: "carol" }),
        ),
      )
    } else {
      Set()
    }
  }

  pure def main_listener(ctx: LocalContext): Set[Transition] = {
    val requests = if (ctx.state.core.status == "Idle") {
      ctx.messages.filter(message => match message {
        | NetRequest(_) => true
        | _ => false
      })
    } else {
      Set()
    }
    val responses = ctx.messages.filter(message => match message {
      | NetEmptyResponse(_) => true
      | NetHelpfulResponse(_) => true
      | _ => false
    })
    val request_choices = requests
      .map(message => Set(
        request_response(ctx, message, false),
        request_response(ctx, message, true),
      ))
      .fold(Set(), (out, choices) => out.union(choices))
    val response_choices = if (ctx.state.process_id == "alice") {
      responses.map(message => match message {
        | NetEmptyResponse(response) => event_transition(
            ctx,
            EmptyResponse(response),
            ConsumeMessage({ process: "alice", message: message }),
            DeliverEmpty(response),
          )
        | NetHelpfulResponse(response) => event_transition(
            ctx,
            HelpfulResponse(response),
            ConsumeMessage({ process: "alice", message: message }),
            DeliverHelpful(response),
          )
        | _ => event_transition(
            ctx,
            Open,
            NoConsume,
            OpenPeer({ peer: "alice" }),
          )
      })
    } else {
      Set()
    }
    val watchdog_choices = if (ctx.state.process_id == "alice") {
      ctx.events.map(event => match event {
        | NetWatchdog(id) => event_transition(
            ctx,
            Watchdog(id),
            ConsumeEvent({ process: "alice", event: event }),
            FireWatchdog({ id: id }),
          )
      })
    } else {
      Set()
    }
    spontaneous_choices(ctx)
      .union(request_choices)
      .union(response_choices)
      .union(watchdog_choices)
  }

  pure def apply_custom_effect(ctx: GlobalContext, effect: CustomEffect): GlobalContext = {
    match effect {
      | AdvancePhase => {
          ...ctx,
          extensions: { ...ctx.extensions, phase: ctx.extensions.phase + 1 },
        }
      | RecordCommand(command) => {
          ...ctx,
          extensions: { ...ctx.extensions, command: command },
        }
      | ConsumeMessage(entry) => {
          ...ctx,
          messages: ctx.messages.setBy(entry.process, xs => xs.exclude(Set(entry.message))),
        }
      | ConsumeEvent(entry) => {
          ...ctx,
          events: ctx.events.setBy(entry.process, xs => xs.exclude(Set(entry.event))),
        }
      | NoConsume => ctx
    }
  }

  action init = choreo::init_with_displayer({
    system: NODES.mapBy(node => initialize(node)),
    messages: NODES.mapBy(_ => Set()),
    events: NODES.mapBy(_ => Set()),
    extensions: { phase: 0, command: Init },
  }, display)

  pure def open_alice(ctx: LocalContext): Set[Transition] =
    if (
      ctx.extensions.phase == 0 and ctx.state.core.status == "Disconnected"
    ) {
      Set(event_transition(
        ctx,
        Open,
        NoConsume,
        OpenPeer({ peer: "alice" }),
      ))
    } else {
      Set()
    }

  pure def open_bob(ctx: LocalContext): Set[Transition] =
    if (
      ctx.extensions.phase == 1 and ctx.state.core.status == "Disconnected"
    ) {
      Set(event_transition(
        ctx,
        Open,
        NoConsume,
        OpenPeer({ peer: "bob" }),
      ))
    } else {
      Set()
    }

  pure def open_carol(ctx: LocalContext): Set[Transition] =
    if (
      ctx.extensions.phase == 2 and ctx.state.core.status == "Disconnected"
    ) {
      Set(event_transition(
        ctx,
        Open,
        NoConsume,
        OpenPeer({ peer: "carol" }),
      ))
    } else {
      Set()
    }

  pure def start_alice(ctx: LocalContext): Set[Transition] =
    if (ctx.extensions.phase == 3 and ctx.state.core.status == "Idle") {
      Set(event_transition(
        ctx,
        ApplyFailed("bob"),
        NoConsume,
        StartRecovery({ target: "bob" }),
      ))
    } else {
      Set()
    }

  pure def bob_empty(ctx: LocalContext): Set[Transition] = {
    val request = NetRequest({ sender: "alice", id: 1 })
    if (ctx.extensions.phase == 4 and ctx.messages.contains(request)) {
      Set(request_response(ctx, request, false))
    } else {
      Set()
    }
  }

  pure def bob_helpful(ctx: LocalContext): Set[Transition] = {
    val request = NetRequest({ sender: "alice", id: 2 })
    if (ctx.extensions.phase == 7 and ctx.messages.contains(request)) {
      Set(request_response(ctx, request, true))
    } else {
      Set()
    }
  }

  pure def alice_empty(ctx: LocalContext): Set[Transition] = {
    val response = NetEmptyResponse({ sender: "bob", id: 1 })
    if (ctx.extensions.phase == 5 and ctx.messages.contains(response)) {
      Set(event_transition(
        ctx,
        EmptyResponse({ sender: "bob", id: 1 }),
        ConsumeMessage({ process: "alice", message: response }),
        DeliverEmpty({ sender: "bob", id: 1 }),
      ))
    } else {
      Set()
    }
  }

  pure def alice_stale(ctx: LocalContext): Set[Transition] = {
    val event = NetWatchdog(1)
    if (ctx.extensions.phase == 6 and ctx.events.contains(event)) {
      Set(event_transition(
        ctx,
        Watchdog(1),
        ConsumeEvent({ process: "alice", event: event }),
        FireWatchdog({ id: 1 }),
      ))
    } else {
      Set()
    }
  }

  pure def alice_helpful(ctx: LocalContext): Set[Transition] = {
    val response = NetHelpfulResponse({ sender: "bob", id: 2 })
    if (ctx.extensions.phase == 8 and ctx.messages.contains(response)) {
      Set(event_transition(
        ctx,
        HelpfulResponse({ sender: "bob", id: 2 }),
        ConsumeMessage({ process: "alice", message: response }),
        DeliverHelpful({ sender: "bob", id: 2 }),
      ))
    } else {
      Set()
    }
  }

  action openAlice = choreo::step_with_displayer(
    ctx => if (ctx.state.process_id == "alice") open_alice(ctx) else Set(),
    apply_custom_effect,
    display,
  )
  action openBob = choreo::step_with_displayer(
    ctx => if (ctx.state.process_id == "bob") open_bob(ctx) else Set(),
    apply_custom_effect,
    display,
  )
  action openCarol = choreo::step_with_displayer(
    ctx => if (ctx.state.process_id == "carol") open_carol(ctx) else Set(),
    apply_custom_effect,
    display,
  )
  action aliceStartsRecovery = choreo::step_with_displayer(
    ctx => if (ctx.state.process_id == "alice") start_alice(ctx) else Set(),
    apply_custom_effect,
    display,
  )
  action bobRepliesEmpty = choreo::step_with_displayer(
    ctx => if (ctx.state.process_id == "bob") bob_empty(ctx) else Set(),
    apply_custom_effect,
    display,
  )
  action aliceReceivesEmpty = choreo::step_with_displayer(
    ctx => if (ctx.state.process_id == "alice") alice_empty(ctx) else Set(),
    apply_custom_effect,
    display,
  )
  action aliceFiresStaleTimeout1 = choreo::step_with_displayer(
    ctx => if (ctx.state.process_id == "alice") alice_stale(ctx) else Set(),
    apply_custom_effect,
    display,
  )
  action bobRepliesHelpful = choreo::step_with_displayer(
    ctx => if (ctx.state.process_id == "bob") bob_helpful(ctx) else Set(),
    apply_custom_effect,
    display,
  )
  action aliceReceivesHelpful = choreo::step_with_displayer(
    ctx => if (ctx.state.process_id == "alice") alice_helpful(ctx) else Set(),
    apply_custom_effect,
    display,
  )

  // Deliberate model mutation used only by modelMutationStep.
  pure def unsafe_retry(ctx: LocalContext): Set[Transition] =
    if (ctx.extensions.phase == 4 and ctx.state.core.status == "Recovering") {
      Set({
        post_state: { ...ctx.state, core: { ...ctx.state.core, attempt: 5 } },
        effects: Set(
          choreo::CustomEffect(AdvancePhase),
          choreo::CustomEffect(RecordCommand(UnsafeAttemptFive)),
        ),
      })
    } else {
      Set()
    }

  action unsafeAttemptFive = choreo::step_with_displayer(
    ctx => if (ctx.state.process_id == "alice") unsafe_retry(ctx) else Set(),
    apply_custom_effect,
    display,
  )

  action step = choreo::step_with_displayer(
    main_listener,
    apply_custom_effect,
    display,
  )

  val s = choreo::s
  val safety = NODES.forall(node => {
    val core = s.system.get(node).core
    core.attempt >= 0 and core.attempt <= 4 and
    core.requestId >= 0 and core.requestId <= 8 and
    core.recoveries >= 0 and core.recoveries <= 2 and
    core.sent == core.scheduled and core.sent >= 0 and core.sent <= 8 and
    core.applied >= 0 and core.applied <= 6 and
    core.statusEvents >= 0 and core.statusEvents <= 13 and
    core.peerLeaves >= 0 and core.peerLeaves <= 1 and
    (core.status == "Disconnected" implies core.attempt == 0) and
    (core.status == "Idle" implies core.attempt == 0) and
    (core.status == "Recovering" implies {
      core.attempt >= 1 and core.attempt <= 4
    }) and
    (core.target == "" or core.target != node)
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
}
