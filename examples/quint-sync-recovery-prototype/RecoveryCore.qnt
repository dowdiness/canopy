module RecoveryCore {
  type State = {
    status: str,
    attempt: int,
    requestId: int,
    target: str,
    sent: int,
    sentKinds: str,
    scheduled: int,
    applied: int,
    statusEvents: int,
    peerLeaves: int,
  }

  type Event =
    | Open
    | ApplyFailed(str)
    | EmptyResponse({ sender: str, id: int })
    | HelpfulResponse({ sender: str, id: int })
    | Watchdog(int)
    | PeerLeft(str)

  type Effect =
    | SendRequest({ target: str, id: int })
    | ScheduleWatchdog(int)

  type Decision = {
    post_state: State,
    effects: Set[Effect],
  }

  pure def initial(): State = {
    status: "Disconnected",
    attempt: 0,
    requestId: 0,
    target: "",
    sent: 0,
    sentKinds: "",
    scheduled: 0,
    applied: 0,
    statusEvents: 0,
    peerLeaves: 0,
  }

  pure def request_kinds(n: int): str = {
    if (n == 0) { "" }
    else if (n == 1) { "SyncRequest" }
    else if (n == 2) { "SyncRequest,SyncRequest" }
    else if (n == 3) { "SyncRequest,SyncRequest,SyncRequest" }
    else { "SyncRequest,SyncRequest,SyncRequest,SyncRequest" }
  }

  pure def request(s: State, target: str): Decision = {
    val next_id = s.requestId + 1
    val next_attempt = if (s.attempt == 0) { 1 } else { s.attempt + 1 }
    {
      post_state: {
        ...s,
        status: "Recovering",
        attempt: next_attempt,
        requestId: next_id,
        target: target,
        sent: s.sent + 1,
        sentKinds: request_kinds(s.sent + 1),
        scheduled: s.scheduled + 1,
        statusEvents: s.statusEvents + 1,
      },
      effects: Set(SendRequest({ target: target, id: next_id }), ScheduleWatchdog(next_id)),
    }
  }

  pure def unchanged(s: State): Decision = { post_state: s, effects: Set() }

  pure def apply_event(s: State, ev: Event): Decision = {
    match ev {
      | Open => if (s.status == "Disconnected") {
          { post_state: { ...s, status: "Idle", statusEvents: s.statusEvents + 1 }, effects: Set() }
        } else { unchanged(s) }
      | ApplyFailed(target) => if (s.status == "Idle" and s.sent == 0 and target != "") {
          val d = request(s, target)
          { ...d, post_state: { ...d.post_state, applied: s.applied + 1 } }
        } else { unchanged(s) }
      | EmptyResponse(response) => if (s.status == "Recovering" and response.sender == s.target and response.id == s.requestId) {
          if (s.attempt < 4) { request(s, s.target) }
          else { { post_state: { ...s, status: "Error(Exhausted)", statusEvents: s.statusEvents + 1 }, effects: Set() } }
        } else { unchanged(s) }
      | Watchdog(id) => if (s.status == "Recovering" and id == s.requestId) {
          if (s.attempt < 4) { request(s, s.target) }
          else { { post_state: { ...s, status: "Error(Exhausted)", statusEvents: s.statusEvents + 1 }, effects: Set() } }
        } else { unchanged(s) }
      | HelpfulResponse(response) => if (s.status == "Recovering" and response.sender == s.target and response.id == s.requestId) {
          { post_state: { ...s, status: "Idle", attempt: 0, applied: s.applied + 2, statusEvents: s.statusEvents + 1 }, effects: Set() }
        } else { unchanged(s) }
      | PeerLeft(peer) => if (s.status == "Recovering" and peer == s.target) {
          { post_state: { ...s, status: "Error(TargetLeft)", peerLeaves: s.peerLeaves + 1, statusEvents: s.statusEvents + 1 }, effects: Set() }
        } else {
          { post_state: { ...s, peerLeaves: s.peerLeaves + 1 }, effects: Set() }
        }
    }
  }
}
