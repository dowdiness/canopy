import {
  closeSync,
  fsyncSync,
  mkdirSync,
  openSync,
  readFileSync,
  writeFileSync,
  writeSync,
} from 'node:fs';
import { dirname } from 'node:path';
import { test, expect } from '@playwright/test';

import { GENUI_FEASIBILITY_FIXTURES } from '../src/genui-feasibility-fixtures.js';

type FeasibilityResult = {
  classification?: string;
  candidateJson?: string;
  evidence?: unknown;
  rubric?: unknown;
  safe_output_sha256?: string | null;
  session?: unknown;
  provider?: unknown;
};

type FeasibilityBrowserApi = {
  runSlot(input: {
    studyId: string;
    runCapability: string;
    caseId: string;
    slotId: number;
  }): Promise<FeasibilityResult>;
  evaluateSavedCandidate(input: {
    caseId: string;
    candidateJson: string;
  }): Promise<FeasibilityResult>;
  resetSlotSession(): Promise<void>;
};

declare global {
  interface Window {
    __canopyGenUiFeasibilityTest?: FeasibilityBrowserApi;
  }
}

const enabled = process.env.GENUI_FEASIBILITY_LIVE === '1';
const manifestPath = process.env.GENUI_FEASIBILITY_MANIFEST;
const runCapability = process.env.GENUI_FEASIBILITY_RUN_CAPABILITY;
const journalPath = process.env.GENUI_FEASIBILITY_JOURNAL;
const rawOutputPath = process.env.GENUI_FEASIBILITY_RAW_OUTPUT;

function required(name: string, value: string | undefined): string {
  if (value === undefined || value === '') throw new Error(`${name} is required`);
  return value;
}

function appendDurableJsonLine(path: string, value: unknown): void {
  mkdirSync(dirname(path), { recursive: true });
  const descriptor = openSync(path, 'a');
  try {
    writeSync(descriptor, `${JSON.stringify(value)}\n`);
    fsyncSync(descriptor);
  } finally {
    closeSync(descriptor);
  }
}

function writeRawOutput(path: string, value: unknown): void {
  mkdirSync(dirname(path), { recursive: true });
  const descriptor = openSync(path, 'w');
  try {
    writeSync(descriptor, `${JSON.stringify(value, null, 2)}\n`);
    fsyncSync(descriptor);
  } finally {
    closeSync(descriptor);
  }
}

function replayComparable(result: FeasibilityResult): unknown {
  return {
    classification: result.classification ?? null,
    evidence: result.evidence ?? null,
    rubric: result.rubric ?? null,
    safeOutputSha256: result.safe_output_sha256 ?? null,
  };
}

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value as Record<string, unknown>).sort().map((key) =>
      `${JSON.stringify(key)}:${canonicalJson((value as Record<string, unknown>)[key])}`
    ).join(',')}}`;
  }
  return JSON.stringify(value);
}

test('executes the frozen nine-slot feasibility schedule exactly once', async ({ page }) => {
  test.skip(!enabled, 'GENUI_FEASIBILITY_LIVE=1 is required');

  const frozenManifestPath = required('GENUI_FEASIBILITY_MANIFEST', manifestPath);
  const capability = required('GENUI_FEASIBILITY_RUN_CAPABILITY', runCapability);
  const durableJournalPath = required('GENUI_FEASIBILITY_JOURNAL', journalPath);
  const outputPath = required('GENUI_FEASIBILITY_RAW_OUTPUT', rawOutputPath);
  if (!/^[0-9a-f]{64}$/.test(capability)) throw new Error('Run capability must contain exactly 256 bits');

  const manifest = JSON.parse(readFileSync(frozenManifestPath, 'utf8')) as {
    studyId: string;
    schedule: Array<{ caseId: string; slotId: number; seed?: number }>;
  };
  const fixturesByCase = new Map(GENUI_FEASIBILITY_FIXTURES.map((fixture) => [fixture.caseId, fixture]));
  expect(manifest.schedule).toHaveLength(9);
  for (const slot of manifest.schedule) {
    expect(fixturesByCase.has(slot.caseId)).toBe(true);
    expect(slot.slotId).toBeGreaterThanOrEqual(0);
    expect(slot.slotId).toBeLessThan(3);
  }

  await page.goto('/genui.html');
  const rawSlots: Array<Record<string, unknown>> = [];
  try {
    for (const slot of manifest.schedule) {
      appendDurableJsonLine(durableJournalPath, { kind: 'started', ...slot });
      let terminal: Record<string, unknown>;
      try {
        const online = await page.evaluate(async ({ studyId, capability, caseId, slotId }) => {
          const api = window.__canopyGenUiFeasibilityTest;
          if (!api) throw new Error('GenUI feasibility browser test API is unavailable');
          await api.resetSlotSession();
          return api.runSlot({ studyId, runCapability: capability, caseId, slotId });
        }, { studyId: manifest.studyId, capability, caseId: slot.caseId, slotId: slot.slotId });

        let replay: FeasibilityResult | null = null;
        let replayEqual: boolean | null = null;
        if (typeof online.candidateJson === 'string') {
          replay = await page.evaluate(async ({ caseId, candidateJson }) => {
            const api = window.__canopyGenUiFeasibilityTest;
            if (!api) throw new Error('GenUI feasibility browser test API is unavailable');
            return api.evaluateSavedCandidate({ caseId, candidateJson });
          }, { caseId: slot.caseId, candidateJson: online.candidateJson });
          replayEqual = canonicalJson(replayComparable(online)) === canonicalJson(replayComparable(replay));
        }

        terminal = {
          ...online,
          replay,
          replayEqual,
          safeOutputSha256: online.safe_output_sha256 ?? null,
        };
      } catch (error) {
        terminal = {
          classification: 'harness_slot_failure',
          message: error instanceof Error ? error.message : String(error),
          replayEqual: null,
        };
      }
      rawSlots.push({ ...slot, result: terminal });
      appendDurableJsonLine(durableJournalPath, { kind: 'terminal', ...slot, result: terminal });
    }
  } finally {
    writeRawOutput(outputPath, { studyId: manifest.studyId, slots: rawSlots });
  }

  expect(rawSlots).toHaveLength(9);
});
