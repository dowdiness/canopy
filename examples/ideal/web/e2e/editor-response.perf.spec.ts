import { test, expect, type Page } from '@playwright/test';

type ResponseSample = {
  inputToTextChangeMs: number;
  inputToPaintMs: number;
  phases: Record<string, number>;
};

type Stats = {
  p50: number;
  p95: number;
  max: number;
  mean: number;
};

type ResponseSummary = {
  scenario: string;
  sourceChars: number;
  samples: number;
  textChange: Stats;
  paint: Stats;
  phases: Record<string, Stats>;
};

const WARMUP_KEYSTROKES = 5;
const MEASURED_KEYSTROKES = 30;
const P95_PAINT_BUDGET_MS = Number(process.env.EDITOR_RESPONSE_P95_BUDGET_MS ?? 100);
const MAX_PAINT_BUDGET_MS = Number(process.env.EDITOR_RESPONSE_MAX_BUDGET_MS ?? 250);

async function waitForEditor(page: Page) {
  await page.goto(`/#perf-${Date.now()}`);
  await expect(page).toHaveTitle('Canopy Editor');
  await expect(page.getByRole('button', { name: 'Text' })).toBeVisible();
  await page.waitForFunction(() => {
    const el = document.querySelector('canopy-editor') as any;
    return Boolean(el?.shadowRoot?.querySelector('.cm-editor') && (window as any).__canopy_crdt);
  }, { timeout: 10000 });
}

function lambdaSource(definitions: number): string {
  const lines: string[] = [];
  for (let i = 0; i < definitions; i += 1) {
    lines.push(`let v${i} = ${i}`);
  }
  lines.push(`v${definitions - 1}`);
  return lines.join('\n');
}

async function seedEditor(page: Page, source: string) {
  await page.evaluate((text) => {
    const global = window as any;
    const el = document.querySelector('canopy-editor') as any;
    const crdt = global.__canopy_crdt;
    const handle = global.__canopy_crdt_handle;
    if (!el || !crdt || handle == null) {
      throw new Error('Canopy editor is not mounted');
    }

    crdt.set_text(handle, text);
    el.syncAfterExternalChange();
    document.getElementById('canopy-editor-text-changed')?.click();

    const view = el.cmView;
    view.dispatch({
      selection: { anchor: view.state.doc.length },
      scrollIntoView: true,
    });
    view.focus();
  }, source);

  await page.waitForFunction((text) => {
    const el = document.querySelector('canopy-editor') as any;
    const view = el?.cmView;
    return view?.state.doc.toString() === text;
  }, source);
}

async function measureTextInput(page: Page, text: string): Promise<ResponseSample> {
  return page.evaluate((insertText) => new Promise<ResponseSample>((resolve, reject) => {
    const el = document.querySelector('canopy-editor') as any;
    const cmContent = el?.shadowRoot?.querySelector('.cm-content') as HTMLElement | null;
    const view = el?.cmView;
    if (!el || !cmContent || !view) {
      reject(new Error('CodeMirror content is not mounted'));
      return;
    }
    cmContent.focus();
    view.focus();

    let start = 0;
    const timeout = window.setTimeout(() => {
      (window as any).__canopy_perf_current = null;
      cleanup();
      reject(new Error('Timed out waiting for text-changed after text input'));
    }, 5000);
    const cleanup = () => {
      window.clearTimeout(timeout);
      el.removeEventListener('text-changed', onTextChanged);
    };
    const onTextChanged = () => {
      const textChangedAt = performance.now();
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          const perf = (window as any).__canopy_perf_current;
          const phases = { ...(perf?.spans ?? {}) };
          (window as any).__canopy_perf_current = null;
          cleanup();
          resolve({
            inputToTextChangeMs: textChangedAt - start,
            inputToPaintMs: performance.now() - start,
            phases,
          });
        });
      });
    };

    el.addEventListener('text-changed', onTextChanged, { once: true });
    (window as any).__canopy_perf_current = { spans: {} };
    start = performance.now();
    const inserted = document.execCommand('insertText', false, insertText);
    if (!inserted) {
      const pos = view.state.selection.main.head;
      view.dispatch({
        changes: { from: pos, to: pos, insert: insertText },
        selection: { anchor: pos + insertText.length },
      });
    }
  }), text);
}

function stats(values: number[]): Stats {
  const sorted = [...values].sort((a, b) => a - b);
  const at = (q: number) => sorted[Math.min(sorted.length - 1, Math.max(0, Math.ceil(q * sorted.length) - 1))];
  return {
    p50: at(0.50),
    p95: at(0.95),
    max: sorted[sorted.length - 1],
    mean: values.reduce((sum, value) => sum + value, 0) / values.length,
  };
}

function roundStats(s: Stats): Stats {
  return {
    p50: Number(s.p50.toFixed(2)),
    p95: Number(s.p95.toFixed(2)),
    max: Number(s.max.toFixed(2)),
    mean: Number(s.mean.toFixed(2)),
  };
}

function summarize(scenario: string, sourceChars: number, samples: ResponseSample[]): ResponseSummary {
  const phaseNames = new Set<string>();
  for (const sample of samples) {
    for (const phase of Object.keys(sample.phases)) {
      phaseNames.add(phase);
    }
  }
  const phases: Record<string, Stats> = {};
  for (const phase of [...phaseNames].sort()) {
    phases[phase] = roundStats(stats(samples.map((sample) => sample.phases[phase] ?? 0)));
  }
  return {
    scenario,
    sourceChars,
    samples: samples.length,
    textChange: roundStats(stats(samples.map((sample) => sample.inputToTextChangeMs))),
    paint: roundStats(stats(samples.map((sample) => sample.inputToPaintMs))),
    phases,
  };
}

async function runScenario(page: Page, scenario: string, definitions: number): Promise<ResponseSummary> {
  const source = lambdaSource(definitions);
  await seedEditor(page, source);

  for (let i = 0; i < WARMUP_KEYSTROKES; i += 1) {
    await measureTextInput(page, 'a');
  }

  const samples: ResponseSample[] = [];
  for (let i = 0; i < MEASURED_KEYSTROKES; i += 1) {
    samples.push(await measureTextInput(page, 'a'));
  }

  return summarize(scenario, source.length, samples);
}

test.describe('realistic editor response benchmark', () => {
  test('text-mode typing updates CRDT, projection, and browser paint within budget', async ({ page }) => {
    await waitForEditor(page);

    const summaries = [
      await runScenario(page, 'medium text edit', 100),
      await runScenario(page, 'large text edit', 500),
    ];

    for (const summary of summaries) {
      console.log(`[editor-response] ${JSON.stringify(summary)}`);
      console.log(`[editor-response-phase] ${JSON.stringify({
        scenario: summary.scenario,
        sourceChars: summary.sourceChars,
        samples: summary.samples,
        phases: summary.phases,
      })}`);
      expect(summary.paint.p95, `${summary.scenario} p95 paint latency`).toBeLessThan(P95_PAINT_BUDGET_MS);
      expect(summary.paint.max, `${summary.scenario} max paint latency`).toBeLessThan(MAX_PAINT_BUDGET_MS);
    }
  });
});
