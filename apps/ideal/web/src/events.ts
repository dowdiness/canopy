export const CanopyEvents = {
  TEXT_CHANGE: 'text-changed',
  EXTERNAL_CRDT_CHANGE: 'external-crdt-changed',
  NODE_SELECTED: 'node-selected',
  CURSOR_MOVE: 'cursor-move',
  ACTION_OVERLAY_OPEN: 'action-overlay-open',
  ACTION_KEY: 'action-key',
  LONG_PRESS: 'long-press',
  // Host → MoonBit: a file was picked and read; detail is the raw text content.
  FILE_LOADED: 'file-loaded',
} as const;
