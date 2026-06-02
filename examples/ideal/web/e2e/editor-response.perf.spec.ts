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
  trimmedMean: number;
};

type ResponseSummary = {
  scenario: string;
  sourceChars: number;
  samples: number;
  textChange: Stats;
  paint: Stats;
  phases: Record<string, Stats>;
};

// Read a numeric env override, falling back to `fallback` when unset/empty. A
// malformed value (non-finite, e.g. "80ms" or a stray space) is a
// misconfiguration: fail fast with a clear message rather than silently
// coercing to NaN, which would disable the positive-control injection
// (NaN > 0 is false) or produce a confusing toBeLessThan(NaN) failure.
function numericEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw === '') {
    return fallback;
  }
  const value = Number(raw);
  if (!Number.isFinite(value)) {
    throw new Error(`${name} must be a finite number, got ${JSON.stringify(raw)}`);
  }
  return value;
}

const WARMUP_KEYSTROKES = 5;
// 40 measured keystrokes so a 10% symmetric trim drops 4 samples per end and
// averages the central 32. The bump from 30 firms up the central estimate; it
// does NOT reduce the dominant between-run baseline drift (see #460 analysis).
const MEASURED_KEYSTROKES = 40;
// Drop the top and bottom TRIM_FRACTION of samples before averaging. This makes
// the gate reject the 1-2 transient slow paints per run (GC / CPU-steal on
// shared CI runners) that inflated the old single-run p95 metric, while
// preserving systematic latency shifts — a real regression slows every paint, so
// it survives the trim. See stats().
const TRIM_FRACTION = 0.1;
// Primary gate: 10% trimmed mean of paint latency. Replaces the old single-run
// p95, which was the 2nd-highest of 30 samples and therefore dominated by the
// noisy tail (#460). Local default 100 ms is unchanged from the old local p95
// default — the local trimmed mean is ~80 ms with ~1 ms spread, so 100 stays
// tight without flaking. CI overrides this via benchmark.yml.
const TRIMMED_MEAN_PAINT_BUDGET_MS = numericEnv('EDITOR_RESPONSE_TRIMMED_MEAN_BUDGET_MS', 100);
// Coarse catastrophe backstop on the single worst paint. Worst observed CI max
// is ~133 ms, so 250 never flakes; it only trips on a severe single-paint blowup.
// Intentionally loose — tightening it would reintroduce the single-sample
// flakiness the trimmed-mean gate exists to remove.
const MAX_PAINT_BUDGET_MS = numericEnv('EDITOR_RESPONSE_MAX_BUDGET_MS', 250);
// Positive-control harness (#460 / carried from #459). When set, a synchronous
// busy-wait of this many ms is injected into the MEASURED paint region of every
// keystroke (see measureTextInput), simulating a uniform paint regression. A
// regression shifts all samples equally, so the trim does not remove it and the
// trimmed mean rises by ~this value. Default 0 = off. Validate the detector with
// e.g. EDITOR_RESPONSE_INJECT_PAINT_MS=80 (a ~2x local regression) -> gate FAILS.
const INJECT_PAINT_MS = numericEnv('EDITOR_RESPONSE_INJECT_PAINT_MS', 0);

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
  return page.evaluate(({ insertText, injectPaintMs }) => new Promise<ResponseSample>((resolve, reject) => {
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
          // Positive-control injection: a synchronous busy-wait in the measured
          // paint window simulates a uniform paint regression. Placed after
          // textChangedAt so it affects only inputToPaintMs, not the text-change
          // latency. No-op when injectPaintMs is 0 (the default).
          if (injectPaintMs > 0) {
            const spinUntil = performance.now() + injectPaintMs;
            while (performance.now() < spinUntil) {
              // busy-wait
            }
          }
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
  }), { insertText: text, injectPaintMs: INJECT_PAINT_MS });
}

function mean(values: number[]): number {
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function stats(values: number[]): Stats {
  const sorted = [...values].sort((a, b) => a - b);
  const at = (q: number) => sorted[Math.min(sorted.length - 1, Math.max(0, Math.ceil(q * sorted.length) - 1))];
  // Symmetric trim: drop the lowest and highest `drop` samples, average the
  // rest. `drop` is clamped so at least one sample always survives.
  const drop = Math.min(Math.floor(sorted.length * TRIM_FRACTION), Math.floor((sorted.length - 1) / 2));
  const trimmed = sorted.slice(drop, sorted.length - drop);
  return {
    p50: at(0.50),
    p95: at(0.95),
    max: sorted[sorted.length - 1],
    mean: mean(values),
    trimmedMean: mean(trimmed),
  };
}

function roundStats(s: Stats): Stats {
  return {
    p50: Number(s.p50.toFixed(2)),
    p95: Number(s.p95.toFixed(2)),
    max: Number(s.max.toFixed(2)),
    mean: Number(s.mean.toFixed(2)),
    trimmedMean: Number(s.trimmedMean.toFixed(2)),
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
    // ~90 measureTextInput calls (warmup + measured, both scenarios), plus the
    // optional positive-control busy-wait, can approach Playwright's 30s default
    // on a slow runner or under an injected regression. Give headroom so a real
    // slowdown surfaces as a trimmed-mean assertion failure, not a timeout kill.
    test.setTimeout(60_000);
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
      // Gated metrics: trimmedMean (primary, noise-robust) and max (catastrophe
      // backstop). p50/p95/mean are computed and logged for observability only —
      // do not assert on them without an empirical per-metric baseline.
      expect(
        summary.paint.trimmedMean,
        `${summary.scenario} trimmed-mean paint latency`,
      ).toBeLessThan(TRIMMED_MEAN_PAINT_BUDGET_MS);
      expect(summary.paint.max, `${summary.scenario} max paint latency`).toBeLessThan(MAX_PAINT_BUDGET_MS);
    }
  });
});
