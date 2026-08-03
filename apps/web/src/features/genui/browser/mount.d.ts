import type { MountedImperativeSession } from '../../../shared/route-lifecycle/browser/imperative-session';

export interface GenuiMountRuntime {
  loadJsx(): Promise<unknown>;
  reportError?(error: unknown): void;
}

export function mountGenui(
  root?: Document | HTMLElement,
  restoredSnapshot?: unknown,
  runtime?: GenuiMountRuntime,
): MountedImperativeSession;
