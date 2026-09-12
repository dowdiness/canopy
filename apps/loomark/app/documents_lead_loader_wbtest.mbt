/// Browser-shell timer subscription contract tests.

///|
priv struct LeadFakeTimer {
  callbacks : Array[() -> Unit]
  delays : Array[Int]
  cancel_calls : Array[Int]
}

///|
priv struct LeadFakeScheduler {
  commands : Array[@cmd.Cmd]
}

///|
impl @cmd.Scheduler for LeadFakeScheduler with fn queue_command(self, cmd) {
  self.commands.push(cmd)
}

///|
impl @cmd.Scheduler for LeadFakeScheduler with fn set_url_changed_injector(
  self,
  injector,
) {
  ignore((self, injector))
}

///|
impl @cmd.Scheduler for LeadFakeScheduler with fn set_url_request_injector(
  self,
  injector,
) {
  ignore((self, injector))
}

///|
impl @cmd.Context for LeadFakeScheduler with fn get_origin(_self) {
  "test"
}

///|
impl @cmd.Context for LeadFakeScheduler with fn inject_url_changed(_self, _url) {
  @cmd.none
}

///|
impl @cmd.Context for LeadFakeScheduler with fn inject_url_request(_self, _url) {
  @cmd.none
}

///|
fn lead_fake_schedule(
  timer : LeadFakeTimer,
  callback : () -> Unit,
  delay : Int,
) -> Int {
  timer.callbacks.push(callback)
  timer.delays.push(delay)
  timer.callbacks.length() - 1
}

///|
fn lead_fake_cancel(timer : LeadFakeTimer, handle : Int) -> Unit {
  timer.cancel_calls.push(handle)
}

///|
test "pending loader schedules one 250ms timer and updates its tagger" {
  let timer : LeadFakeTimer = { callbacks: [], delays: [], cancel_calls: [], }
  let scheduler : LeadFakeScheduler = { commands: [], }
  let markers : Array[String] = []
  let running = start_pending_edit_subscription(
    PendingEditSub::Apply("one", 1, () => {
      markers.push("old")
      @cmd.none
    }),
    scheduler,
    (callback, delay) => lead_fake_schedule(timer, callback, delay),
    handle => lead_fake_cancel(timer, handle),
  ).unwrap()
  assert_eq(timer.callbacks.length(), 1)
  assert_eq(timer.delays, [250])
  (running.update_tagger)(
    PendingEditSub::Apply("one", 1, () => {
      markers.push("latest")
      @cmd.none
    }),
  )
  assert_eq(timer.callbacks.length(), 1)
  timer.callbacks[0]()
  assert_eq(markers, ["latest"])
  assert_eq(scheduler.commands.length(), 1)
}

///|
test "pending loader unload cancels and mutes a queued callback" {
  let timer : LeadFakeTimer = { callbacks: [], delays: [], cancel_calls: [], }
  let scheduler : LeadFakeScheduler = { commands: [], }
  let running = start_pending_edit_subscription(
    PendingEditSub::Apply("one", 1, () => @cmd.none),
    scheduler,
    (callback, delay) => lead_fake_schedule(timer, callback, delay),
    handle => lead_fake_cancel(timer, handle),
  ).unwrap()
  let queued = timer.callbacks[0]
  (running.unload)(scheduler)
  queued()
  assert_eq(timer.cancel_calls, [0])
  assert_true(scheduler.commands.is_empty())
}

///|
test "replaced loader cancels old revision and emits only the new one" {
  let timer : LeadFakeTimer = { callbacks: [], delays: [], cancel_calls: [], }
  let scheduler : LeadFakeScheduler = { commands: [], }
  let markers : Array[String] = []
  let old = start_pending_edit_subscription(
    PendingEditSub::Apply("one", 1, () => {
      markers.push("old")
      @cmd.none
    }),
    scheduler,
    (callback, delay) => lead_fake_schedule(timer, callback, delay),
    handle => lead_fake_cancel(timer, handle),
  ).unwrap()
  let old_callback = timer.callbacks[0]
  (old.unload)(scheduler)
  let _new = start_pending_edit_subscription(
    PendingEditSub::Apply("one", 2, () => {
      markers.push("new")
      @cmd.none
    }),
    scheduler,
    (callback, delay) => lead_fake_schedule(timer, callback, delay),
    handle => lead_fake_cancel(timer, handle),
  ).unwrap()
  old_callback()
  timer.callbacks[1]()
  assert_eq(markers, ["new"])
  assert_eq(timer.cancel_calls, [0])
  assert_eq(scheduler.commands.length(), 1)
}
