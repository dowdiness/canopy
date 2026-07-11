// Collaborative feature state — operations log and sync config.
//
// Shared document sync is handled by the CRDT (via export/apply_sync_json)
// or by the simple relay store below for local (non-WebSocket) mode.

export interface OperationLog {
  agentId: string;
  type: 'insert' | 'delete' | 'undo' | 'redo' | 'sync';
  content?: string;
  timestamp: number;
}

export const WS_URL = 'ws://localhost:8787';
export const ROOM_ID = 'demo-room';

const MAX_LOG_ENTRIES = 15;

// --- Operations log (simple mutable array + listeners) ---

let operations: OperationLog[] = [];
const logListeners = new Set<() => void>();

export function getOperations(): readonly OperationLog[] {
  return operations;
}

export function logOperation(entry: OperationLog): void {
  operations = [...operations, entry];
  if (operations.length > MAX_LOG_ENTRIES) {
    operations = operations.slice(operations.length - MAX_LOG_ENTRIES);
  }
  for (const l of logListeners) l();
}

export function clearOperations(): void {
  operations = [];
  for (const l of logListeners) l();
}

export function subscribeOperations(listener: () => void): () => void {
  logListeners.add(listener);
  return () => logListeners.delete(listener);
}

// --- Shared document text (for local sync mode) ---
//
// In local mode, we maintain a shared text that both editors read/write.
// In WebSocket mode, sync happens via the CRDT's export/apply_sync protocol.

let sharedText = '';
const sharedListeners = new Set<() => void>();

export function getSharedText(): string {
  return sharedText;
}

export function setSharedText(text: string): void {
  if (text !== sharedText) {
    sharedText = text;
    for (const l of sharedListeners) l();
  }
}

export function subscribeSharedText(listener: () => void): () => void {
  sharedListeners.add(listener);
  return () => sharedListeners.delete(listener);
}

export function resetSharedState(): void {
  sharedText = '';
  operations = [];
  for (const l of sharedListeners) l();
  for (const l of logListeners) l();
}
