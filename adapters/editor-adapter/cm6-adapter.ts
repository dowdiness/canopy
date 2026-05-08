// CM6Adapter: CodeMirror 6 adapter for the EditorProtocol.

import {
  EditorView,
  Decoration as CmDecoration,
  DecorationSet,
  ViewPlugin,
  ViewUpdate,
  WidgetType,
} from "@codemirror/view";
import { StateField, StateEffect, RangeSetBuilder } from "@codemirror/state";
import type { EditorAdapter } from './adapter';
import type { ViewPatch, UserIntent, Decoration, Diagnostic } from './types';

// ── Decoration state ────────────────────────────────────────

const setDecorations = StateEffect.define<Decoration[]>();

class PeerCursorWidget extends WidgetType {
  constructor(
    readonly label: string,
    readonly cssClass: string,
    readonly color: string,
  ) {
    super();
  }

  eq(other: PeerCursorWidget): boolean {
    return this.label === other.label && this.cssClass === other.cssClass && this.color === other.color;
  }

  toDOM(): HTMLElement {
    const wrapper = document.createElement("span");
    wrapper.className = this.cssClass;
    if (this.color) wrapper.style.setProperty("--color", this.color);

    const labelEl = document.createElement("span");
    labelEl.className = `${this.cssClass}-label`;
    labelEl.textContent = this.label;
    wrapper.appendChild(labelEl);

    return wrapper;
  }

  ignoreEvent(): boolean {
    return true;
  }
}

function buildDecorationSet(
  decorations: Decoration[],
  docLength: number,
): DecorationSet {
  const widgets: { pos: number; deco: CmDecoration }[] = [];
  const marks: { from: number; to: number; deco: CmDecoration }[] = [];

  for (const d of decorations) {
    const from = Math.min(Math.max(0, d.from), docLength);
    const to = Math.min(Math.max(0, d.to), docLength);

    if (d.widget) {
      // Extract color from data field (format: "name|color" or just "name")
      let label = d.data ?? "";
      let color = "";
      if (label.includes("|")) {
        const parts = label.split("|");
        label = parts[0];
        color = parts[1] ?? "";
      }
      widgets.push({
        pos: from,
        deco: CmDecoration.widget({
          widget: new PeerCursorWidget(label, d.css_class, color),
          side: 1,
        }),
      });
    } else {
      if (from < to) {
        marks.push({
          from,
          to,
          deco: CmDecoration.mark({ class: d.css_class }),
        });
      }
    }
  }

  widgets.sort((a, b) => a.pos - b.pos);
  marks.sort((a, b) => a.from - b.from || a.to - b.to);

  const builder = new RangeSetBuilder<CmDecoration>();

  let wi = 0;
  let mi = 0;
  while (wi < widgets.length || mi < marks.length) {
    const wPos = wi < widgets.length ? widgets[wi].pos : Infinity;
    const mPos = mi < marks.length ? marks[mi].from : Infinity;

    if (mPos <= wPos) {
      builder.add(marks[mi].from, marks[mi].to, marks[mi].deco);
      mi++;
    } else {
      builder.add(widgets[wi].pos, widgets[wi].pos, widgets[wi].deco);
      wi++;
    }
  }

  return builder.finish();
}

const decorationField = StateField.define<Decoration[]>({
  create() {
    return [];
  },
  update(value, tr) {
    for (const effect of tr.effects) {
      if (effect.is(setDecorations)) {
        return effect.value;
      }
    }
    return value;
  },
});

const decorationPlugin = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;

    constructor(view: EditorView) {
      const decos = view.state.field(decorationField);
      this.decorations = buildDecorationSet(decos, view.state.doc.length);
    }

    update(update: ViewUpdate) {
      const oldDecos = update.startState.field(decorationField);
      const newDecos = update.state.field(decorationField);
      if (oldDecos !== newDecos) {
        // Decoration array changed — full rebuild
        this.decorations = buildDecorationSet(newDecos, update.state.doc.length);
      } else if (update.docChanged) {
        // Only doc changed, decorations unchanged — remap positions
        this.decorations = this.decorations.map(update.changes);
      }
    }
  },
  {
    decorations: (v) => v.decorations,
  },
);

// ── Diagnostic state ────────────────────────────────────────

const setDiagnostics = StateEffect.define<Diagnostic[]>();

function buildDiagnosticSet(
  diagnostics: Diagnostic[],
  docLength: number,
): DecorationSet {
  const sorted = diagnostics
    .map((d) => {
      const from = Math.min(Math.max(0, d.from), docLength);
      const to = Math.min(Math.max(from, d.to), docLength);
      return { ...d, from, to };
    })
    .filter((d) => d.from < d.to)
    .sort((a, b) => a.from - b.from || a.to - b.to);

  const builder = new RangeSetBuilder<CmDecoration>();
  for (const d of sorted) {
    builder.add(
      d.from,
      d.to,
      CmDecoration.mark({
        class: `cm-diagnostic cm-diagnostic-${d.severity}`,
        // Native browser tooltip — no extra @codemirror/lint dep.
        // Consumers can override by replacing this StateField.
        attributes: { title: d.message, "data-severity": d.severity },
      }),
    );
  }
  return builder.finish();
}

const diagnosticField = StateField.define<Diagnostic[]>({
  create() {
    return [];
  },
  update(value, tr) {
    for (const effect of tr.effects) {
      if (effect.is(setDiagnostics)) {
        return effect.value;
      }
    }
    return value;
  },
});

const diagnosticPlugin = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;

    constructor(view: EditorView) {
      const diags = view.state.field(diagnosticField);
      this.decorations = buildDiagnosticSet(diags, view.state.doc.length);
    }

    update(update: ViewUpdate) {
      const oldDiags = update.startState.field(diagnosticField);
      const newDiags = update.state.field(diagnosticField);
      if (oldDiags !== newDiags) {
        this.decorations = buildDiagnosticSet(newDiags, update.state.doc.length);
      } else if (update.docChanged) {
        this.decorations = this.decorations.map(update.changes);
      }
    }
  },
  {
    decorations: (v) => v.decorations,
  },
);

// ── CM6Adapter ──────────────────────────────────────────────

export class CM6Adapter implements EditorAdapter {
  private view: EditorView;
  private intentCallback: ((intent: UserIntent) => void) | null = null;
  private updating = false;

  constructor(view: EditorView) {
    this.view = view;
  }

  /**
   * CM6 extensions required for this adapter. Include in EditorView extensions.
   */
  static extensions(): [
    typeof decorationField,
    typeof decorationPlugin,
    typeof diagnosticField,
    typeof diagnosticPlugin,
  ] {
    return [decorationField, decorationPlugin, diagnosticField, diagnosticPlugin];
  }

  /**
   * Create a CM6 updateListener that feeds user intents to the adapter.
   * The adapter must be constructed first so the reference is captured.
   */
  createUpdateListener(): ReturnType<typeof EditorView.updateListener.of> {
    return EditorView.updateListener.of((update: ViewUpdate) => {
      if (this.updating || !this.intentCallback) return;

      if (update.docChanged) {
        update.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
          this.intentCallback!({
            type: "TextEdit",
            from: fromA,
            to: toA,
            insert: inserted.toString(),
          });
        });
      }

      if (update.selectionSet && !update.docChanged) {
        const sel = update.state.selection.main;
        this.intentCallback({
          type: "SetCursor",
          position: sel.anchor,
        });
      }
    });
  }

  applyPatches(patches: ViewPatch[]): void {
    for (const patch of patches) {
      this.applyPatch(patch);
    }
  }

  onIntent(callback: (intent: UserIntent) => void): void {
    this.intentCallback = callback;
  }

  /** Does not destroy the CM6 view (caller owns it). */
  destroy(): void {
    this.intentCallback = null;
  }

  private applyPatch(patch: ViewPatch): void {
    switch (patch.type) {
      case "TextChange": {
        this.updating = true;
        try {
          this.view.dispatch({
            changes: { from: patch.from, to: patch.to, insert: patch.insert },
          });
        } finally {
          this.updating = false;
        }
        break;
      }

      case "SetDecorations": {
        this.view.dispatch({
          effects: setDecorations.of(patch.decorations),
        });
        break;
      }

      case "SetSelection": {
        this.view.dispatch({
          selection: { anchor: patch.anchor, head: patch.head },
        });
        break;
      }

      case "SetDiagnostics": {
        this.view.dispatch({
          effects: setDiagnostics.of(patch.diagnostics),
        });
        break;
      }

      case "SelectNode":
        break;

      case "FullTree":
      case "ReplaceNode":
      case "InsertChild":
      case "RemoveChild":
      case "UpdateNode":
        break;
    }
  }
}
