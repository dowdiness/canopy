import { test, expect, type Page } from '@playwright/test';
import { dispatchExternalCrdtChanged } from './support/dom-events';

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
    return Boolean(
      document.querySelector('#canopy-text-editor .cm-editor') &&
      (window as any).__canopy_crdt,
    );
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
    const crdt = global.__canopy_crdt;
    const handle = global.__canopy_crdt_handle;
    if (!crdt || handle == null) {
      throw new Error('Canopy editor is not mounted');
    }

    crdt.set_text(handle, text);
  }, source);
  await dispatchExternalCrdtChanged(page);

  await page.waitForFunction((text) => {
    const content = document.querySelector('#canopy-text-editor .cm-content');
    const visible = content?.textContent ?? '';
    const lines = String(text).split('\n');
    return visible.includes(lines[0]) || visible.includes(lines[lines.length - 1]);
  }, source);
  await page.evaluate(() => {
    const content = document.querySelector('#canopy-text-editor .cm-content') as HTMLElement | null;
    content?.focus();
  });
  await page.keyboard.press('Control+End');
}

async function measureTextInput(page: Page, text: string): Promise<ResponseSample> {
  return page.evaluate((insertText) => new Promise<ResponseSample>((resolve, reject) => {
    const global = window as any;
    const cmContent = document.querySelector('#canopy-text-editor .cm-content') as HTMLElement | null;
    const crdt = global.__canopy_crdt;
    const handle = global.__canopy_crdt_handle;
    if (!cmContent || !crdt || handle == null) {
      reject(new Error('CodeMirror content is not mounted'));
      return;
    }
    cmContent.focus();
    const before = crdt.get_text(handle);

    let start = 0;
    let cancelled = false;
    let pollRafId: number | null = null;
    const timeout = window.setTimeout(() => {
      cancelled = true;
      (window as any).__canopy_perf_current = null;
      cleanup();
      reject(new Error('Timed out waiting for CRDT text after text input'));
    }, 5000);
    const cleanup = () => {
      window.clearTimeout(timeout);
      if (pollRafId !== null) {
        window.cancelAnimationFrame(pollRafId);
        pollRafId = null;
      }
    };
    const complete = () => {
      if (cancelled) return;
      cancelled = true;
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
    const poll = () => {
      if (cancelled) return;
      if (crdt.get_text(handle) !== before) {
        complete();
      } else {
        pollRafId = requestAnimationFrame(poll);
      }
    };

    (window as any).__canopy_perf_current = { spans: {} };
    start = performance.now();
    const inserted = document.execCommand('insertText', false, insertText);
    if (!inserted) {
      cancelled = true;
      cleanup();
      reject(new Error('insertText command failed'));
      return;
    }
    requestAnimationFrame(poll);
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
