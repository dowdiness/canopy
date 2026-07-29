import type {
  ActivityItem,
  NormalizedEntry,
  ResumeProjection,
} from '../core/session';

export interface PilotTimelinePhase {
  readonly id: string;
  readonly index: number;
  readonly items: readonly ActivityItem[];
  readonly recordedKinds: readonly string[];
}

interface OperationReference {
  readonly entryId: string;
  readonly name: string;
}

export interface WorkbenchViewModel {
  readonly conversationItems: readonly ActivityItem[];
  readonly entriesById: ReadonlyMap<string, NormalizedEntry>;
  readonly normalizedRecord: string;
  readonly operationIndex: Readonly<{
    readonly calls: ReadonlyMap<string, OperationReference>;
    readonly results: ReadonlyMap<string, OperationReference>;
  }>;
  readonly operationRelationship: string | undefined;
  readonly phases: readonly PilotTimelinePhase[];
  readonly selectedItem: ActivityItem | undefined;
  readonly selectedItemIndex: number;
  readonly selectedPhase: PilotTimelinePhase | undefined;
  readonly selectedPhaseId: string | undefined;
  readonly selectedRecord: NormalizedEntry | undefined;
}

export function activityKindLabel(item: ActivityItem): string {
  switch (item.kind) {
    case 'human': return 'human input';
    case 'assistant-claim': return 'assistant claim';
    case 'tool-evidence':
      return item.evidenceStatus === 'observed-failure' ? 'tool failure' : 'tool evidence';
    case 'checkpoint': return 'accepted anchor';
    case 'compaction': return 'source summary';
    case 'branch-summary': return 'branch context';
    case 'omitted': return 'omitted';
  }
}

export function normalizedEntryLabel(entry: NormalizedEntry | undefined): string {
  if (entry === undefined) return 'withheld entry';
  switch (entry.kind) {
    case 'message':
      if (entry.role === 'user') return 'user message';
      if (entry.role === 'assistant') return 'assistant message';
      return 'tool result';
    case 'bashExecution': return 'bash execution';
    case 'compaction': return 'conversation summary';
    case 'branchSummary': return 'branch summary';
    case 'checkpoint': return `${entry.anchorKind} checkpoint`;
    case 'omitted': return `omitted ${entry.originalType}`;
  }
}

function buildTimelinePhases(chronology: readonly ActivityItem[]): readonly PilotTimelinePhase[] {
  const grouped: ActivityItem[][] = [];
  let current: ActivityItem[] = [];
  for (const item of chronology) {
    if (item.kind === 'human' && current.length > 0) {
      grouped.push(current);
      current = [];
    }
    current.push(item);
    if (item.kind === 'compaction') {
      grouped.push(current);
      current = [];
    }
  }
  if (current.length > 0) grouped.push(current);
  return grouped.map((items, index) => {
    const first = items[0]!;
    const last = items[items.length - 1]!;
    const recordedKinds = [...new Set(items.map(activityKindLabel))];
    return {
      id: `${first.id}-${last.id}`,
      index,
      items: Object.freeze([...items]),
      recordedKinds: Object.freeze(recordedKinds),
    };
  });
}

function buildOperationIndex(entries: readonly NormalizedEntry[]) {
  const calls = new Map<string, OperationReference>();
  const results = new Map<string, OperationReference>();
  for (const entry of entries) {
    if (entry.kind === 'message' && entry.role === 'assistant') {
      for (const call of entry.toolCalls) {
        calls.set(call.id, { entryId: entry.id, name: call.name });
      }
    }
    if (
      entry.kind === 'message' &&
      entry.role === 'toolResult' &&
      entry.toolCallId !== undefined
    ) {
      results.set(entry.toolCallId, {
        entryId: entry.id,
        name: entry.toolName ?? 'tool',
      });
    }
  }
  return Object.freeze({ calls, results });
}

function operationRelationship(
  selectedRecord: NormalizedEntry | undefined,
  operationIndex: WorkbenchViewModel['operationIndex'],
): string | undefined {
  if (selectedRecord?.kind === 'message' && selectedRecord.role === 'assistant') {
    const linkedResults = selectedRecord.toolCalls
      .map(call => operationIndex.results.get(call.id))
      .filter((result): result is OperationReference => result !== undefined);
    if (selectedRecord.toolCalls.length > 0) {
      return `${selectedRecord.toolCalls.map(call => call.name).join(', ')} requested · ${linkedResults.length} matching result${linkedResults.length === 1 ? '' : 's'} recorded`;
    }
  }
  if (
    selectedRecord?.kind === 'message' &&
    selectedRecord.role === 'toolResult' &&
    selectedRecord.toolCallId !== undefined
  ) {
    const request = operationIndex.calls.get(selectedRecord.toolCallId);
    return request === undefined
      ? 'Tool result recorded; its request is outside the selected path.'
      : `Result for ${request.name} requested by source entry ${request.entryId}`;
  }
  return undefined;
}

export function buildWorkbenchView(
  projection: ResumeProjection,
  entries: readonly NormalizedEntry[],
  selectedEntryId: string,
): WorkbenchViewModel {
  const phases = buildTimelinePhases(projection.chronology);
  const entriesById = new Map(entries.map(entry => [entry.id, entry]));
  const operationIndex = buildOperationIndex(entries);
  const selectedPhaseId = phases.find(phase =>
    phase.items.some(item => item.source.entryId === selectedEntryId),
  )?.id;
  const selectedItemIndex = Math.max(
    0,
    projection.chronology.findIndex(item => item.source.entryId === selectedEntryId),
  );
  const selectedItem = projection.chronology[selectedItemIndex];
  const selectedRecord = selectedItem === undefined
    ? undefined
    : entriesById.get(selectedItem.source.entryId);
  return {
    conversationItems: projection.chronology,
    entriesById,
    normalizedRecord: selectedRecord === undefined
      ? 'This entry was withheld by the bounded import policy.'
      : JSON.stringify(selectedRecord, null, 2),
    operationIndex,
    operationRelationship: operationRelationship(selectedRecord, operationIndex),
    phases,
    selectedItem,
    selectedItemIndex,
    selectedPhase: phases.find(phase => phase.id === selectedPhaseId),
    selectedPhaseId,
    selectedRecord,
  };
}
