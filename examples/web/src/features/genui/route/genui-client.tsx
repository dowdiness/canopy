'use client';

import { type ReactNode, useCallback, useState } from 'react';
import { ImperativeDemoHost } from '../../../shared/route-lifecycle/browser/imperative-host';
import type { MountedImperativeSession } from '../../../shared/route-lifecycle/browser/imperative-session';
import type { GenuiMountRuntime } from '../browser/mount.js';

const loadGenuiMount = import.meta.env.SSR
  ? null
  : () => import('../browser/mount.js');
const loadJsxRuntime: GenuiMountRuntime['loadJsx'] | null = import.meta.env.SSR
  ? null
  : () => import('@moonbit/crdt-jsx');

function mountGenuiRoute(
  container: HTMLElement,
  restoredSnapshot: unknown,
  reportRuntimeError: (error: unknown) => void,
): MountedImperativeSession {
  if (loadGenuiMount === null || loadJsxRuntime === null) {
    throw new Error('The GenUI runtime is unavailable on the client');
  }
  let controller: MountedImperativeSession | null = null;
  let disposed = false;
  let pendingFocusToken: string | null = null;

  function dispose(): void {
    if (disposed) return;
    disposed = true;
    controller?.dispose();
    controller = null;
  }

  void loadGenuiMount()
    .then(({ mountGenui }) => {
      if (disposed) return;
      controller = mountGenui(container, restoredSnapshot, {
        loadJsx: loadJsxRuntime,
        reportError: reportRuntimeError,
      });
      if (
        pendingFocusToken !== null &&
        !controller.restoreFocus(pendingFocusToken)
      ) {
        container.querySelector<HTMLElement>('[data-route-heading]')
          ?.focus({ preventScroll: true });
      }
    })
    .catch((error: unknown) => {
      if (disposed) return;
      dispose();
      reportRuntimeError(error);
    });

  return {
    snapshot: () => controller?.snapshot() ?? restoredSnapshot,
    restoreFocus(token: string): boolean {
      if (controller !== null) return controller.restoreFocus(token);
      if (
        token !== 'heading' &&
        token !== 'source' &&
        !token.startsWith('order:')
      ) return false;
      pendingFocusToken = token;
      return true;
    },
    dispose,
  };
}

export function GenuiClient({ children }: { readonly children: ReactNode }) {
  const [runtimeError, setRuntimeError] = useState<Error | null>(null);
  const mount = useCallback(
    (container: HTMLElement, restoredSnapshot: unknown) => mountGenuiRoute(
      container,
      restoredSnapshot,
      (error) => setRuntimeError(
        error instanceof Error ? error : new Error(String(error)),
      ),
    ),
    [],
  );
  if (runtimeError !== null) throw runtimeError;

  return (
    <ImperativeDemoHost demoId="genui" mount={mount}>
      {children}
    </ImperativeDemoHost>
  );
}
