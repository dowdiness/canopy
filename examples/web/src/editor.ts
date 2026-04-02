// Lambda Calculus Editor — thin DOM bridge over MoonBit CRDT backend

import * as crdt from '@moonbit/crdt';
import * as graphviz from '@moonbit/graphviz';
import { HTMLAdapter } from '../../../lib/editor-adapter/html-adapter';
import type { ViewPatch } from '../../../lib/editor-adapter/types';

export function createEditor(agentId: string) {
  const handle = crdt.create_editor(agentId);

  const editorEl = document.getElementById('editor') as HTMLDivElement;
  const astGraphEl = document.getElementById('ast-graph') as HTMLDivElement;
  const astOutputEl = document.getElementById('ast-output') as HTMLElement;
  const errorEl = document.getElementById('error-output') as HTMLUListElement;

  // Protocol-based pretty-print adapter
  const prettyAdapter = new HTMLAdapter(astOutputEl);

  let lastText = '';
  let scheduled = false;

  function updateUI() {
    const text = editorEl.textContent || '';
    if (text !== lastText) {
      crdt.set_text(handle, text);
      lastText = text;
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

    // Errors
    const errors: string[] = JSON.parse(crdt.get_errors_json(handle));
    if (errors.length === 0) {
      errorEl.innerHTML = '<li>No errors</li>';
    } else {
      errorEl.innerHTML = errors
        .map(e => `<li class="error-item">${escapeHTML(e)}</li>`)
        .join('');
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
