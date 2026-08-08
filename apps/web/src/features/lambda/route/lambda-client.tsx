'use client';

import { type ReactNode, useCallback, useState } from 'react';
import { adaptMoonBitModule } from '@canopy/editor-adapter/moonbit-result';
import { ImperativeDemoHost } from '../../../shared/route-lifecycle/browser/imperative-host';
import {
  mountLambdaEditor,
  type GraphvizRuntime,
} from '../browser/editor';
import '../browser/styles.css';

type RawLambdaEditorRuntime = typeof import('@moonbit/crdt-lambda');
const loadLambdaRuntime: (() => Promise<[
  RawLambdaEditorRuntime,
  GraphvizRuntime,
]>) | null = import.meta.env.SSR
  ? null
  : () => Promise.all([
      import('@moonbit/crdt-lambda'),
      import('@moonbit/graphviz'),
    ]);

function mountLambdaRoute(
  container: HTMLElement,
  restoredSnapshot: unknown,
  reportRuntimeError: (error: unknown) => void,
) {
  if (loadLambdaRuntime === null) {
    throw new Error('The Mini-ML editor runtime is unavailable on the client');
  }
  let controller: ReturnType<typeof mountLambdaEditor> | null = null;
  let disposed = false;
  let pendingFocusToken: string | null = null;

  function dispose(): void {
    if (disposed) return;
    disposed = true;
    controller?.dispose();
    controller = null;
  }

  void loadLambdaRuntime()
    .then(([crdt, graphviz]) => {
      if (disposed) return;
      const adaptedRuntime = adaptMoonBitModule(crdt, {
        createFunctions: ['create_editor', 'create_editor_with_undo'],
        destroyFunctions: ['destroy_editor'],
        tryDestroyFunctions: ['try_destroy_editor'],
      });
      controller = mountLambdaEditor(
        container,
        restoredSnapshot,
        adaptedRuntime,
        graphviz,
      );
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
    snapshot: () => controller?.snapshot() ?? (
      typeof restoredSnapshot === 'string' ? restoredSnapshot : ''
    ),
    restoreFocus(token: string): boolean {
      if (controller !== null) return controller.restoreFocus(token);
      if (token !== 'editor') return false;
      pendingFocusToken = token;
      return true;
    },
    dispose,
  };
}

export function LambdaClient({ children }: { readonly children: ReactNode }) {
  const [runtimeError, setRuntimeError] = useState<Error | null>(null);
  const mount = useCallback(
    (container: HTMLElement, restoredSnapshot: unknown) => mountLambdaRoute(
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
      demoId="lambda"
      mount={mount}
      className="lambda-surface"
    >
      {children}
    </ImperativeDemoHost>
  );
}
