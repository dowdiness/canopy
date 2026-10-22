import * as core from './core.mjs';
import * as store from './store.mjs';

// Platform adapters only. Request sequencing and operation behavior belong to
// the compiled MoonBit Worker module.
export function close() {
  self.close();
}


export function now() {
  return performance.now();
}

export function uuid() {
  return crypto.randomUUID();
}

export function delay(milliseconds) {
  return new Promise(resolve => setTimeout(resolve, milliseconds));
}

export function invoke(name, ...args) {
  const value = helpers[name];
  if (typeof value === 'function') return value(...args);
  if (value !== undefined && args.length === 0) return value;
  throw Error(`Unknown native helper: ${name}`);
}

export const helpers = Object.freeze({
  close,
  now,
  uuid,
  delay,
  snapshotChanges: core.snapshotChanges,
  scalarAt: core.scalarAt,
  boundedPacket: core.boundedPacket,
  knowledge: core.knowledge,
  contains: core.contains,
  MAX_OPS: core.MAX_OPS,
  oversizedPayload,
  settle,
  ...store,
});
export function oversizedPayload(payload) {
  const message = JSON.parse(payload);
  message.operations = Array(100001).fill(message.operations[0]);
  return JSON.stringify(message);
}
export function settle(promise) {
  return Promise.resolve(promise).then(
    value => ({ ok: true, value }),
    error => ({ ok: false, error: error?.message || String(error) }),
  );
}
