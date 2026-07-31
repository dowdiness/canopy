import { EditorState } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import * as crdt from "../../../_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.js";
import { CM6Adapter } from "../cm6-adapter";
import type { UserIntent, ViewPatch } from "../types";

async function main(): Promise<void> {
  const parent = document.querySelector<HTMLElement>("#editor");
  const result = document.querySelector<HTMLOutputElement>("#result");
  if (!parent || !result) {
    throw new Error("diagnostic harness DOM is incomplete");
  }

  const initialSource = "if x then y";
  const handle = crdt.create_editor("cm6-diagnostic-fix-e2e");
  crdt.set_text(handle, initialSource);
  const state = EditorState.create({
    doc: initialSource,
    extensions: CM6Adapter.extensions(),
  });
  const view = new EditorView({ state, parent });
  const adapter = new CM6Adapter(view);
  const intents: UserIntent[] = [];
  let replayAccepted: boolean | null = null;
  adapter.onIntent((intent) => {
    intents.push(intent);
    if (intent.type !== "ApplyDiagnosticFix") return;
    const before = crdt.get_text(handle);
    const applied = crdt.handle_diagnostic_fix_intent(
      handle,
      intent.snapshot_id,
      intent.diagnostic_id,
      intent.fix_id,
      101,
    );
    if (!applied) return;
    const after = crdt.get_text(handle);
    const patches = JSON.parse(crdt.compute_view_patches_json(handle)) as ViewPatch[];
    adapter.applyPatches([
      { type: "TextChange", from: 0, to: before.length, insert: after },
      ...patches,
    ]);
    replayAccepted = crdt.handle_diagnostic_fix_intent(
      handle,
      intent.snapshot_id,
      intent.diagnostic_id,
      intent.fix_id,
      102,
    );
  });

  const published = JSON.parse(crdt.compute_view_patches_json(handle)) as ViewPatch[];
  adapter.applyPatches(
    published.map((patch): ViewPatch => {
      if (patch.type !== "SetDiagnostics") return patch;
      return {
        ...patch,
        diagnostics: [
        {
          from: 3,
          to: 4,
          severity: "warning",
          message: "range warning",
          code: "test.range",
          snapshot_id: null,
          diagnostic_id: null,
          fixes: [],
        },
          ...patch.diagnostics,
        ],
      };
    }),
  );

  await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
  const rangeVisible = parent.querySelector(".cm-lintRange-warning") !== null;
  const pointVisible = parent.querySelector(".cm-lintPoint-error") !== null;
  result.dataset.result = "markers-ready";
  result.textContent = JSON.stringify({ rangeVisible, pointVisible });

  const harnessWindow = window as typeof window & {
    clearCm6Diagnostics: () => Promise<void>;
    diagnosticFixResult: () => {
      intents: UserIntent[];
      text: string;
      crdtText: string;
      replayAccepted: boolean | null;
    };
  };
  harnessWindow.diagnosticFixResult = () => ({
    intents: [...intents],
    text: view.state.doc.toString(),
    crdtText: crdt.get_text(handle),
    replayAccepted,
  });
  harnessWindow.clearCm6Diagnostics = async () => {
    adapter.applyPatches([{ type: "SetDiagnostics", diagnostics: [] }]);
    await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
    const cleared =
      parent.querySelector(".cm-lintRange-warning") === null &&
      parent.querySelector(".cm-lintPoint-error") === null;
    const passed = rangeVisible && pointVisible && cleared;
    result.dataset.result = passed ? "pass" : "fail";
    result.textContent = JSON.stringify({ rangeVisible, pointVisible, cleared });
    if (!passed) throw new Error(result.textContent);
  };
  window.addEventListener("pagehide", () => crdt.destroy_editor(handle), {
    once: true,
  });
}

void main().catch((error: unknown) => {
  const result = document.querySelector<HTMLOutputElement>("#result");
  if (result) {
    result.dataset.result = "fail";
    result.textContent = error instanceof Error ? error.message : String(error);
  }
  console.error(error);
});
