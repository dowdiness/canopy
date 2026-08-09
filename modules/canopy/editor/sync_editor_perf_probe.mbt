// Shared measurement helper for the browser-only phase probe.

///|
let editor_perf_profile_depth : Ref[Int] = Ref(0)

///|
fn editor_perf_begin(name : String) -> Unit {
  if editor_perf_profile_depth.val > 0 {
    js_perf_detail_begin(name)
  }
}

///|
fn editor_perf_end(name : String) -> Unit {
  if editor_perf_profile_depth.val > 0 {
    js_perf_detail_end(name)
  }
}

///|
fn[T] editor_perf_scope(action : () -> T raise Failure) -> T raise Failure {
  if !js_perf_detail_enabled() {
    return action()
  }
  editor_perf_profile_depth.val += 1
  try {
    let result = action()
    editor_perf_profile_depth.val -= 1
    result
  } catch {
    error => {
      editor_perf_profile_depth.val -= 1
      raise error
    }
  }
}

///|
fn[T] editor_perf_measure(
  name : String,
  action : () -> T raise Failure,
) -> T raise Failure {
  if editor_perf_profile_depth.val == 0 {
    return action()
  }
  editor_perf_begin(name)
  try {
    let result = action()
    editor_perf_end(name)
    result
  } catch {
    error => {
      editor_perf_end(name)
      raise error
    }
  }
}
