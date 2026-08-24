///|
/// Imperative shell for speculative Raw Preview. Worker handles and bounded
/// scheduling remain outside the Rabbita model.
priv struct RawPreviewRuntime {
  worker : ProjectionWorkerRuntime
  mut queue : RawPreviewQueueState
}

///|
fn RawPreviewRuntime::new(agent_id : String) -> RawPreviewRuntime {
  {
    worker: ProjectionWorkerRuntime::new(agent_id),
    queue: RawPreviewQueueState::initial(),
  }
}

///|
#warnings("-unused_value")
fn RawPreviewRuntime::new_in_process(agent_id : String) -> RawPreviewRuntime {
  {
    worker: ProjectionWorkerRuntime::new_in_process(agent_id),
    queue: RawPreviewQueueState::initial(),
  }
}

///|
fn RawPreviewRuntime::dispatch(
  self : RawPreviewRuntime,
  source : String,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  let worker = self.worker
  let seed = !worker.seeded
  let source_revision = if seed {
    0
  } else {
    match checked_next(worker.source_revision) {
      Some(next) => next
      None => {
        self.queue = RawPreviewQueueState::initial()
        worker.disposed = true
        return @rabbita_runtime.none
      }
    }
  }
  let causal_version = if seed {
    "raw-preview-seed"
  } else {
    "raw-preview-" + source_revision.to_string()
  }
  worker.seeded = true
  worker.source_revision = source_revision
  worker.causal_version = causal_version
  worker.demand = { block: false, preview: true, diagnostics: false }
  @cmd.custom_cmd(scheduler => {
    let resolve = (request_id, stamp, raw) => {
      scheduler.add(
        emit(
          GotRawPreviewMsg(ProjectionCompleted(request_id, stamp, raw, source)),
        ),
      )
    }
    let stamp = worker.stamp_owner.next(
      source_revision~,
      causal_version~,
      block_intent=0,
    ) catch {
      _ => {
        self.queue = RawPreviewQueueState::initial()
        worker.disposed = true
        return
      }
    }
    let request_id = worker.client.fast_preview(source, stamp, resolve) catch {
      _ => {
        self.queue = RawPreviewQueueState::initial()
        worker.disposed = true
        return
      }
    }
    worker.current_stamp = Some(stamp)
    worker.expected_request_id = Some(request_id)
  })
}

///|
/// Keep at most one active parse and one replaceable latest source.
fn RawPreviewRuntime::request(
  self : RawPreviewRuntime,
  source : String,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  let worker = self.worker
  guard !worker.disposed else { return @rabbita_runtime.none }
  let changed = !worker.seeded || source != worker.source
  guard changed else { return @rabbita_runtime.none }
  worker.source = source
  let (queue, decision) = self.queue.request(source)
  self.queue = queue
  match decision {
    RawPreviewQueueDecision::Dispatch(next) => self.dispatch(next, emit)
    RawPreviewQueueDecision::Wait => @rabbita_runtime.none
  }
}

///|
/// Claim one completed projection and translate its transport envelope into a
/// value-level result for the pure Rabbita update.
fn RawPreviewRuntime::complete(
  self : RawPreviewRuntime,
  request_id : Int,
  expected : ProjectionStamp,
  raw : String,
  source : String,
  emit : @cmd.Emit[DriverEvent],
) -> (Bool, RawPreviewResult?, @cmd.Cmd) {
  guard self.queue.active == Some(source) else {
    return (false, None, @rabbita_runtime.none)
  }
  guard self.worker.accepts(request_id, expected) else {
    return (false, None, @rabbita_runtime.none)
  }
  let (queue, decision) = self.queue.complete(source)
  self.queue = queue
  let next_command = match decision {
    RawPreviewQueueDecision::Dispatch(next) => self.dispatch(next, emit)
    RawPreviewQueueDecision::Wait => @rabbita_runtime.none
  }
  match projection_worker_response_artifact(raw) {
    Err(_) => (true, Some(Failed), next_command)
    Ok((response_request_id, stamp, preview)) => {
      guard response_request_id == request_id && stamp == expected else {
        return (true, Some(Failed), next_command)
      }
      match preview {
        None => {
          self.worker.mark_healthy()
          (true, Some(Empty), next_command)
        }
        Some(preview) =>
          if preview.source == source {
            self.worker.mark_healthy()
            (true, Some(Ready(source, stamp, preview)), next_command)
          } else {
            (true, Some(Failed), next_command)
          }
      }
    }
  }
}

///|
/// Replace a failed runtime, drop obsolete queued work, and seed only the
/// current browser source.
fn RawPreviewRuntime::recover(
  self : RawPreviewRuntime,
  source : String,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  self.queue = RawPreviewQueueState::initial()
  self.worker.restart() catch {
    _ => {
      self.worker.disposed = true
      return @rabbita_runtime.none
    }
  }
  self.request(source, emit)
}

///|
/// Stop obsolete speculative work without destroying the reusable runtime.
fn RawPreviewRuntime::stop(self : RawPreviewRuntime) -> Unit {
  self.queue = RawPreviewQueueState::initial()
  self.worker.source = ""
  self.worker.expected_request_id = None
}

///|
fn RawPreviewRuntime::dispose(self : RawPreviewRuntime) -> Unit {
  self.stop()
  self.worker.dispose()
}

///|
fn raw_preview_subscription_loader(
  payload : Error,
  _scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    DriverSubscription::RawPreviewLifetime(runtime) =>
      Some({
        unload: _ => runtime.dispose(),
        update_tagger: payload => {
          guard payload is DriverSubscription::RawPreviewLifetime(_) else {
            return
          }
        },
      })
    _ => None
  }
}

///|
fn raw_preview_subscriptions(runtime : RawPreviewRuntime) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.raw-preview-runtime",
    @sub.Local,
    DriverSubscription::RawPreviewLifetime(runtime),
    raw_preview_subscription_loader,
  )
}
