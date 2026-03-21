/**
 * CM6 extension for rendering remote peer cursors and selections.
 *
 * Displays colored carets with name labels at peer cursor positions
 * and semi-transparent selection highlights for peer selections.
 */

import {
  EditorView,
  Decoration,
  DecorationSet,
  ViewPlugin,
  ViewUpdate,
  WidgetType,
} from "@codemirror/view";
import { StateField, StateEffect } from "@codemirror/state";
import { RangeSetBuilder } from "@codemirror/state";

// ── Data Types ─────────────────────────────────────────────

export interface PeerCursor {
  peer_id: string;
  cursor: number;
  name: string;
  color: string;
  selection: [number, number] | null;
}

// ── State Effect & Field ───────────────────────────────────

const setPeerCursors = StateEffect.define<PeerCursor[]>();

const peerCursorField = StateField.define<PeerCursor[]>({
  create() {
    return [];
  },
  update(value, tr) {
    for (const effect of tr.effects) {
      if (effect.is(setPeerCursors)) {
        return effect.value;
      }
    }
    return value;
  },
});

// ── Cursor Widget ──────────────────────────────────────────

class PeerCursorWidget extends WidgetType {
  constructor(
    readonly name: string,
    readonly color: string,
  ) {
    super();
  }

  eq(other: PeerCursorWidget): boolean {
    return this.name === other.name && this.color === other.color;
  }

  toDOM(): HTMLElement {
    const wrapper = document.createElement("span");
    wrapper.className = "peer-cursor-widget";
    wrapper.style.setProperty("--color", this.color);

    const label = document.createElement("span");
    label.className = "peer-cursor-label";
    label.style.setProperty("--color", this.color);
    label.textContent = this.name;
    wrapper.appendChild(label);

    return wrapper;
  }

  ignoreEvent(): boolean {
    return true;
  }
}

// ── Decoration Builder ─────────────────────────────────────

function buildDecorations(
  cursors: PeerCursor[],
  docLength: number,
): DecorationSet {
  // Collect all decorations: cursors (widgets) and selections (marks)
  const widgets: { pos: number; deco: Decoration }[] = [];
  const marks: { from: number; to: number; deco: Decoration }[] = [];

  for (const peer of cursors) {
    // Clamp cursor position to doc length
    const cursorPos = Math.min(Math.max(0, peer.cursor), docLength);

    widgets.push({
      pos: cursorPos,
      deco: Decoration.widget({
        widget: new PeerCursorWidget(peer.name, peer.color),
        side: 1,
      }),
    });

    if (peer.selection) {
      const selFrom = Math.min(
        Math.max(0, peer.selection[0]),
        docLength,
      );
      const selTo = Math.min(
        Math.max(0, peer.selection[1]),
        docLength,
      );
      if (selFrom !== selTo) {
        const from = Math.min(selFrom, selTo);
        const to = Math.max(selFrom, selTo);
        marks.push({
          from,
          to,
          deco: Decoration.mark({
            class: "peer-selection",
            attributes: { style: `--color: ${peer.color}` },
          }),
        });
      }
    }
  }

  // Sort by position for RangeSetBuilder (requires sorted input)
  widgets.sort((a, b) => a.pos - b.pos);
  marks.sort((a, b) => a.from - b.from || a.to - b.to);

  const builder = new RangeSetBuilder<Decoration>();

  // Merge widgets and marks in sorted order
  let wi = 0;
  let mi = 0;
  while (wi < widgets.length || mi < marks.length) {
    const wPos = wi < widgets.length ? widgets[wi].pos : Infinity;
    const mPos = mi < marks.length ? marks[mi].from : Infinity;

    if (mPos < wPos) {
      builder.add(marks[mi].from, marks[mi].to, marks[mi].deco);
      mi++;
    } else if (wPos < mPos) {
      builder.add(widgets[wi].pos, widgets[wi].pos, widgets[wi].deco);
      wi++;
    } else {
      // Same position: marks before widgets (marks have extent)
      if (mi < marks.length && marks[mi].from === mPos) {
        builder.add(marks[mi].from, marks[mi].to, marks[mi].deco);
        mi++;
      } else {
        builder.add(widgets[wi].pos, widgets[wi].pos, widgets[wi].deco);
        wi++;
      }
    }
  }

  return builder.finish();
}

// ── View Plugin ────────────────────────────────────────────

const peerCursorPlugin = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;

    constructor(view: EditorView) {
      const cursors = view.state.field(peerCursorField);
      this.decorations = buildDecorations(cursors, view.state.doc.length);
    }

    update(update: ViewUpdate) {
      // Rebuild decorations when the field changes or the document changes
      // (document changes shift positions)
      const oldCursors = update.startState.field(peerCursorField);
      const newCursors = update.state.field(peerCursorField);
      if (oldCursors !== newCursors || update.docChanged) {
        this.decorations = buildDecorations(
          newCursors,
          update.state.doc.length,
        );
      }
    }
  },
  {
    decorations: (v) => v.decorations,
  },
);

// ── Public API ─────────────────────────────────────────────

/**
 * CM6 extension for peer cursor rendering.
 * Add to the CM6 extensions array.
 */
export function peerCursors(): [typeof peerCursorField, typeof peerCursorPlugin] {
  return [peerCursorField, peerCursorPlugin];
}

/**
 * Dispatch updated peer cursor positions to the CM6 editor.
 */
export function updatePeerCursors(
  view: EditorView,
  cursors: PeerCursor[],
): void {
  view.dispatch({
    effects: setPeerCursors.of(cursors),
  });
}
