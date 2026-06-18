// Lambda Calculus Editor — thin DOM bridge over MoonBit CRDT backend

import * as crdt from '@moonbit/crdt-lambda';
import * as graphviz from '@moonbit/graphviz';
import { HTMLAdapter } from '@canopy/editor-adapter/html-adapter';
import type { Decoration, ViewPatch } from '@canopy/editor-adapter/types';
import { runAnalysis } from './ast-grep-runner';
import { DecorationOverlay } from './decoration-overlay';

export function createEditor(agentId: string) {
  const handle = crdt.create_editor(agentId);

  const editorEl = document.getElementById('editor') as HTMLDivElement;
  const astGraphEl = document.getElementById('ast-graph') as HTMLDivElement;
  const astOutputEl = document.getElementById('ast-output') as HTMLElement;
  const errorEl = document.getElementById('error-output') as HTMLUListElement;

  // Protocol-based pretty-print adapter
  const prettyAdapter = new HTMLAdapter(astOutputEl);
  const decorationOverlay = new DecorationOverlay(editorEl);
  const analysisApi = crdt as typeof crdt & {
    apply_ast_grep_results_json(handle: number, matchesJson: string): string;
    compute_view_patches_json(handle: number): string;
  };

  let lastText = '';
  let scheduled = false;
  let analysisGeneration = 0;
  let analysisTimer: number | null = null;
  let analysisAbortController: AbortController | null = null;

  function updateUI() {
    const text = editorEl.textContent || '';
    if (text !== lastText) {
      crdt.set_text(handle, text);
      lastText = text;
      decorationOverlay.applyDecorations([]);
      scheduleAnalysis(text);
    }

    // AST visualization (DOT → SVG via graphviz module)
    try {
      const dot = crdt.get_ast_dot_resolved(handle);
      const svg = graphviz.render_dot_to_svg(dot);
      astGraphEl.innerHTML = svg;

      // Dark theme: remove white background from SVG
      const polygon = astGraphEl.querySelector('g.graph polygon');
      if (polygon) polygon.setAttribute('fill', 'transparent');
    } catch (e) {
      astGraphEl.innerHTML = `<p style="color:#f44">Error: ${e}</p>`;
    }

    // Pretty-printed AST with syntax highlighting (via protocol)
    try {
      const patches: ViewPatch[] = JSON.parse(
        crdt.compute_pretty_patches_json(handle),
      );
      prettyAdapter.applyPatches(patches);
    } catch (e) {
      astOutputEl.textContent = `Pretty-print error: ${e}`;
    }

    // Diagnostics (parse errors + eval warnings). `def_name` is present
    // on type errors inside a named binding so we can render a badge
    // instead of string-prefixing the message.
    const diags: { level: string; message: string; def_name?: string }[] = JSON.parse(
      crdt.get_diagnostics_json(handle),
    );
    if (diags.length === 0) {
      errorEl.innerHTML = '<li>No errors</li>';
    } else {
      errorEl.innerHTML = diags
        .map(d => {
          const badge = d.def_name
            ? `<span class="diag-def-badge">${escapeHTML(d.def_name)}</span> `
            : '';
          return `<li class="diag-item diag-${d.level}">${badge}${escapeHTML(d.message)}</li>`;
        })
        .join('');
    }
  }

  function scheduleAnalysis(text: string) {
    const generation = ++analysisGeneration;
    if (analysisTimer !== null) {
      window.clearTimeout(analysisTimer);
    }
    if (analysisAbortController !== null) {
      analysisAbortController.abort();
      analysisAbortController = null;
    }
    analysisTimer = window.setTimeout(() => {
      analysisTimer = null;
      void applyAnalysis(text, generation);
    }, 150);
  }

  async function applyAnalysis(text: string, generation: number) {
    const controller = new AbortController();
    analysisAbortController = controller;
    try {
      const matches = await runAnalysis(text, { signal: controller.signal });
      if (generation !== analysisGeneration) return;

      const result = analysisApi.apply_ast_grep_results_json(handle, JSON.stringify(matches));
      if (result !== 'ok') {
        console.warn(`ast-grep analysis rejected: ${result}`);
        return;
      }

      const patches: ViewPatch[] = JSON.parse(analysisApi.compute_view_patches_json(handle));
      const decorations = patches.flatMap((patch): Decoration[] =>
        patch.type === 'SetDecorations' ? patch.decorations : [],
      );
      decorationOverlay.applyDecorations(decorations);
    } catch (error) {
      if (controller.signal.aborted || generation !== analysisGeneration) return;
      console.warn('ast-grep analysis failed', error);
      decorationOverlay.applyDecorations([]);
    } finally {
      if (analysisAbortController === controller) {
        analysisAbortController = null;
      }
    }
  }

  editorEl.addEventListener('input', () => {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(() => {
      scheduled = false;
      updateUI();
    });
  });

  return {
    handle,
    agentId,
    updateUI,
    getText: () => crdt.get_text(handle),
    setText: (text: string) => {
      editorEl.textContent = text;
      editorEl.dispatchEvent(new Event('input', { bubbles: true }));
    },
  };
}

function escapeHTML(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}
