export interface GenuiFeasibilityFixture {
  readonly caseId: string;
  readonly question: string;
  readonly sourceFormat: string;
  readonly binding: string;
  readonly selectionKey: string;
  readonly fields: readonly string[];
  readonly numericFields: readonly string[];
  readonly taskValue: string | number | boolean | null;
  readonly source: unknown;
}

export const GENUI_FEASIBILITY_FIXTURES: readonly GenuiFeasibilityFixture[];

export function getFeasibilityFixture(caseId: string): GenuiFeasibilityFixture;
export function capabilitiesJsonForFixture(fixture: GenuiFeasibilityFixture): string;
export function normalizedDatasetJsonForFixture(fixture: GenuiFeasibilityFixture): string;
