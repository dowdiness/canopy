// CM6Adapter: CodeMirror 6 adapter for the EditorProtocol.

import {
  EditorView,
  Decoration as CmDecoration,
  ViewPlugin,
  WidgetType,
} from "@codemirror/view";
import type { DecorationSet, ViewUpdate } from "@codemirror/view";
import { StateField, StateEffect, RangeSetBuilder } from "@codemirror/state";
import { setDiagnostics } from "@codemirror/lint";
import type { Diagnostic as CmDiagnostic } from "@codemirror/lint";
import type { EditorAdapter } from './adapter';
import type { ViewPatch, UserIntent, Decoration } from './types';

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

  override eq(other: PeerCursorWidget): boolean {
    return this.label === other.label && this.cssClass === other.cssClass && this.color === other.color;
  }

  override toDOM(): HTMLElement {
    const wrapper = document.createElement("span");
    wrapper.className = this.cssClass;
    if (this.color) wrapper.style.setProperty("--color", this.color);

    const labelEl = document.createElement("span");
    labelEl.className = `${this.cssClass}-label`;
    labelEl.textContent = this.label;
    wrapper.appendChild(labelEl);

    return wrapper;
  }

  override ignoreEvent(): boolean {
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
  ] {
    return [decorationField, decorationPlugin];
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
          type: "SetDocCursor",
          doc_code_unit_offset: sel.anchor,
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
        const docLength = this.view.state.doc.length;
        const diagnostics: CmDiagnostic[] = patch.diagnostics.map((diagnostic) => {
          const from = Math.min(Math.max(0, diagnostic.from), docLength);
          const to = Math.min(Math.max(from, diagnostic.to), docLength);
          const actions =
            diagnostic.snapshot_id != null && diagnostic.diagnostic_id != null
              ? (diagnostic.fixes ?? []).map((fix) => ({
                  name: fix.title,
                  apply: () => {
                    this.intentCallback?.({
                      type: "ApplyDiagnosticFix",
                      snapshot_id: diagnostic.snapshot_id!,
                      diagnostic_id: diagnostic.diagnostic_id!,
                      fix_id: fix.id,
                    });
                  },
                }))
              : [];
          return {
            from,
            to,
            severity: diagnostic.severity,
            message: diagnostic.message,
            source: diagnostic.code ?? undefined,
            actions: actions.length > 0 ? actions : undefined,
          };
        });
        this.view.dispatch(setDiagnostics(this.view.state, diagnostics));
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
