import { readFileSync } from 'node:fs';
import { expect, test } from '@playwright/test';
import {
  parsePiSessionJsonl,
  projectResume,
  reducePiSession,
} from '../src/features/resume/core/session';
import { buildWorkbenchView } from '../src/features/resume/browser/workbench-view-model';
const fixtureSource = readFileSync(
  new URL('./fixtures/pi-session-v3.jsonl', import.meta.url),
  'utf8',
);

const session = reducePiSession(parsePiSessionJsonl(fixtureSource));
const projection = projectResume(session, session.terminalPaths[0]!.leafId);

test('partitions chronology at human inputs and compactions', () => {
  const view = buildWorkbenchView(projection, session.entries, projection.chronology[0]!.source.entryId);
  const flattened = view.phases.flatMap(phase => phase.items);

  expect(flattened).toEqual(projection.chronology);
  for (const phase of view.phases.slice(1)) {
    const firstIndex = projection.chronology.indexOf(phase.items[0]!);
    const previous = projection.chronology[firstIndex - 1]!;
    expect(
      phase.items[0]!.kind === 'human' || previous.kind === 'compaction',
    ).toBe(true);
  }
});

test('links selected assistant operations to recorded results', () => {
  const assistant = session.entries.find(entry =>
    entry.kind === 'message' && entry.role === 'assistant' && entry.toolCalls.length > 0,
  );
  expect(assistant).toBeDefined();
  if (assistant === undefined) return;

  const view = buildWorkbenchView(projection, session.entries, assistant.id);
  expect(view.operationRelationship).toContain('requested');
  expect(view.operationRelationship).toContain(assistant.toolCalls[0]!.name);
});

test('falls back to the first chronology item for an absent selection', () => {
  const view = buildWorkbenchView(projection, session.entries, 'missing-entry');

  expect(view.selectedItemIndex).toBe(0);
  expect(view.selectedItem).toEqual(projection.chronology[0]);
});
