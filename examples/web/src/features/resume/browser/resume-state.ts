import fixtureSource from '../../../../tests/fixtures/pi-session-v3.jsonl?raw';
import {
  parsePiSessionJsonl,
  reducePiSession,
  type ReducedPiSession,
  type ResumeDiagnostic,
} from '../core/session';
import { PKE_CHAT_SOURCE_LIMIT } from '../protocol/chat';

const demoSession = reducePiSession(parsePiSessionJsonl(fixtureSource));

type SourceMode = 'demo' | 'imported';
type StatusTone = 'idle' | 'success' | 'error';

export interface ImportStatus {
  readonly message: string;
  readonly tone: StatusTone;
}

export interface ResumeState {
  readonly session: ReducedPiSession;
  readonly sourceMode: SourceMode;
  readonly importedFileName?: string;
  readonly selectedLeafId: string | null;
  readonly isImporting: boolean;
  readonly importStatus: ImportStatus;
  readonly diagnosticOverride?: readonly ResumeDiagnostic[];
  readonly fileInputGeneration: number;
}

export type ResumeEvent =
  | { readonly type: 'import-reading'; readonly fileName: string }
  | {
      readonly type: 'import-succeeded';
      readonly session: ReducedPiSession;
      readonly fileName: string;
      readonly status: ImportStatus;
    }
  | { readonly type: 'import-failed'; readonly diagnostic: ResumeDiagnostic; readonly status: ImportStatus }
  | { readonly type: 'select-leaf'; readonly leafId: string | null }
  | { readonly type: 'forget' };

export const initialResumeState: ResumeState = {
  session: demoSession,
  sourceMode: 'demo',
  selectedLeafId: null,
  isImporting: false,
  importStatus: { message: '', tone: 'idle' },
  fileInputGeneration: 0,
};

export function reduceResumeState(state: ResumeState, event: ResumeEvent): ResumeState {
  switch (event.type) {
    case 'import-reading':
      return {
        ...state,
        selectedLeafId: null,
        isImporting: true,
        importStatus: { message: `Reading ${event.fileName} in this tab…`, tone: 'idle' },
        fileInputGeneration: state.fileInputGeneration + 1,
      };
    case 'import-succeeded': {
      return {
        session: event.session,
        sourceMode: 'imported',
        importedFileName: event.fileName,
        selectedLeafId: null,
        isImporting: false,
        importStatus: event.status,
        fileInputGeneration: state.fileInputGeneration,
      };
    }
    case 'import-failed':
      return {
        ...initialResumeState,
        importStatus: event.status,
        diagnosticOverride: [event.diagnostic],
        fileInputGeneration: state.fileInputGeneration + 1,
      };
    case 'select-leaf':
      return {
        ...state,
        selectedLeafId: event.leafId,
        diagnosticOverride: undefined,
      };
    case 'forget':
      return {
        ...initialResumeState,
        importStatus: {
          message: 'Imported session forgotten. The demo transcript is active again.',
          tone: 'idle',
        },
        fileInputGeneration: state.fileInputGeneration + 1,
      };
  }
}

export interface PilotSourceSelection {
  readonly entryId: string;
}

export interface PilotViewState {
  readonly selectedSource?: PilotSourceSelection;
  readonly chatSourceEntryIds: readonly string[];
}

export type PilotViewEvent =
  | { readonly type: 'open-source'; readonly entryId: string }
  | { readonly type: 'toggle-chat-source'; readonly entryId: string }
  | { readonly type: 'reset' };

export const initialPilotViewState: PilotViewState = {
  chatSourceEntryIds: Object.freeze([]),
};

export function reducePilotViewState(
  state: PilotViewState,
  event: PilotViewEvent,
): PilotViewState {
  switch (event.type) {
    case 'open-source':
      return {
        ...state,
        selectedSource: { entryId: event.entryId },
      };
    case 'toggle-chat-source': {
      const includesSource = state.chatSourceEntryIds.includes(event.entryId);
      if (!includesSource && state.chatSourceEntryIds.length >= PKE_CHAT_SOURCE_LIMIT) return state;
      return {
        ...state,
        chatSourceEntryIds: Object.freeze(
          includesSource
            ? state.chatSourceEntryIds.filter(entryId => entryId !== event.entryId)
            : [...state.chatSourceEntryIds, event.entryId],
        ),
      };
    }
    case 'reset':
      return initialPilotViewState;
  }
}
