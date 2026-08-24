///|
fn driver_control_subscription_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    DriverSubscription::Control(emit) => {
      let mut tagger = emit
      let mut disposed = false
      let mut subscription : @dom_boundary.CustomEventSubscription? = None
      let install = _ => {
        guard !disposed && subscription is None else { return }
        subscription = Some(
          @dom_boundary.listen_custom_event_id(
            "loomark-driver-target",
            "loomark-driver",
            detail => {
              guard !disposed else { return }
              scheduler.add(tagger(parse_driver_event(detail)))
            },
          ),
        ) catch {
          _ => None
        }
        match subscription {
          Some(_) => scheduler.add(tagger(Lifecycle(ControlInstalled)))
          None => ()
        }
      }
      scheduler.add(@cmd.custom_cmd(install, kind=@cmd.AfterRender))
      Some({
        unload: _ => {
          if !disposed {
            disposed = true
            match subscription {
              Some(running) => running.dispose() catch { _ => () }
              None => ()
            }
          }
        },
        update_tagger: payload => {
          guard payload is DriverSubscription::Control(new_emit) else { return }
          guard !disposed else { return }
          tagger = new_emit
        },
      })
    }
    _ => None
  }
}

///|
fn driver_test_subscription_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    DriverSubscription::Test(emit, lifecycle) => {
      let mut tagger = emit
      let mut lifecycle_tagger = lifecycle
      let mut disposed = false
      let mut installed = false
      let mut subscription : @dom_boundary.CustomEventSubscription? = None
      let install = _ => {
        guard !disposed && subscription is None else { return }
        subscription = Some(
          @dom_boundary.listen_custom_event_id(
            "loomark-event-target",
            "loomark-test",
            detail => {
              guard !disposed else { return }
              scheduler.add(tagger(detail))
            },
          ),
        ) catch {
          _ => None
        }
        match subscription {
          Some(_) => {
            installed = true
            scheduler.add(lifecycle_tagger(Lifecycle(SubscriptionInstalled)))
          }
          None => ()
        }
      }
      scheduler.add(@cmd.custom_cmd(install, kind=@cmd.AfterRender))
      Some({
        unload: scheduler => {
          if !disposed {
            disposed = true
            match subscription {
              Some(running) => {
                running.dispose() catch {
                  _ => ()
                }
                subscription = None
              }
              None => ()
            }
            if installed {
              installed = false
              scheduler.add(lifecycle_tagger(Lifecycle(SubscriptionUnloaded)))
            }
          }
        },
        update_tagger: payload => {
          guard payload is DriverSubscription::Test(new_emit, new_lifecycle) else {
            return
          }
          guard !disposed else { return }
          tagger = new_emit
          lifecycle_tagger = new_lifecycle
        },
      })
    }
    _ => None
  }
}

///|
fn projection_worker_lifetime_loader(
  payload : Error,
  _scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    DriverSubscription::WorkerLifetime(worker) =>
      Some({
        unload: _ => worker.dispose(),
        update_tagger: payload => {
          guard payload is DriverSubscription::WorkerLifetime(_) else { return }
        },
      })
    _ => None
  }
}

///|
fn driver_control_subscription(emit : @cmd.Emit[DriverEvent]) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.driver-control",
    @sub.Local,
    DriverSubscription::Control(emit),
    driver_control_subscription_loader,
  )
}

///|
fn driver_test_subscription(
  emit : @cmd.Emit[DriverEvent],
  source : String,
) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.driver-event",
    @sub.Local,
    DriverSubscription::Test(
      emit.map(detail => Lifecycle(CustomEvent(detail + "|" + source))),
      emit,
    ),
    driver_test_subscription_loader,
  )
}

///|
fn projection_worker_subscription(worker : ProjectionWorkerRuntime) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.projection-worker-lifetime",
    @sub.Local,
    DriverSubscription::WorkerLifetime(worker),
    projection_worker_lifetime_loader,
  )
}

///|
fn standalone_subscriptions(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @sub.Sub {
  if model.fatal || !model.archive_persistence_enabled {
    @sub.none
  } else {
    @sub.on_resize(emit.map(viewport => Lifecycle(Resize(viewport))))
  }
}

///|
fn private_dev_host_subscriptions(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @sub.Sub {
  let control = driver_control_subscription(emit)
  if !model.listening || model.fatal {
    control
  } else {
    @sub.batch([
      @sub.on_resize(emit.map(viewport => Lifecycle(Resize(viewport)))),
      driver_test_subscription(emit, model.document.source()),
      control,
    ])
  }
}
