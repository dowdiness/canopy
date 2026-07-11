// EditorAdapter: Framework-agnostic interface for rendering ViewPatch streams.

import type { ViewPatch, UserIntent } from './types';

export interface EditorAdapter {
  /** Apply patches from MoonBit ViewUpdater */
  applyPatches(patches: ViewPatch[]): void;

  /** Register callback for user intents */
  onIntent(callback: (intent: UserIntent) => void): void;

  /** Clear transient UI state (e.g. collapse) on document replacement */
  resetCollapseState?(): void;

  /** Clean up resources */
  destroy(): void;
}
