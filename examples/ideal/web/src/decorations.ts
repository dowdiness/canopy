// ProseMirror decoration plugins for peer cursors and error squigglies.
//
// - peerCursorPlugin: shows colored carets + name labels at peer positions
// - errorDecoPlugin:  underlines parse error spans with squiggly decorations

import { Decoration, DecorationSet } from "prosemirror-view";
import { Plugin, PluginKey } from "prosemirror-state";
import type { Node as PmNode } from "prosemirror-model";
import type { Transaction } from "prosemirror-state";

// ---------------------------------------------------------------------------
// Peer cursors
// ---------------------------------------------------------------------------

export interface PeerCursor {
  name: string;
  color: string;
  /** PM document position of the peer's caret. */
  pos: number;
}

export const peerCursorKey = new PluginKey<DecorationSet>("peer-cursors");

export function peerCursorPlugin(): Plugin {
  return new Plugin({
    key: peerCursorKey,
    state: {
      init(): DecorationSet {
        return DecorationSet.empty;
      },
      apply(tr: Transaction, decos: DecorationSet): DecorationSet {
        const peers: PeerCursor[] | undefined = tr.getMeta(peerCursorKey);
        if (peers) {
          return createPeerDecos(tr.doc, peers);
        }
        return decos.map(tr.mapping, tr.doc);
      },
    },
    props: {
      decorations(state) {
        return peerCursorKey.getState(state);
      },
    },
  });
}

function createPeerDecos(
  doc: PmNode,
  peers: PeerCursor[],
): DecorationSet {
  const decos: Decoration[] = [];
  for (const peer of peers) {
    if (peer.pos < 0 || peer.pos > doc.content.size) continue;

    const widget = document.createElement("span");
    widget.className = "peer-cursor";
    widget.style.borderLeft = `2px solid ${peer.color}`;

    const label = document.createElement("span");
    label.className = "peer-cursor-label";
    label.textContent = peer.name;
    label.style.backgroundColor = peer.color;
    widget.appendChild(label);

    decos.push(Decoration.widget(peer.pos, widget, { side: 1 }));
  }
  return DecorationSet.create(doc, decos);
}

// ---------------------------------------------------------------------------
// Error squiggly decorations
// ---------------------------------------------------------------------------

export interface ErrorRange {
  /** Start position in the PM document. */
  start: number;
  /** End position in the PM document (exclusive). */
  end: number;
  /** Human-readable error message, shown on hover. */
  message: string;
}

export const errorDecoKey = new PluginKey<DecorationSet>(
  "error-decorations",
);

export function errorDecoPlugin(): Plugin {
  return new Plugin({
    key: errorDecoKey,
    state: {
      init(): DecorationSet {
        return DecorationSet.empty;
      },
      apply(tr: Transaction, decos: DecorationSet): DecorationSet {
        const errors: ErrorRange[] | undefined = tr.getMeta(errorDecoKey);
        if (errors) {
          return createErrorDecos(tr.doc, errors);
        }
        return decos.map(tr.mapping, tr.doc);
      },
    },
    props: {
      decorations(state) {
        return errorDecoKey.getState(state);
      },
    },
  });
}

function createErrorDecos(
  doc: PmNode,
  errors: ErrorRange[],
): DecorationSet {
  const decos: Decoration[] = [];
  for (const err of errors) {
    if (err.start < 0 || err.end > doc.content.size || err.start >= err.end) {
      continue;
    }
    decos.push(
      Decoration.inline(err.start, err.end, {
        class: "error-squiggly",
        title: err.message,
      }),
    );
  }
  return DecorationSet.create(doc, decos);
}

// ---------------------------------------------------------------------------
// Eval ghost decorations (inline reduction results)
// ---------------------------------------------------------------------------

export interface EvalResult {
  /** PM document position at the end of the expression. */
  pos: number;
  /** Human-readable result string, e.g. "→ 84". */
  result: string;
}

export const evalGhostKey = new PluginKey<DecorationSet>("eval-ghosts");

/**
 * PM plugin that renders inline "ghost" decorations showing evaluation
 * results next to expressions. Feed results by setting tr.setMeta(evalGhostKey, results).
 *
 * Actual evaluation / reduction is out of scope — this is the decoration
 * infrastructure only. Consumers dispatch a transaction with EvalResult[]
 * metadata to update the displayed ghosts.
 */
export function evalGhostPlugin(): Plugin {
  return new Plugin({
    key: evalGhostKey,
    state: {
      init(): DecorationSet {
        return DecorationSet.empty;
      },
      apply(tr: Transaction, decos: DecorationSet): DecorationSet {
        const results: EvalResult[] | undefined = tr.getMeta(evalGhostKey);
        if (results) {
          return createEvalDecos(tr.doc, results);
        }
        return decos.map(tr.mapping, tr.doc);
      },
    },
    props: {
      decorations(state) {
        return evalGhostKey.getState(state);
      },
    },
  });
}

function createEvalDecos(
  doc: PmNode,
  results: EvalResult[],
): DecorationSet {
  const decos: Decoration[] = [];
  for (const res of results) {
    if (res.pos < 0 || res.pos > doc.content.size) continue;

    const ghost = document.createElement("span");
    ghost.className = "eval-ghost";
    ghost.textContent = res.result;
    ghost.style.opacity = "0.5";
    ghost.style.marginLeft = "8px";
    ghost.style.fontStyle = "italic";

    decos.push(Decoration.widget(res.pos, ghost, { side: 1 }));
  }
  return DecorationSet.create(doc, decos);
}
