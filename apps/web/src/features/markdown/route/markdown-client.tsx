'use client';

import { type ReactNode, useCallback, useState } from 'react';
import { adaptMoonBitModule } from '@canopy/editor-adapter/moonbit-result';
import { ImperativeDemoHost } from '../../../shared/route-lifecycle/browser/imperative-host';
import { mountMarkdownApp } from '../browser/app';
import '../browser/styles.css';

type RawMarkdownEditorRuntime = typeof import('@moonbit/crdt-markdown');
const loadMarkdownRuntime: (() => Promise<RawMarkdownEditorRuntime>) | null = import.meta.env.SSR
  ? null
  : () => import('@moonbit/crdt-markdown');

function mountMarkdownRoute(
  container: HTMLElement,
  restoredSnapshot: unknown,
  reportRuntimeError: (error: unknown) => void,
) {
  if (loadMarkdownRuntime === null) {
    throw new Error('The Markdown editor runtime is unavailable on the client');
  }
  let controller: ReturnType<typeof mountMarkdownApp> | null = null;
  let disposed = false;
  let pendingFocusToken: string | null = null;

  function dispose(): void {
    if (disposed) return;
    disposed = true;
    controller?.dispose();
    controller = null;
  }

  void loadMarkdownRuntime()
    .then((runtime) => {
      if (disposed) return;
      const adaptedRuntime = adaptMoonBitModule(runtime, {
        createFunctions: ['create_markdown_editor'],
        destroyFunctions: ['destroy_markdown_editor'],
        tryDestroyFunctions: ['try_destroy_markdown_editor'],
      });
      controller = mountMarkdownApp(container, restoredSnapshot, adaptedRuntime);
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
      if (!['mode-block', 'mode-raw', 'mode-preview', 'raw-editor'].includes(token)) {
        return false;
      }
      pendingFocusToken = token;
      return true;
    },
    dispose,
  };
}

export function MarkdownClient({ children }: { readonly children: ReactNode }) {
  const [runtimeError, setRuntimeError] = useState<Error | null>(null);
  const mount = useCallback(
    (container: HTMLElement, restoredSnapshot: unknown) => mountMarkdownRoute(
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
      demoId="markdown"
      mount={mount}
      className="markdown-surface"
    >
      {children}
    </ImperativeDemoHost>
  );
}
