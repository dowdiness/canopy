///|
/// Wall-clock milliseconds for expiry checks (non-JS fallback).
/// Returns 0; tests use remove_outdated_at(now) with explicit timestamps.
fn now_ms() -> UInt64 {
  0UL
}
