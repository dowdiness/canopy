import type { GenuiFeasibilityFixture } from '../../src/features/genui/core/genui-feasibility-fixtures.js';

export interface FrozenGenuiProviderIdentity {
  readonly lookupTag: string;
  readonly modelManifestSha256: string;
  readonly showDetailsSha256: string;
  readonly ollamaVersion: string;
  readonly templateSha256: string;
  readonly parametersSha256: string;
}

export const GENUI_PROVIDER_SETTINGS: {
  readonly stream: false;
  readonly temperature: number;
  readonly numCtx: number;
  readonly numPredict: number;
  readonly keepAlive: string;
  readonly timeoutMs: number;
  readonly slotSeeds: readonly number[];
  readonly maxCandidateBytes: number;
};

export function callOllamaSlot(input: {
  readonly fixture: GenuiFeasibilityFixture;
  readonly slotId: number;
  readonly frozenIdentity: FrozenGenuiProviderIdentity;
}): Promise<Record<string, unknown>>;

export function sha256Hex(value: string | Uint8Array): string;
