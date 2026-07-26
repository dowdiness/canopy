'use client';

// Mini-ML editor — imperative DOM shell over the MoonBit CRDT core.

import { HTMLAdapter } from '@canopy/editor-adapter/html-adapter';
import type { ViewPatch } from '@canopy/editor-adapter/types';
import type { MountedImperativeSession } from '../../../shared/route-lifecycle/browser/imperative-session';
import { DecorationOverlay } from '../../../shared/decoration-overlay';
import { runAnalysis } from './ast-grep-runner';

export type LambdaEditorRuntime = typeof import('@moonbit/crdt-lambda');
export type GraphvizRuntime = typeof import('@moonbit/graphviz');

export function mountLambdaEditor(
  root: Document | HTMLElement = globalThis.document,
  restoredSnapshot: unknown,
  crdt: LambdaEditorRuntime,
  graphviz: GraphvizRuntime,
): MountedImperativeSession {
  const document = root instanceof Document ? root : root.ownerDocument;
  const window = document.defaultView ?? globalThis.window;

  function must<T extends HTMLElement>(selector: string): T {
    const element = root.querySelector<HTMLElement>(selector);
    if (element === null) throw new Error(`Missing Mini-ML editor element ${selector}`);
    return element as T;
  }

  const surfaceEl = must<HTMLElement>('[data-lambda-ready]');
  const editorEl = must<HTMLDivElement>('#editor');
  const astGraphEl = must<HTMLDivElement>('#ast-graph');
  const astOutputEl = must<HTMLElement>('#ast-output');
  const errorEl = must<HTMLUListElement>('#error-output');
  const statusEl = must<HTMLElement>('#status');
  const exampleButtons = Array.from(root.querySelectorAll<HTMLButtonElement>('.example-btn'));
  const listenerAbort = new window.AbortController();
  const agentId = `user-${Date.now()}-${Math.random().toString(36).slice(2, 11)}`;
  const restoredSource = typeof restoredSnapshot === 'string' ? restoredSnapshot : '';

  let disposed = false;
  let inputFrame: number | null = null;
  let analysisGeneration = 0;
  let analysisTimer: number | null = null;
  let analysisAbortController: AbortController | null = null;
  let releaseHandle: (() => void) | null = null;
  let releasePrettyAdapter: (() => void) | null = null;
  let releaseDecorationOverlay: (() => void) | null = null;

  function dispose(): void {
    if (disposed) return;
    disposed = true;
    surfaceEl.inert = true;
    surfaceEl.dataset.lambdaReady = 'false';
    listenerAbort.abort();
    analysisGeneration += 1;
    if (inputFrame !== null) {
      window.cancelAnimationFrame(inputFrame);
      inputFrame = null;
    }
    if (analysisTimer !== null) {
      window.clearTimeout(analysisTimer);
      analysisTimer = null;
    }
    analysisAbortController?.abort();
    analysisAbortController = null;

    const releases = [
      ['decoration overlay', releaseDecorationOverlay],
      ['pretty-print adapter', releasePrettyAdapter],
      ['MoonBit handle', releaseHandle],
    ] as const;
    releaseDecorationOverlay = null;
    releasePrettyAdapter = null;
    releaseHandle = null;
    releases.forEach(([resource, release]) => {
      try {
        release?.();
      } catch (error) {
        console.error(`Failed to dispose Mini-ML editor ${resource}`, error);
      }
    });
  }

  try {
    const handle = crdt.create_editor(agentId);
    releaseHandle = () => crdt.destroy_editor(handle);
    const prettyAdapter = new HTMLAdapter(astOutputEl);
    releasePrettyAdapter = () => prettyAdapter.destroy();
    const decorationOverlay = new DecorationOverlay(editorEl);
    releaseDecorationOverlay = () => decorationOverlay.dispose();
    const analysisApi = crdt as LambdaEditorRuntime & {
      apply_ast_grep_results_json(handle: number, matchesJson: string): string;
      compute_view_patches_json(handle: number): string;
    };
    let lastText = '';

    function applyDecorationPatches(patches: ViewPatch[]): void {
      const decorationPatch = patches.reduce<
        Extract<ViewPatch, { type: 'SetDecorations' }> | undefined
      >(
        (last, patch) => patch.type === 'SetDecorations' ? patch : last,
        undefined,
      );
      if (decorationPatch !== undefined) {
        decorationOverlay.applyDecorations(decorationPatch.decorations);
      }
    }

    async function applyAnalysis(text: string, generation: number): Promise<void> {
      const controller = new window.AbortController();
      analysisAbortController = controller;
      try {
        const matches = await runAnalysis(text, { signal: controller.signal });
        if (disposed || generation !== analysisGeneration) return;

        const result = analysisApi.apply_ast_grep_results_json(
          handle,
          JSON.stringify(matches),
        );
        if (result !== 'ok') {
          console.warn(`ast-grep analysis rejected: ${result}`);
          return;
        }
        const patches: ViewPatch[] = JSON.parse(
          analysisApi.compute_view_patches_json(handle),
        );
        applyDecorationPatches(patches);
      } catch (error) {
        if (controller.signal.aborted || disposed || generation !== analysisGeneration) return;
        console.warn('ast-grep analysis failed', error);
      } finally {
        if (analysisAbortController === controller) analysisAbortController = null;
      }
    }

    function scheduleAnalysis(text: string): void {
      const generation = ++analysisGeneration;
      if (analysisTimer !== null) window.clearTimeout(analysisTimer);
      analysisAbortController?.abort();
      analysisAbortController = null;
      analysisTimer = window.setTimeout(() => {
        analysisTimer = null;
        void applyAnalysis(text, generation);
      }, 150);
    }

    function updateUI(): void {
      if (disposed) return;
      const text = editorEl.textContent ?? '';
      if (text !== lastText) {
        crdt.set_text(handle, text);
        lastText = text;
        const patches: ViewPatch[] = JSON.parse(
          analysisApi.compute_view_patches_json(handle),
        );
        applyDecorationPatches(patches);
        scheduleAnalysis(text);
      }

      try {
        const svg = graphviz.render_dot_to_svg(crdt.get_ast_dot_resolved(handle));
        astGraphEl.innerHTML = svg;
        astGraphEl.querySelector('g.graph polygon')?.setAttribute('fill', 'transparent');
      } catch (error) {
        astGraphEl.textContent = `AST visualization error: ${error}`;
      }

      try {
        const patches: ViewPatch[] = JSON.parse(
          crdt.compute_pretty_patches_json(handle),
        );
        prettyAdapter.applyPatches(patches);
      } catch (error) {
        astOutputEl.textContent = `Pretty-print error: ${error}`;
      }

      const diagnostics: { level: string; message: string; def_name?: string }[] = JSON.parse(
        crdt.get_diagnostics_json(handle),
      );
      errorEl.innerHTML = diagnostics.length === 0
        ? '<li>No errors</li>'
        : diagnostics.map((diagnostic) => {
            const badge = diagnostic.def_name
              ? `<span class="diag-def-badge">${escapeHTML(diagnostic.def_name)}</span> `
              : '';
            return `<li class="diag-item diag-${diagnostic.level}">${badge}${escapeHTML(diagnostic.message)}</li>`;
          }).join('');
    }

    function setText(text: string): void {
      editorEl.textContent = text;
      editorEl.dispatchEvent(new window.Event('input', { bubbles: true }));
    }

    editorEl.addEventListener('input', () => {
      if (inputFrame !== null) return;
      inputFrame = window.requestAnimationFrame(() => {
        inputFrame = null;
        updateUI();
      });
    }, { signal: listenerAbort.signal });
    exampleButtons.forEach((button) => {
      button.addEventListener('click', () => {
        const example = button.dataset.example;
        if (example !== undefined) setText(example);
      }, { signal: listenerAbort.signal });
    });

    if (restoredSource !== '') {
      editorEl.textContent = restoredSource;
      updateUI();
    }
    statusEl.textContent = `Ready! ID: ${agentId}`;
    statusEl.className = 'status success';
    surfaceEl.inert = false;
    surfaceEl.dataset.lambdaReady = 'true';

    return {
      snapshot: () => editorEl.textContent ?? '',
      restoreFocus(token: string): boolean {
        if (disposed || token !== 'editor') return false;
        editorEl.focus({ preventScroll: true });
        return document.activeElement === editorEl;
      },
      dispose,
    };
  } catch (error) {
    dispose();
    throw error;
  }
}

function escapeHTML(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}
