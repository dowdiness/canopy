import { test, expect } from '@playwright/test';
import {
  createResumeReducer,
  createResumeState,
  reducePilotViewState,
  initialPilotViewState,
  type PilotViewState,
  type ResumeState,
} from '../src/features/resume/browser/resume-reducer';
import { type ReducedPiSession, type ResumeDiagnostic } from '../src/features/resume/core/session';
import { PKE_CHAT_SOURCE_LIMIT } from '../src/features/resume/protocol/chat';

const dummySession: ReducedPiSession = {
  header: { sessionId: 'test', version: 3, timestamp: '2024-01-01T00:00:00Z', cwd: '/' },
  entries: Object.freeze([]),
  terminalPaths: Object.freeze([]),
  diagnostics: Object.freeze([]),
};

const baseline = createResumeState(dummySession);
const reduceResumeState = createResumeReducer(baseline);

test('import-reading sets isImporting and clears selectedLeafId', () => {
  const initial = createResumeState(dummySession);
  const withSelection: ResumeState = { ...initial, selectedLeafId: 'leaf-1' };
  const result = reduceResumeState(withSelection, {
    type: 'import-reading',
    fileName: 'session.jsonl',
  });

  expect(result.selectedLeafId).toBeNull();
  expect(result.isImporting).toBe(true);
  expect(result.importStatus.message).toBe('Reading session.jsonl in this tab\u2026');
  expect(result.importStatus.tone).toBe('idle');
  expect(result.fileInputGeneration).toBe(1);
});

test('select-leaf clears diagnosticOverride', () => {
  const initial = createResumeState(dummySession);
  const withDiagnostic: ResumeState = {
    ...initial,
    diagnosticOverride: [{ severity: 'error', code: 'test', message: 'test error' }],
  };
  const result = reduceResumeState(withDiagnostic, {
    type: 'select-leaf',
    leafId: 'leaf-2',
  });

  expect(result.selectedLeafId).toBe('leaf-2');
  expect(result.diagnosticOverride).toBeUndefined();
});

test('select-leaf with null clears selection and diagnostics', () => {
  const initial = createResumeState(dummySession);
  const withSelection: ResumeState = {
    ...initial,
    selectedLeafId: 'leaf-1',
    diagnosticOverride: [{ severity: 'warning', code: 'warn', message: 'warn msg' }],
  };
  const result = reduceResumeState(withSelection, { type: 'select-leaf', leafId: null });

  expect(result.selectedLeafId).toBeNull();
  expect(result.diagnosticOverride).toBeUndefined();
});

test('forget restores baseline session', () => {
  const initial = createResumeState(dummySession);
  const importedSession: ReducedPiSession = {
    header: { sessionId: 'imported', version: 3, timestamp: '2024-02-01T00:00:00Z', cwd: '/other' },
    entries: Object.freeze([]),
    terminalPaths: Object.freeze([]),
    diagnostics: Object.freeze([]),
  };
  const withImport: ResumeState = {
    ...initial,
    session: importedSession,
    sourceMode: 'imported',
    importedFileName: 'session.jsonl',
    selectedLeafId: 'leaf-1',
    isImporting: false,
    importStatus: { message: 'Imported.', tone: 'success' },
  };
  const result = reduceResumeState(withImport, { type: 'forget' });

  expect(result.session).toBe(dummySession);
  expect(result.session.header.sessionId).toBe('test');
  expect(result.sourceMode).toBe('demo');
  expect(result.importedFileName).toBeUndefined();
  expect(result.selectedLeafId).toBeNull();
  expect(result.isImporting).toBe(false);
  expect(result.importStatus.message).toContain('forgotten');
  expect(result.fileInputGeneration).toBe(1);
});

test('import-failed restores baseline session with diagnostic', () => {
  const initial = createResumeState(dummySession);
  const importedSession: ReducedPiSession = {
    header: { sessionId: 'imported', version: 3, timestamp: '2024-02-01T00:00:00Z', cwd: '/other' },
    entries: Object.freeze([]),
    terminalPaths: Object.freeze([]),
    diagnostics: Object.freeze([]),
  };
  const withImport: ResumeState = {
    ...initial,
    session: importedSession,
    sourceMode: 'imported',
    importedFileName: 'session.jsonl',
    diagnosticOverride: undefined,
  };
  const diagnostic: ResumeDiagnostic = { severity: 'error', code: 'parse_failed', message: 'Bad format' };
  const result = reduceResumeState(withImport, {
    type: 'import-failed',
    diagnostic,
    status: { message: 'Import failed. Demo active.', tone: 'error' },
  });

  expect(result.session).toBe(dummySession);
  expect(result.session.header.sessionId).toBe('test');
  expect(result.sourceMode).toBe('demo');
  expect(result.importedFileName).toBeUndefined();
  expect(result.isImporting).toBe(false);
  expect(result.diagnosticOverride).toEqual([diagnostic]);
  expect(result.importStatus.tone).toBe('error');
  expect(result.fileInputGeneration).toBe(1);
});

test('toggle-chat-source caps at PKE_CHAT_SOURCE_LIMIT', () => {
  const limit = PKE_CHAT_SOURCE_LIMIT;
  let state: PilotViewState = initialPilotViewState;

  for (let i = 0; i < limit; i++) {
    state = reducePilotViewState(state, {
      type: 'toggle-chat-source',
      entryId: `entry-${i}`,
    });
    expect(state.chatSourceEntryIds.length).toBe(i + 1);
  }

  // Exceeding the limit is a no-op
  state = reducePilotViewState(state, {
    type: 'toggle-chat-source',
    entryId: 'overflow',
  });
  expect(state.chatSourceEntryIds.length).toBe(limit);
});

test('toggle-chat-source preserves insertion order', () => {
  let state: PilotViewState = initialPilotViewState;

  state = reducePilotViewState(state, { type: 'toggle-chat-source', entryId: 'a' });
  state = reducePilotViewState(state, { type: 'toggle-chat-source', entryId: 'b' });
  state = reducePilotViewState(state, { type: 'toggle-chat-source', entryId: 'c' });
  expect(state.chatSourceEntryIds).toEqual(['a', 'b', 'c']);

  // Toggling an existing entry removes it
  state = reducePilotViewState(state, { type: 'toggle-chat-source', entryId: 'b' });
  expect(state.chatSourceEntryIds).toEqual(['a', 'c']);

  // Re-toggling appends at the end
  state = reducePilotViewState(state, { type: 'toggle-chat-source', entryId: 'b' });
  expect(state.chatSourceEntryIds).toEqual(['a', 'c', 'b']);
});

test('reset clears pilot view state', () => {
  let state: PilotViewState = {
    selectedSource: { entryId: 'src-1' },
    chatSourceEntryIds: Object.freeze(['a', 'b']),
  };
  state = reducePilotViewState(state, { type: 'reset' });
  expect(state.chatSourceEntryIds).toEqual([]);
  expect(state.selectedSource).toBeUndefined();
});
