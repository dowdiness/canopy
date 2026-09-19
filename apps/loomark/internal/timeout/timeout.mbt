///|
priv suberror TimeoutSubscription {
  After(@cmd.Cmd)
}

///|
fn start(
  payload : Error,
  scheduler : &@cmd.Scheduler,
  milliseconds : Int,
  schedule : (() -> Unit, Int) -> Int,
  cancel : (Int) -> Unit,
) -> @sub.RunningSub? {
  guard payload is TimeoutSubscription::After(command) else { return None }
  let mut command = command
  let mut active = true
  let timer = schedule(() => if active { scheduler.add(command) }, milliseconds)
  Some({
    unload: _ => {
      active = false
      cancel(timer)
    },
    update_tagger: next => {
      guard next is TimeoutSubscription::After(next) else { return }
      command = next
    },
  })
}

///|
fn loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
  milliseconds : Int,
) -> @sub.RunningSub? {
  let window = @dom.window()
  start(
    payload,
    scheduler,
    milliseconds,
    (callback, delay) => window.set_timeout(callback, delay),
    timer => window.clear_timeout(timer),
  )
}

///|
/// Runs `command` once after the delay while this subscription remains active.
pub fn after(key : String, milliseconds : Int, command : @cmd.Cmd) -> @sub.Sub {
  @sub.custom_sub(
    "timeout.after(key=\{key},milliseconds=\{milliseconds})",
    @sub.Scope::Local,
    TimeoutSubscription::After(command),
    (payload, scheduler) => loader(payload, scheduler, milliseconds),
  )
}
