///|
/// Wall-clock milliseconds for expiry checks (native target).
/// Uses clock_gettime(CLOCK_REALTIME) on POSIX, GetSystemTimeAsFileTime on Windows.
fn now_ms() -> UInt64 {
  now_ms_ffi()
}

///|
extern "c" fn now_ms_ffi() -> UInt64 = "now_ms_ffi"
