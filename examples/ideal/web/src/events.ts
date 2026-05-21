export const CanopyEvents = {
  TEXT_CHANGE: 'text-changed',
  EXTERNAL_CRDT_CHANGE: 'external-crdt-changed',
  NODE_SELECTED: 'node-selected',
  STRUCTURAL_EDIT_REQUEST: 'structural-edit-request',
  STRUCTURAL_EDIT_APPLIED: 'structural-edit-applied',
  CURSOR_MOVE: 'cursor-move',
  REQUEST_UNDO: 'request-undo',
  REQUEST_REDO: 'request-redo',
  ACTION_OVERLAY_OPEN: 'action-overlay-open',
  ACTION_KEY: 'action-key',
  LONG_PRESS: 'long-press',
} as const;
