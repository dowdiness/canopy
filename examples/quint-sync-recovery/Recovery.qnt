module Recovery {
  var phase: int
  var status: str
  var attempt: int
  var sent: int
  var sentKinds: str
  var scheduled: int
  var applied: int
  var statusEvents: int
  var peerLeaves: int

  action init = all {
    phase' = 0,
    status' = "Disconnected",
    attempt' = 0,
    sent' = 0,
    sentKinds' = "",
    scheduled' = 0,
    applied' = 0,
    statusEvents' = 0,
    peerLeaves' = 0,
  }

  action open = all {
    phase == 0,
    phase' = 1,
    status' = "Idle",
    attempt' = 0,
    sent' = sent,
    sentKinds' = sentKinds,
    scheduled' = scheduled,
    applied' = applied,
    statusEvents' = statusEvents + 1,
    peerLeaves' = peerLeaves,
  }

  action startRecovery = all {
    phase == 1,
    phase' = 2,
    status' = "Recovering(alice,1)",
    attempt' = 1,
    sent' = 1,
    sentKinds' = "SyncRequest",
    scheduled' = 1,
    applied' = 1,
    statusEvents' = statusEvents + 1,
    peerLeaves' = peerLeaves,
  }

  action watchdogCurrent = all {
    phase == 2 or phase == 4 or phase == 5,
    phase' = phase + 1,
    status' = if (phase == 2) { "Recovering(alice,2)" } else if (phase == 4) {
      "Recovering(alice,3)"
    } else { "Recovering(alice,4)" },
    attempt' = attempt + 1,
    sent' = sent + 1,
    sentKinds' = if (phase == 2) { "SyncRequest,SyncRequest" } else if (phase == 4) {
      "SyncRequest,SyncRequest,SyncRequest"
    } else { "SyncRequest,SyncRequest,SyncRequest,SyncRequest" },
    scheduled' = scheduled + 1,
    applied' = applied,
    statusEvents' = statusEvents + 1,
    peerLeaves' = peerLeaves,
  }

  action watchdogStale = all {
    phase == 3,
    phase' = 4,
    status' = status,
    attempt' = attempt,
    sent' = sent,
    sentKinds' = sentKinds,
    scheduled' = scheduled,
    applied' = applied,
    statusEvents' = statusEvents,
    peerLeaves' = peerLeaves,
  }

  action watchdogExhaust = all {
    phase == 6,
    phase' = 7,
    status' = "Error(Exhausted(peer_id=alice))",
    attempt' = 4,
    sent' = sent,
    sentKinds' = sentKinds,
    scheduled' = scheduled,
    applied' = applied,
    statusEvents' = statusEvents + 1,
    peerLeaves' = peerLeaves,
  }

  action noteSyncApplied = all {
    phase == 7,
    phase' = 8,
    status' = "Idle",
    attempt' = 0,
    sent' = sent,
    sentKinds' = sentKinds,
    scheduled' = scheduled,
    applied' = applied,
    statusEvents' = statusEvents + 1,
    peerLeaves' = peerLeaves,
  }

  action startRecoveryAgain = all {
    phase == 8,
    phase' = 9,
    status' = "Recovering(alice,1)",
    attempt' = 1,
    sent' = sent + 1,
    sentKinds' = "SyncRequest,SyncRequest,SyncRequest,SyncRequest,SyncRequest",
    scheduled' = scheduled + 1,
    applied' = applied + 1,
    statusEvents' = statusEvents + 1,
    peerLeaves' = peerLeaves,
  }

  action peerLeftTarget = all {
    phase == 9,
    phase' = 10,
    status' = "Error(TargetLeft(peer_id=alice))",
    attempt' = attempt,
    sent' = sent,
    sentKinds' = sentKinds,
    scheduled' = scheduled,
    applied' = applied,
    statusEvents' = statusEvents + 1,
    peerLeaves' = peerLeaves + 1,
  }

  action done = all {
    phase == 10,
    phase' = phase,
    status' = status,
    attempt' = attempt,
    sent' = sent,
    sentKinds' = sentKinds,
    scheduled' = scheduled,
    applied' = applied,
    statusEvents' = statusEvents,
    peerLeaves' = peerLeaves,
  }

  val safety =
    phase >= 0 and phase <= 10 and
    attempt >= 0 and attempt <= 4 and
    sent == scheduled and
    sent >= 0 and scheduled >= 0 and applied >= 0 and
    statusEvents >= 0 and peerLeaves >= 0 and
    sent <= 5 and scheduled <= 5 and applied <= 2 and
    statusEvents <= 9 and peerLeaves <= 1

  action step = any {
    open,
    startRecovery,
    watchdogCurrent,
    watchdogStale,
    watchdogExhaust,
    noteSyncApplied,
    startRecoveryAgain,
    peerLeftTarget,
    done,
  }
}
