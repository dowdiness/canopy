export function canopyEditTimestampMs(): number {
  const bridge = (globalThis as any).__canopy_bridge;
  if (typeof bridge?.sessionStartMs !== 'number') return 0;
  const elapsed = Math.floor(Date.now() - bridge.sessionStartMs);
  return Math.max(0, Math.min(2147483647, elapsed));
}
