module RecoveryDistributed {
  import RecoveryCore.* from "RecoveryCore"

  // Verify-oriented, monomorphic network shell around RecoveryCore. Choreo
  // remains the simulation/trace layer; this module avoids its generic rows,
  // higher-order listener types, and custom-effect processor.
  type Message = {
    kind: int,
    sender: str,
    target: str,
    id: int,
  }

  type SystemState = {
    local: State,
    messages: Set[Message],
    watchdogs: Set[int],
    left: Set[str],
  }

  pure val ALICE = "alice"
  pure val BOB = "bob"
  pure val CAROL = "carol"
  pure val RESPONDERS = Set(BOB, CAROL)
  pure val REQUEST = 0
  pure val EMPTY_RESPONSE = 1
  pure val HELPFUL_RESPONSE = 2

  var s: SystemState

  action init = s' = {
    local: initial,
    messages: Set(),
    watchdogs: Set(),
    left: Set(),
  }

  pure def apply_decision(base: SystemState, decision: Decision): SystemState = {
    val post = decision.post_state
    val request = SendRequest({ target: post.target, id: post.requestId })
    val schedule = ScheduleWatchdog(post.requestId)
    val messages = if (decision.effects.contains(request)) {
      base.messages.union(Set({
        kind: REQUEST,
        sender: ALICE,
        target: post.target,
        id: post.requestId,
      }))
    } else {
      base.messages
    }
    val watchdogs = if (decision.effects.contains(schedule)) {
      base.watchdogs.union(Set(post.requestId))
    } else {
      base.watchdogs
    }
    { ...base, local: post, messages: messages, watchdogs: watchdogs }
  }

  action open = all {
    s.local.status == "Disconnected",
    s' = apply_decision(s, apply_event(s.local, Open)),
  }

  action startRecovery = {
    nondet target = oneOf(RESPONDERS.exclude(s.left))
    val decision = apply_event(s.local, ApplyFailed(target))
    all {
      s.local.status == "Idle",
      s.local.recoveries < 2,
      s' = apply_decision(s, decision),
    }
  }

  pure def is_request(message: Message): bool =
    message.kind == REQUEST and message.sender == ALICE and
    RESPONDERS.contains(message.target)

  pure def respond(
    state: SystemState,
    request: Message,
    kind: int,
  ): SystemState = {
    val without_request = state.messages.exclude(Set(request))
    val response = {
      kind: kind,
      sender: request.target,
      target: ALICE,
      id: request.id,
    }
    { ...state, messages: without_request.union(Set(response)) }
  }

  action responder = {
    nondet request = oneOf(
      s.messages.filter(message => {
        is_request(message) and not(s.left.contains(message.target))
      }),
    )
    any {
      s' = respond(s, request, EMPTY_RESPONSE),
      s' = respond(s, request, HELPFUL_RESPONSE),
    }
  }

  pure def is_response(message: Message): bool =
    (message.kind == EMPTY_RESPONSE or message.kind == HELPFUL_RESPONSE) and
    RESPONDERS.contains(message.sender) and message.target == ALICE

  pure def deliver_response(
    state: SystemState,
    response: Message,
  ): SystemState = {
    val base = {
      ...state,
      messages: state.messages.exclude(Set(response)),
    }
    val event = if (response.kind == EMPTY_RESPONSE) {
      EmptyResponse({ sender: response.sender, id: response.id })
    } else {
      HelpfulResponse({ sender: response.sender, id: response.id })
    }
    apply_decision(base, apply_event(state.local, event))
  }

  action responseDelivery = {
    nondet response = oneOf(s.messages.filter(is_response))
    s' = deliver_response(s, response)
  }

  pure def deliver_watchdog(state: SystemState, id: int): SystemState = {
    val base = { ...state, watchdogs: state.watchdogs.exclude(Set(id)) }
    apply_decision(base, apply_event(state.local, Watchdog(id)))
  }

  action watchdogDelivery = {
    nondet id = oneOf(s.watchdogs)
    s' = deliver_watchdog(s, id)
  }

  action peerLeaves = {
    nondet peer = oneOf(RESPONDERS.exclude(s.left))
    val decision = apply_event(s.local, PeerLeft(peer))
    all {
      s.local.status == "Recovering",
      s' = {
        ...apply_decision(s, decision),
        left: s.left.union(Set(peer)),
      },
    }
  }

  action syncApplied = all {
    s.local.status == "Error(Exhausted)" or
      s.local.status == "Error(TargetLeft)",
    s' = apply_decision(s, apply_event(s.local, SyncApplied)),
  }

  // Deliberate invalid transition, reachable only through modelMutationStep.
  action unsafeAttemptFive = all {
    s.local.status == "Recovering",
    s' = { ...s, local: { ...s.local, attempt: 5 } },
  }

  action progressStep = any {
    open,
    startRecovery,
    responder,
    responseDelivery,
    watchdogDelivery,
    peerLeaves,
    syncApplied,
  }

  action done = s' = s
  action step = any { progressStep, done }
  action modelMutationStep =
    if (s.local.status == "Disconnected") open
    else if (s.local.status == "Idle") startRecovery
    else unsafeAttemptFive

  val localSafety =
    s.local.attempt >= 0 and s.local.attempt <= 4 and
    s.local.requestId >= 0 and s.local.requestId <= 8 and
    s.local.recoveries >= 0 and s.local.recoveries <= 2 and
    s.local.sent == s.local.scheduled and
    s.local.sent >= 0 and s.local.sent <= 8 and
    s.local.applied >= 0 and s.local.applied <= 6 and
    s.local.statusEvents >= 0 and s.local.statusEvents <= 13 and
    s.local.peerLeaves >= 0 and s.local.peerLeaves <= 2 and
    (s.local.status == "Disconnected" implies {
      s.local.attempt == 0 and s.local.target == ""
    }) and
    (s.local.status == "Idle" implies {
      s.local.attempt == 0 and s.local.target == ""
    }) and
    (s.local.status == "Recovering" implies {
      s.local.attempt >= 1 and s.local.attempt <= 4 and
      RESPONDERS.contains(s.local.target)
    }) and
    ((s.local.status == "Error(Exhausted)" or
      s.local.status == "Error(TargetLeft)") implies {
      s.local.attempt >= 1 and s.local.attempt <= 4 and
      RESPONDERS.contains(s.local.target)
    })

  val networkSafety =
    s.messages.size() <= 8 and s.watchdogs.size() <= 8 and
    s.left.subseteq(RESPONDERS) and
    s.messages.forall(message => {
      message.id >= 1 and message.id <= 8 and
      message.sender != message.target and
      if (message.kind == REQUEST) {
        message.sender == ALICE and RESPONDERS.contains(message.target)
      } else {
        (message.kind == EMPTY_RESPONSE or message.kind == HELPFUL_RESPONSE) and
        RESPONDERS.contains(message.sender) and message.target == ALICE
      }
    }) and
    s.watchdogs.forall(id => id >= 1 and id <= 8)

  val safety = localSafety and networkSafety
}
