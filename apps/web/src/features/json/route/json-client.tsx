'use client';

import { type ReactNode, useCallback, useState } from 'react';
import { adaptMoonBitModule } from '@canopy/editor-adapter/moonbit-result';
import { ImperativeDemoHost } from '../../../shared/route-lifecycle/browser/imperative-host';
import { mountJsonEditor } from '../browser/editor';
import '../browser/styles.css';

type RawJsonEditorRuntime = typeof import('@moonbit/crdt-json');
const loadJsonRuntime: (() => Promise<RawJsonEditorRuntime>) | null = import.meta.env.SSR
  ? null
  : () => import('@moonbit/crdt-json');

function mountJsonRoute(
  container: HTMLElement,
  restoredSnapshot: unknown,
  reportRuntimeError: (error: unknown) => void,
) {
  if (loadJsonRuntime === null) {
    throw new Error('The JSON editor runtime is unavailable on the client');
  }
  let controller: ReturnType<typeof mountJsonEditor> | null = null;
  let disposed = false;
  let pendingFocusToken: string | null = null;

  function dispose(): void {
    if (disposed) return;
    disposed = true;
    controller?.dispose();
    controller = null;
  }

  void loadJsonRuntime()
    .then((runtime) => {
      if (disposed) return;
      const adaptedRuntime = adaptMoonBitModule(runtime, {
        createFunctions: ['create_json_editor'],
        destroyFunctions: ['destroy_json_editor'],
        tryDestroyFunctions: ['try_destroy_json_editor'],
      });
      controller = mountJsonEditor(container, restoredSnapshot, adaptedRuntime);
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
      if (token !== 'editor' && token !== 'structure-toggle') return false;
      pendingFocusToken = token;
      return true;
    },
    dispose,
  };
}

export function JsonClient({ children }: { readonly children: ReactNode }) {
  const [runtimeError, setRuntimeError] = useState<Error | null>(null);
  const mount = useCallback(
    (container: HTMLElement, restoredSnapshot: unknown) => mountJsonRoute(
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
      demoId="json"
      mount={mount}
      className="json-surface"
    >
      {children}
    </ImperativeDemoHost>
  );
}
