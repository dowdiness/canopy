import { timingSafeEqual } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import type { Plugin } from 'vite';

import {
  GENUI_PROVIDER_SETTINGS,
  callOllamaSlot,
  sha256Hex,
} from './src/genui-feasibility-provider.js';
import { GENUI_FEASIBILITY_FIXTURES } from './src/genui-feasibility-fixtures.js';
import { getRecordedFeasibilityCandidate } from './src/genui-recorded-candidates.js';

const REQUEST_LIMIT_BYTES = 1024;
const REQUEST_KEYS = ['caseId', 'runCapability', 'slotId', 'studyId'];

type FrozenIdentity = {
  lookupTag: string;
  modelManifestSha256: string;
  showDetailsSha256: string;
  ollamaVersion: string;
  templateSha256: string;
  parametersSha256: string;
};

type StudyManifest = {
  studyId: string;
  modelIdentity: FrozenIdentity;
  schedule: Array<{ caseId: string; slotId: number }>;
  settings?: unknown;
};

type GateOptions = {
  manifest: StudyManifest;
  runCapability: string;
  fixtures: typeof GENUI_FEASIBILITY_FIXTURES;
  callSlot: (input: {
    fixture: (typeof GENUI_FEASIBILITY_FIXTURES)[number];
    slotId: number;
    frozenIdentity: FrozenIdentity;
  }) => Promise<Record<string, unknown>>;
};

export function createFeasibilityRequestGate(options: GateOptions) {
  const claimedSlots = new Set<string>();
  const fixturesByCase = new Map(options.fixtures.map((fixture) => [fixture.caseId, fixture]));
  const scheduledSlots = new Set(options.manifest.schedule.map(({ caseId, slotId }) => slotKey(caseId, slotId)));

  return {
    async execute(body: unknown) {
      if (!hasExactRequestShape(body)) {
        return { classification: 'request_rejected', message: 'Malformed feasibility study request.' };
      }
      if (body.studyId !== options.manifest.studyId || !capabilitiesEqual(body.runCapability, options.runCapability)) {
        return { classification: 'request_rejected', message: 'Feasibility study request was not authorized.' };
      }
      const fixture = fixturesByCase.get(body.caseId);
      const key = slotKey(body.caseId, body.slotId);
      if (fixture === undefined || !scheduledSlots.has(key)) {
        return { classification: 'request_rejected', message: 'Unknown feasibility study slot.' };
      }
      if (claimedSlots.has(key)) {
        return { classification: 'duplicate_slot', message: 'Feasibility study slot was already claimed.' };
      }

      claimedSlots.add(key);
      return options.callSlot({
        fixture,
        slotId: body.slotId,
        frozenIdentity: options.manifest.modelIdentity,
      });
    },
  };
}

export async function callFakeFeasibilitySlot(input: {
  fixture: (typeof GENUI_FEASIBILITY_FIXTURES)[number];
  slotId: number;
  frozenIdentity: FrozenIdentity;
}): Promise<Record<string, unknown>> {
  if (input.slotId === 2) {
    return {
      classification: 'provider_failure',
      message: 'Deterministic fake provider failure.',
    };
  }
  return {
    classification: 'success',
    candidateJson: input.slotId === 0
      ? JSON.stringify(getRecordedFeasibilityCandidate(input.fixture.caseId))
      : '{}',
    caseId: input.fixture.caseId,
    slotId: input.slotId,
    ...input.frozenIdentity,
  };
}

export function genUiFeasibilityPlugin(): Plugin | false {
  if (process.env.GENUI_FEASIBILITY_LIVE !== '1') return false;

  const manifestPath = process.env.GENUI_FEASIBILITY_MANIFEST;
  const runCapability = process.env.GENUI_FEASIBILITY_RUN_CAPABILITY;
  if (manifestPath === undefined || runCapability === undefined) {
    throw new Error('Live feasibility mode requires a frozen manifest and ephemeral run capability.');
  }
  if (!/^[0-9a-f]{64}$/.test(runCapability)) {
    throw new Error('GENUI_FEASIBILITY_RUN_CAPABILITY must be a 256-bit lowercase hexadecimal value.');
  }

  const manifestBytes = readFileSync(resolve(manifestPath), 'utf8');
  const manifest = parseStudyManifest(manifestBytes);
  const manifestSha256 = sha256Hex(manifestBytes);
  const gate = createFeasibilityRequestGate({
    manifest,
    runCapability,
    fixtures: GENUI_FEASIBILITY_FIXTURES,
    callSlot: process.env.GENUI_FEASIBILITY_FAKE === '1'
      ? (input) => callFakeFeasibilitySlot(input)
      : (input) => callOllamaSlot(input),
  });

  return {
    name: 'genui-feasibility-ollama',
    apply: 'serve',
    configureServer(server) {
      server.middlewares.use('/api/genui-feasibility', async (request, response) => {
        if (request.method !== 'POST') {
          sendJson(response, 405, { classification: 'request_rejected', message: 'Only POST is supported.' });
          return;
        }
        try {
          const result = await gate.execute(await readRequestBody(request));
          const status = statusForClassification(result.classification);
          sendJson(response, status, { ...result, studyId: manifest.studyId, manifestSha256 });
        } catch (error) {
          sendJson(response, 400, {
            classification: 'request_rejected',
            message: error instanceof Error ? error.message : String(error),
          });
        }
      });
    },
  };
}

export function parseStudyManifest(source: string): StudyManifest {
  const value: unknown = JSON.parse(source);
  if (!isRecord(value) || typeof value.studyId !== 'string' || !isRecord(value.modelIdentity) || !Array.isArray(value.schedule)) {
    throw new Error('Invalid feasibility study manifest.');
  }
  const identityKeys = [
    'lookupTag', 'modelManifestSha256', 'showDetailsSha256', 'ollamaVersion',
    'templateSha256', 'parametersSha256',
  ];
  if (identityKeys.some((key) => typeof value.modelIdentity[key] !== 'string')) {
    throw new Error('Feasibility study manifest has an invalid model identity.');
  }
  if (!value.schedule.every((entry) =>
    isRecord(entry) && typeof entry.caseId === 'string' && Number.isInteger(entry.slotId) &&
    entry.slotId >= 0 && entry.slotId < GENUI_PROVIDER_SETTINGS.slotSeeds.length
  )) {
    throw new Error('Feasibility study manifest has an invalid slot schedule.');
  }
  const slotKeys = value.schedule.map((entry) => slotKey(entry.caseId as string, entry.slotId as number));
  if (new Set(slotKeys).size !== slotKeys.length) {
    throw new Error('Feasibility study manifest contains duplicate slots.');
  }
  return value as StudyManifest;
}

async function readRequestBody(request: AsyncIterable<Uint8Array>) {
  const chunks: Uint8Array[] = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.byteLength;
    if (size > REQUEST_LIMIT_BYTES) throw new Error('Request body exceeds the 1 KiB limit.');
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

function sendJson(
  response: { statusCode: number; setHeader(name: string, value: string): void; end(body: string): void },
  status: number,
  body: unknown,
) {
  response.statusCode = status;
  response.setHeader('content-type', 'application/json; charset=utf-8');
  response.setHeader('cache-control', 'no-store');
  response.end(JSON.stringify(body));
}

function hasExactRequestShape(value: unknown): value is {
  studyId: string;
  runCapability: string;
  caseId: string;
  slotId: number;
} {
  if (!isRecord(value) || Object.keys(value).sort().join(',') !== REQUEST_KEYS.join(',')) return false;
  return (
    typeof value.studyId === 'string' &&
    typeof value.runCapability === 'string' &&
    typeof value.caseId === 'string' &&
    Number.isInteger(value.slotId)
  );
}

function capabilitiesEqual(actual: string, expected: string) {
  const actualBytes = Buffer.from(actual);
  const expectedBytes = Buffer.from(expected);
  return actualBytes.length === expectedBytes.length && timingSafeEqual(actualBytes, expectedBytes);
}

function statusForClassification(classification: unknown) {
  if (classification === 'success') return 200;
  if (classification === 'duplicate_slot') return 409;
  if (classification === 'request_rejected') return 400;
  if (classification === 'provider_timeout') return 504;
  return 502;
}

function slotKey(caseId: string, slotId: number) {
  return `${caseId}\u0000${slotId}`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
