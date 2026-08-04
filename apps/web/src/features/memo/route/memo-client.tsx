'use client';

import { type ReactNode, useCallback, useState } from 'react';
import { ImperativeDemoHost } from '../../../shared/route-lifecycle/browser/imperative-host';
import {
  mountMemoApp,
  normalizeMemoSnapshot,
  type MemoRuntime,
} from '../browser/app';
import '../browser/styles.css';

const loadMemoRuntime: (() => Promise<MemoRuntime>) | null = import.meta.env.SSR
  ? null
  : () => import('@moonbit/crdt-lambda');

function mountMemoRoute(
  container: HTMLElement,
  restoredSnapshot: unknown,
  reportRuntimeError: (error: unknown) => void,
) {
  if (loadMemoRuntime === null) {
    throw new Error('The Memo runtime is unavailable on the client');
  }
  const pendingSnapshot = normalizeMemoSnapshot(restoredSnapshot);
  let controller: ReturnType<typeof mountMemoApp> | null = null;
  let disposed = false;
  let pendingFocusToken: string | null = null;

  function dispose(): void {
    if (disposed) return;
    disposed = true;
    controller?.dispose();
    controller = null;
  }

  void loadMemoRuntime()
    .then((runtime) => {
      if (disposed) return;
      controller = mountMemoApp(container, pendingSnapshot, runtime);
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
    snapshot: () => controller?.snapshot() ?? pendingSnapshot,
    restoreFocus(token: string): boolean {
      if (controller !== null) return controller.restoreFocus(token);
      if (token !== 'memo' && token !== 'instruction') return false;
      pendingFocusToken = token;
      return true;
    },
    dispose,
  };
}

export function MemoClient({ children }: { readonly children: ReactNode }) {
  const [runtimeError, setRuntimeError] = useState<Error | null>(null);
  const mount = useCallback(
    (container: HTMLElement, restoredSnapshot: unknown) => mountMemoRoute(
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
    <ImperativeDemoHost
      demoId="memo"
      mount={mount}
      className="memo-surface"
    >
      {children}
    </ImperativeDemoHost>
  );
}
