///|
priv struct FakeTimer {
  callbacks : Array[() -> Unit]
  delays : Array[Int]
  cancellations : Array[Int]
}

///|
priv struct FakeScheduler {
  commands : Array[@cmd.Cmd]
}

///|
impl @cmd.Scheduler for FakeScheduler with fn queue_command(self, command) {
  self.commands.push(command)
}

///|
impl @cmd.Scheduler for FakeScheduler with fn set_url_changed_injector(
  self,
  injector,
) {
  ignore((self, injector))
}

///|
impl @cmd.Scheduler for FakeScheduler with fn set_url_request_injector(
  self,
  injector,
) {
  ignore((self, injector))
}

///|
impl @cmd.Context for FakeScheduler with fn get_origin(_self) {
  "test"
}

///|
impl @cmd.Context for FakeScheduler with fn inject_url_changed(_self, _url) {
  @cmd.none
}

///|
impl @cmd.Context for FakeScheduler with fn inject_url_request(_self, _url) {
  @cmd.none
}

///|
fn schedule(timer : FakeTimer, callback : () -> Unit, delay : Int) -> Int {
  timer.callbacks.push(callback)
  timer.delays.push(delay)
  timer.callbacks.length() - 1
}

///|
fn cancel(timer : FakeTimer, handle : Int) -> Unit {
  timer.cancellations.push(handle)
}

///|
async test "the active timeout emits its latest command once" {
  let timer : FakeTimer = { callbacks: [], delays: [], cancellations: [], }
  let scheduler : FakeScheduler = { commands: [], }
  let markers : Array[String] = []
  let running = start(
    TimeoutSubscription::After(@cmd.custom_cmd(_ => markers.push("old"))),
    scheduler,
    250,
    (callback, delay) => schedule(timer, callback, delay),
    handle => cancel(timer, handle),
  ).unwrap()
  assert_eq(timer.delays, [250])
  (running.update_tagger)(
    TimeoutSubscription::After(@cmd.custom_cmd(_ => markers.push("latest"))),
  )
  timer.callbacks[0]()
  assert_eq(timer.callbacks.length(), 1)
  assert_eq(scheduler.commands.length(), 1)
  @rabbita_testing.run_cmd(scheduler.commands[0])
  assert_eq(markers, ["latest"])
}

///|
test "unloading cancels and mutes an already queued callback" {
  let timer : FakeTimer = { callbacks: [], delays: [], cancellations: [], }
  let scheduler : FakeScheduler = { commands: [], }
  let running = start(
    TimeoutSubscription::After(@cmd.none),
    scheduler,
    250,
    (callback, delay) => schedule(timer, callback, delay),
    handle => cancel(timer, handle),
  ).unwrap()
  let queued = timer.callbacks[0]
  (running.unload)(scheduler)
  queued()
  assert_eq(timer.cancellations, [0])
  assert_true(scheduler.commands.is_empty())
}
