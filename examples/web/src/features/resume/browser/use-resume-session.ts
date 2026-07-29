import { useMemo, useReducer } from 'react';
import {
  DEFAULT_LIMITS,
  parsePiSessionJsonl,
  PiSessionFormatError,
  projectResume,
  reducePiSession,
  type ResumeDiagnostic,
  type ResumeProjection,
} from '../core/session';
import {
  initialPilotViewState,
  initialResumeState,
  reducePilotViewState,
  reduceResumeState,
  type PilotSourceSelection,
  type PilotViewState,
  type ResumeState,
} from './resume-state';

export interface ResumeSessionController {
  readonly state: ResumeState;
  readonly pilotState: PilotViewState;
  readonly effectiveLeafId: string | null;
  readonly projection: ResumeProjection | undefined;
  readonly effectivePilotSource: PilotSourceSelection | undefined;
  readonly diagnostics: readonly ResumeDiagnostic[];
  importSessionFile(file: File): Promise<void>;
  revealSource(entryId: string): void;
  revealChatSource(entryId: string, leafId: string): void;
  selectPath(leafId: string | null): void;
  toggleChatSource(entryId: string): void;
  forgetSession(): void;
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} bytes`;
  const units = ['KiB', 'MiB', 'GiB'];
  let value = bytes;
  let unitIndex = -1;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  return `${value.toFixed(1)} ${units[unitIndex]}`;
}

function formatImportError(error: unknown, file: File): ResumeDiagnostic {
  if (error instanceof PiSessionFormatError) {
    const message = (() => {
      switch (error.code) {
        case 'file_too_large':
          return `This session is ${formatBytes(file.size)} (${file.size.toLocaleString()} bytes), above the ${formatBytes(DEFAULT_LIMITS.maxFileBytes)} limit (${DEFAULT_LIMITS.maxFileBytes.toLocaleString()} bytes). Choose a shorter or newer pi session and try again. Nothing was uploaded or saved.`;
        case 'line_too_large':
          return 'One entry in this session is too large to import safely. Choose a shorter session or a session with less captured tool output. Nothing was uploaded or saved.';
        case 'too_many_entries':
          return `This session has more than ${DEFAULT_LIMITS.maxEntries.toLocaleString()} entries. Choose a shorter session and try again. Nothing was uploaded or saved.`;
        case 'unsupported_version':
          return 'This is not a supported pi session v3 file. Choose a v3 .jsonl session snapshot.';
        case 'invalid_json':
          return 'This file is not valid JSONL. Choose a pi session .jsonl snapshot rather than a folder or export in another format.';
        case 'invalid_entry_identity':
        case 'missing_parent':
        case 'missing_reference':
        case 'cycle':
          return 'This session appears incomplete or malformed. Choose another .jsonl snapshot; the file was not modified.';
        default:
          return error.message;
      }
    })();
    return { severity: 'error', code: error.code, message };
  }
  return {
    severity: 'error',
    code: 'import_failed',
    message: error instanceof Error ? error.message : String(error),
  };
}

export function useResumeSession(): ResumeSessionController {
  const [state, dispatch] = useReducer(reduceResumeState, initialResumeState);
  const [pilotState, dispatchPilot] = useReducer(reducePilotViewState, initialPilotViewState);
  const effectiveLeafId = state.selectedLeafId ?? (
    state.sourceMode === 'demo' ? state.session.terminalPaths[0]?.leafId ?? null : null
  );
  const projection = useMemo(
    () => effectiveLeafId === null ? undefined : projectResume(state.session, effectiveLeafId),
    [effectiveLeafId, state.session],
  );
  const defaultItem = projection?.chronology[0];
  const effectivePilotSource: PilotSourceSelection | undefined = pilotState.selectedSource ??
    (defaultItem === undefined ? undefined : { entryId: defaultItem.source.entryId });
  const diagnostics = state.diagnosticOverride ?? projection?.diagnostics ?? state.session.diagnostics;

  const importSessionFile = async (file: File): Promise<void> => {
    dispatchPilot({ type: 'reset' });
    dispatch({ type: 'import-reading', fileName: file.name });
    try {
      if (file.size > DEFAULT_LIMITS.maxFileBytes) {
        throw new PiSessionFormatError('file_too_large', 'The selected file exceeds the file limit.');
      }
      const session = reducePiSession(parsePiSessionJsonl(await file.text()));
      const count = session.diagnostics.length;
      dispatch({
        type: 'import-succeeded', session, fileName: file.name,
        status: { tone: 'success', message: count === 0
          ? `Imported ${file.name}. Select a terminal path to inspect it.`
          : `Imported ${file.name} with ${count} import note${count === 1 ? '' : 's'}.` },
      });
    } catch (error) {
      const diagnostic = formatImportError(error, file);
      dispatch({ type: 'import-failed', diagnostic,
        status: { tone: 'error', message: `Could not import ${file.name}. ${diagnostic.message} The demo transcript remains active.` } });
    }
  };

  const revealSource = (entryId: string): void => {
    if (projection?.chronology.some(item => item.source.entryId === entryId) !== true) return;
    dispatchPilot({ type: 'open-source', entryId });
    window.history.replaceState(null, '', `#source-${entryId}`);
  };

  const revealChatSource = (entryId: string, leafId: string): void => {
    if (projection?.leafId === leafId) { revealSource(entryId); return; }
    if (!state.session.entries.some(entry => entry.id === leafId) ||
        !state.session.entries.some(entry => entry.id === entryId)) return;
    dispatchPilot({ type: 'open-source', entryId });
    dispatch({ type: 'select-leaf', leafId });
    window.history.replaceState(null, '', `#source-${entryId}`);
  };

  const selectPath = (leafId: string | null): void => {
    dispatchPilot({ type: 'reset' });
    dispatch({ type: 'select-leaf', leafId });
  };

  const toggleChatSource = (entryId: string): void => {
    dispatchPilot({ type: 'toggle-chat-source', entryId });
  };

  const forgetSession = (): void => {
    dispatchPilot({ type: 'reset' });
    dispatch({ type: 'forget' });
  };

  return {
    state,
    pilotState,
    effectiveLeafId,
    projection,
    effectivePilotSource,
    diagnostics,
    importSessionFile,
    revealSource,
    revealChatSource,
    selectPath,
    toggleChatSource,
    forgetSession,
  };
}
