import { EditorView as CmView, type ViewUpdate } from "@codemirror/view";
import { EditorState as CmState } from "@codemirror/state";

/** Shared theme for all inline CM6 editors (no gutters, inline display) */
export const inlineTheme = CmView.theme({
  "&": { display: "inline-block", padding: "0 2px" },
  ".cm-content": { padding: "0" },
  ".cm-line": { padding: "0" },
  ".cm-editor": { display: "inline" },
  "&.cm-focused": { outline: "1px solid #66f" },
});

/** Prevent Enter from creating newlines (single-line editor) */
export const singleLineFilter = CmState.transactionFilter.of(tr => {
  if (tr.newDoc.lines > 1) return [];
  return tr;
});

/** Collect CM6 changes into an array for forwarding to bridge */
export function collectChanges(
  update: ViewUpdate,
): { from: number; to: number; insert: string }[] {
  const changes: { from: number; to: number; insert: string }[] = [];
  update.changes.iterChanges((fromA: number, toA: number, _fromB: number, _toB: number, inserted: { toString(): string }) => {
    changes.push({ from: fromA, to: toA, insert: inserted.toString() });
  });
  return changes;
}

/**
 * Create an inline CM6 editor for use inside PM NodeViews.
 * Handles theme, single-line filter, and change forwarding.
 *
 * When running inside Shadow DOM, pass `root` so CM6 injects
 * its styles into the shadow root instead of document.head.
 */
export function createInlineCm(opts: {
  doc: string;
  parent: HTMLElement;
  root?: ShadowRoot | Document;
  onEdit?: (changes: { from: number; to: number; insert: string }[]) => void;
  isUpdating: () => boolean;
}): CmView {
  return new CmView({
    state: CmState.create({
      doc: opts.doc,
      extensions: [
        inlineTheme,
        singleLineFilter,
        CmView.updateListener.of(update => {
          if (opts.isUpdating() || !update.docChanged || !opts.onEdit) return;
          const changes = collectChanges(update);
          if (changes.length > 0) {
            opts.onEdit(changes);
          }
        }),
      ],
    }),
    parent: opts.parent,
    // Inject CM6 styles into Shadow DOM root (not document.head)
    root: opts.root ?? document,
  });
}
