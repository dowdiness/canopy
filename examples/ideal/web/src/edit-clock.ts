const SESSION_START_KEY = "__canopy_session_start_ms";

export function canopyEditTimestampMs(): number {
  const global = globalThis as Record<string, unknown>;
  if (typeof global[SESSION_START_KEY] !== "number") {
    global[SESSION_START_KEY] = Date.now();
  }
  const start = global[SESSION_START_KEY] as number;
  const elapsed = Math.floor(Date.now() - start);
  return Math.max(0, Math.min(2147483647, elapsed));
}
