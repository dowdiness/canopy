import { EditorState } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { CM6Adapter } from "../cm6-adapter";

async function main(): Promise<void> {
  const parent = document.querySelector<HTMLElement>("#editor");
  const result = document.querySelector<HTMLOutputElement>("#result");
  if (!parent || !result) {
    throw new Error("diagnostic harness DOM is incomplete");
  }

  const state = EditorState.create({
    doc: "if x then y",
    extensions: CM6Adapter.extensions(),
  });
  const view = new EditorView({ state, parent });
  const adapter = new CM6Adapter(view);

  adapter.applyPatches([
    {
      type: "SetDiagnostics",
      diagnostics: [
        {
          from: 3,
          to: 4,
          severity: "warning",
          message: "range warning",
          code: "test.range",
        },
        {
          from: 11,
          to: 11,
          severity: "error",
          message: "missing else",
          code: null,
        },
      ],
    },
  ]);

  await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
  const rangeVisible = parent.querySelector(".cm-lintRange-warning") !== null;
  const pointVisible = parent.querySelector(".cm-lintPoint-error") !== null;
  result.dataset.result = "markers-ready";
  result.textContent = JSON.stringify({ rangeVisible, pointVisible });

  const harnessWindow = window as typeof window & {
    clearCm6Diagnostics: () => Promise<void>;
  };
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
}

void main();
