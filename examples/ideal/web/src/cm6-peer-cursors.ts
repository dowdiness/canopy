/**
 * CM6 extension factory for rendering remote peer cursors and selections.
 *
 * The rabbita binding passes the exact CodeMirror namespace used to create the
 * editor. Build every CM object from that namespace to avoid mixing multiple
 * @codemirror/state instances.
 */

// -- Data Types -------------------------------------------------------------

export interface PeerCursor {
  peer_id: string;
  cursor: number;
  name: string;
  color: string;
  selection: [number, number] | null;
}

type CmNamespace = Record<string, any>;

let activeView: any = null;
let activeSetPeerCursors: any = null;

// -- Extension Factory ------------------------------------------------------

export function peerCursors(cm: CmNamespace): any[] {
  const {
    Decoration,
    EditorView,
    RangeSetBuilder,
    StateEffect,
    StateField,
    ViewPlugin,
    WidgetType,
  } = cm;

  const setPeerCursors = StateEffect.define<PeerCursor[]>();
  activeSetPeerCursors = setPeerCursors;

  const peerCursorField = StateField.define<PeerCursor[]>({
    create() {
      return [];
    },
    update(value: PeerCursor[], tr: any) {
      for (const effect of tr.effects) {
        if (effect.is(setPeerCursors)) {
          return effect.value;
        }
      }
      return value;
    },
  });

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

  function buildDecorations(
    cursors: PeerCursor[],
    docLength: number,
  ): any {
    const widgets: { pos: number; deco: any }[] = [];
    const marks: { from: number; to: number; deco: any }[] = [];

    for (const peer of cursors) {
      const cursorPos = Math.min(Math.max(0, peer.cursor), docLength);

      widgets.push({
        pos: cursorPos,
        deco: Decoration.widget({
          widget: new PeerCursorWidget(peer.name, peer.color),
          side: 1,
        }),
      });

      if (peer.selection) {
        const selFrom = Math.min(Math.max(0, peer.selection[0]), docLength);
        const selTo = Math.min(Math.max(0, peer.selection[1]), docLength);
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

    widgets.sort((a, b) => a.pos - b.pos);
    marks.sort((a, b) => a.from - b.from || a.to - b.to);

    const builder = new RangeSetBuilder();
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
      } else if (mi < marks.length && marks[mi].from === mPos) {
        builder.add(marks[mi].from, marks[mi].to, marks[mi].deco);
        mi++;
      } else {
        builder.add(widgets[wi].pos, widgets[wi].pos, widgets[wi].deco);
        wi++;
      }
    }

    return builder.finish();
  }

  const peerCursorPlugin = ViewPlugin.fromClass(
    class {
      decorations: any;

      constructor(view: any) {
        activeView = view;
        const cursors = view.state.field(peerCursorField);
        this.decorations = buildDecorations(cursors, view.state.doc.length);
      }

      update(update: any) {
        activeView = update.view;
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
      decorations: (plugin: any) => plugin.decorations,
    },
  );

  const rememberView = EditorView.updateListener.of((update: any) => {
    activeView = update.view;
  });

  return [peerCursorField, peerCursorPlugin, rememberView];
}

// -- Runtime Updates --------------------------------------------------------

export function updatePeerCursorsFromJson(json: string): void {
  if (!activeView || !activeSetPeerCursors) return;
  try {
    const cursors: PeerCursor[] = JSON.parse(json);
    activeView.dispatch({
      effects: activeSetPeerCursors.of(cursors),
    });
  } catch {
    // Malformed JSON or a stale view; ignore cursor decorations.
  }
}
