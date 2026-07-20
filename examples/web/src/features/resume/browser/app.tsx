import { useChat } from '@ai-sdk/react';
import { DefaultChatTransport, type UIMessage } from 'ai';
import {
  StrictMode,
  useEffect,
  useMemo,
  useReducer,
  useRef,
  useState,
  type ChangeEvent,
  type KeyboardEvent,
  type MouseEvent,
} from 'react';
import { createRoot } from 'react-dom/client';
import fixtureSource from '../../../../tests/fixtures/pi-session-v3.jsonl?raw';
import {
  Conversation,
  ConversationContent,
  ConversationEmptyState,
  ConversationScrollButton,
} from './components/conversation';
import {
  Message,
  MessageContent,
  MessageResponse,
} from './components/message';
import {
  PromptInput,
  PromptInputBody,
  PromptInputFooter,
  PromptInputSubmit,
  PromptInputTextarea,
} from './components/prompt-input';
import {
  Source,
  Sources,
  SourcesContent,
  SourcesTrigger,
} from './components/sources';
import {
  DEFAULT_LIMITS,
  activityTextForDisplay,
  isSensitiveText,
  parsePiSessionJsonl,
  projectResume,
  reducePiSession,
  PiSessionFormatError,
  type ActivityItem,
  type NormalizedEntry,
  type ReducedPiSession,
  type ResumeDiagnostic,
  type ResumeProjection,
} from '../core/session';
import {
  PKE_CHAT_MESSAGE_LIMIT,
  PKE_CHAT_MESSAGE_TEXT_LIMIT,
  PKE_CHAT_MODEL,
  PKE_CHAT_REQUEST_MAX_BYTES,
  PKE_CHAT_SOURCE_LIMIT,
  parsePkeChatStatus,
  pkeChatSourceFromActivity,
  pkeChatTextMessages,
  type PkeChatContext,
  type PkeChatSource,
  type PkeChatStatus,
} from '../protocol/chat';
import './styles.css';

const demoSession = reducePiSession(parsePiSessionJsonl(fixtureSource));

const dateTimeFormat = new Intl.DateTimeFormat(undefined, {
  month: 'short',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});
const workbenchTimeFormat = new Intl.DateTimeFormat(undefined, {
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
});

type SourceMode = 'demo' | 'imported';
type StatusTone = 'idle' | 'success' | 'error';

interface ImportStatus {
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

interface PilotSourceSelection {
  readonly entryId: string;
}

interface PilotViewState {
  readonly selectedSource?: PilotSourceSelection;
  readonly chatSourceEntryIds: readonly string[];
}

type PilotViewEvent =
  | {
      readonly type: 'open-source';
      readonly entryId: string;
    }
  | { readonly type: 'toggle-chat-source'; readonly entryId: string }
  | { readonly type: 'reset' };

const initialPilotViewState: PilotViewState = {
  chatSourceEntryIds: Object.freeze([]),
};

function reducePilotViewState(
  state: PilotViewState,
  event: PilotViewEvent,
): PilotViewState {
  switch (event.type) {
    case 'open-source':
      return {
        ...state,
        selectedSource: {
          entryId: event.entryId,
        },
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

function formatTimestamp(value: string): string {
  return dateTimeFormat.format(new Date(value));
}

function formatWorkbenchTime(value: string): string {
  return workbenchTimeFormat.format(new Date(value));
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

function activityKindLabel(item: ActivityItem): string {
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

function PilotSessionToolbar({
  state,
  pathLength,
  selectedLeafId,
  onFile,
  onSelectPath,
  onForget,
}: {
  readonly state: ResumeState;
  readonly pathLength: number;
  readonly selectedLeafId: string | null;
  readonly onFile: (file: File) => void;
  readonly onSelectPath: (leafId: string | null) => void;
  readonly onForget: () => void;
}) {
  const pathParts = state.session.header.cwd.split('/').filter(Boolean);
  const projectName = pathParts[pathParts.length - 1] ?? 'work session';
  const handleChange = (event: ChangeEvent<HTMLInputElement>): void => {
    const file = event.currentTarget.files?.[0];
    if (file !== undefined) onFile(file);
  };
  const sourceStatus = state.isImporting
    ? state.importStatus.message
    : state.importStatus.tone === 'error'
      ? state.importStatus.message
      : state.sourceMode === 'imported'
        ? `${state.importedFileName ?? 'Imported session'}${
            state.session.diagnostics.length === 0
              ? ''
              : ` · ${state.session.diagnostics.length} import notes`
          }`
        : state.importStatus.message === ''
          ? 'Example'
          : 'Example restored';
  return (
    <header className="pilot-session-toolbar" aria-label="Session controls">
      <h1 id="pilot-view-title" className="visually-hidden">{projectName} session</h1>
      <div className="pilot-file-control">
        <label htmlFor="session-file">Open session</label>
        <input
          key={state.fileInputGeneration}
          className="file-input"
          id="session-file"
          type="file"
          aria-label="Open session file"
          accept=".jsonl,application/json,text/plain"
          disabled={state.isImporting}
          onChange={handleChange}
        />
      </div>
      <div className="pilot-path-control">
        <label className="visually-hidden" htmlFor="branch-select">Session path</label>
        <select
          id="branch-select"
          aria-label="Session path"
          disabled={state.isImporting}
          value={selectedLeafId ?? ''}
          onChange={event => onSelectPath(event.currentTarget.value || null)}
        >
          <option value="">Choose a path…</option>
          {state.session.terminalPaths.map((path, index) => (
            <option key={path.leafId} value={path.leafId}>
              Path {index + 1} · {path.entryIds.length} recorded moments
            </option>
          ))}
        </select>
      </div>
      <p
        className="pilot-session-status"
        data-tone={state.importStatus.tone}
        role="status"
        aria-live="polite"
      >
        {sourceStatus} <span aria-hidden="true">·</span> Local, unsaved
      </p>
      <details className="pilot-session-details">
        <summary>Details</summary>
        <dl>
          <div><dt>Project</dt><dd>{projectName}</dd></div>
          <div><dt>Started</dt><dd>{formatTimestamp(state.session.header.timestamp)}</dd></div>
          <div><dt>Working directory</dt><dd>{state.session.header.cwd}</dd></div>
          <div><dt>Source</dt><dd>{state.importedFileName ?? 'Built-in example'}</dd></div>
          <div><dt>Selected path</dt><dd>{pathLength} recorded entries</dd></div>
        </dl>
      </details>
      {state.sourceMode === 'imported' ? (
        <button
          className="pilot-forget-session"
          type="button"
          disabled={state.isImporting}
          aria-label="Forget session"
          onClick={onForget}
        >
          Forget
        </button>
      ) : null}
    </header>
  );
}

function PilotEmptyWorkspace({ state }: { readonly state: ResumeState }) {
  return (
      <section className="pilot-workbench pilot-workbench-empty" aria-label="Session workbench">
        <div className="pilot-workbench-grid">
          <section className="pilot-workbench-panel pilot-timeline" data-pane="timeline">
            <header className="pilot-panel-heading">
              <div><h3>Timeline</h3></div>
              <p>0 recorded moments</p>
            </header>
          </section>
          <section className="pilot-workbench-panel pilot-conversation" data-pane="conversation">
            <header className="pilot-panel-heading">
              <div><h3>Conversation</h3></div>
              <p>No path selected</p>
            </header>
          </section>
          <section className="pilot-workbench-panel pilot-evidence" data-pane="evidence">
            <header className="pilot-panel-heading">
              <div><h3>Evidence</h3></div>
              <p>No moment selected</p>
            </header>
          </section>
        </div>
      </section>
  );
}

interface PilotTimelinePhase {
  readonly id: string;
  readonly index: number;
  readonly items: readonly ActivityItem[];
  readonly recordedKinds: readonly string[];
}

type PilotWorkbenchPane = 'timeline' | 'conversation' | 'evidence';
type PilotEvidenceMode = 'readable' | 'normalized';
type PilotInspectorMode = 'discuss' | 'evidence';

function buildPilotTimelinePhases(
  chronology: readonly ActivityItem[],
): readonly PilotTimelinePhase[] {
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

function normalizedEntryLabel(entry: NormalizedEntry | undefined): string {
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

type PilotChatRole = 'user' | 'assistant' | 'tool' | 'checkpoint' | 'system';

function pilotChatRole(item: ActivityItem, entry: NormalizedEntry | undefined): PilotChatRole {
  if (entry?.kind === 'message') {
    if (entry.role === 'user') return 'user';
    if (entry.role === 'assistant') return 'assistant';
    return 'tool';
  }
  if (entry?.kind === 'bashExecution' || item.kind === 'tool-evidence') return 'tool';
  if (entry?.kind === 'checkpoint' || item.kind === 'checkpoint') return 'checkpoint';
  return 'system';
}

function conversationSpeaker(role: PilotChatRole): string {
  switch (role) {
    case 'user': return 'You';
    case 'assistant': return 'Assistant';
    case 'tool': return 'Tool';
    case 'checkpoint': return 'Accepted checkpoint';
    case 'system': return 'Session event';
  }
}

function chatAuthorityLabel(item: ActivityItem, role: PilotChatRole): string {
  switch (role) {
    case 'user': return 'Recorded user message';
    case 'assistant': return 'Unverified assistant text';
    case 'tool': return item.evidenceStatus === 'observed-failure'
      ? 'Observed failure'
      : 'Observed result';
    case 'checkpoint': return item.anchorKind === undefined
      ? 'Accepted anchor'
      : `Accepted ${item.anchorKind}`;
    case 'system': return activityKindLabel(item);
  }
}

interface PilotChatTurnContext {
  readonly context: PkeChatContext;
  readonly sources: readonly PkeChatSource[];
}

const NO_HISTORY_CHAT_CONTEXT: PilotChatTurnContext = Object.freeze({
  context: Object.freeze({ scope: 'none' }),
  sources: Object.freeze([]),
});

const PKE_CHAT_CITATION_HREF_PREFIX = '#canopy-source-';

function sourceLinkedChatMarkdown(
  text: string,
  turnContext: PilotChatTurnContext,
): string {
  if (turnContext.context.scope === 'none') return text;
  const sourceEntryIds = new Set(turnContext.sources.map(source => source.source.entryId));
  return text.replace(
    /\[source:([A-Za-z0-9._:@/-]+)\]/g,
    (citation, entryId: string) => sourceEntryIds.has(entryId)
      ? `[\\[source:${entryId}\\]](${PKE_CHAT_CITATION_HREF_PREFIX}${encodeURIComponent(entryId)})`
      : citation,
  );
}

function chatCitationEntryId(
  href: string | undefined,
  sourceEntryIds: ReadonlySet<string>,
): string | undefined {
  if (href === undefined || !href.startsWith(PKE_CHAT_CITATION_HREF_PREFIX)) return undefined;
  try {
    const entryId = decodeURIComponent(href.slice(PKE_CHAT_CITATION_HREF_PREFIX.length));
    return sourceEntryIds.has(entryId) ? entryId : undefined;
  } catch {
    return undefined;
  }
}

function PilotSourceChat({
  projection,
  selectedSource,
  sourceEntryIds,
  onToggleSource,
  onOpenSource,
}: {
  readonly projection: ResumeProjection;
  readonly selectedSource: PilotSourceSelection;
  readonly sourceEntryIds: readonly string[];
  readonly onToggleSource: (entryId: string) => void;
  readonly onOpenSource: (entryId: string, leafId: string) => void;
}) {
  const [draft, setDraft] = useState('');
  const [draftMessageId, setDraftMessageId] = useState(() => crypto.randomUUID());
  const [contextScope, setContextScope] = useState<PkeChatContext['scope']>('none');
  const [contextByMessageId, setContextByMessageId] = useState<
    ReadonlyMap<string, PilotChatTurnContext>
  >(() => new Map());
  const [showPayload, setShowPayload] = useState(false);
  const [relayStatus, setRelayStatus] = useState<PkeChatStatus>();
  const [relayStatusError, setRelayStatusError] = useState<string>();
  const selectedSourceItems = useMemo(
    () => sourceEntryIds.flatMap(entryId => {
      const item = projection.chronology.find(candidate => candidate.source.entryId === entryId);
      return item === undefined ? [] : [item];
    }),
    [projection.chronology, sourceEntryIds],
  );
  useEffect(() => {
    if (contextScope === 'selected' && selectedSourceItems.length === 0) {
      setContextScope('none');
    }
  }, [contextScope, selectedSourceItems.length]);
  const sourceItems = contextScope === 'path'
    ? projection.chronology
    : contextScope === 'selected'
      ? selectedSourceItems
      : [];
  const sourcePayload = useMemo(
    () => Object.freeze(sourceItems.map(pkeChatSourceFromActivity)),
    [sourceItems],
  );
  const sensitiveSourceCount = useMemo(
    () => sourcePayload.filter(source => isSensitiveText(source.text)).length,
    [sourcePayload],
  );
  const currentContext = useMemo<PkeChatContext>(
    () => contextScope === 'none'
      ? Object.freeze({ scope: 'none' })
      : Object.freeze({
          scope: contextScope,
          sessionId: projection.sessionId,
          leafId: projection.leafId,
        }),
    [contextScope, projection.leafId, projection.sessionId],
  );
  const outboundContextRef = useRef<PkeChatContext>(currentContext);
  const outboundSourcesRef = useRef<readonly PkeChatSource[]>(sourcePayload);
  const transport = useMemo(
    () => new DefaultChatTransport<UIMessage>({
      api: '/api/pi-resume-chat',
      prepareSendMessagesRequest: ({ messages }) => ({
        body: {
          messages: pkeChatTextMessages(messages),
          context: outboundContextRef.current,
          sources: outboundSourcesRef.current,
        },
      }),
    }),
    [],
  );
  const {
    messages,
    setMessages,
    sendMessage,
    status,
    stop,
    error,
    clearError,
  } = useChat<UIMessage>({
    id: `pke-chat:${projection.sessionId}`,
    transport,
  });
  const restoreUnansweredUserMessage = (): void => {
    const trailingMessage = messages[messages.length - 1];
    if (trailingMessage?.role !== 'user') return;
    const text = trailingMessage.parts
      .filter(part => part.type === 'text')
      .map(part => part.text)
      .join('');
    setMessages(messages.slice(0, -1));
    setContextByMessageId(current => {
      if (!current.has(trailingMessage.id)) return current;
      const next = new Map(current);
      next.delete(trailingMessage.id);
      return next;
    });
    setDraft(current => current.trim().length === 0 ? text : current);
  };
  const stopRef = useRef(stop);
  stopRef.current = stop;
  useEffect(() => () => {
    void stopRef.current();
  }, []);
  useEffect(() => {
    if (error === undefined) return;
    const trailingMessage = messages[messages.length - 1];
    if (trailingMessage?.role !== 'user') return;
    const text = trailingMessage.parts
      .filter(part => part.type === 'text')
      .map(part => part.text)
      .join('');
    setMessages(messages.slice(0, -1));
    setContextByMessageId(current => {
      if (!current.has(trailingMessage.id)) return current;
      const next = new Map(current);
      next.delete(trailingMessage.id);
      return next;
    });
    setDraft(current => current.trim().length === 0 ? text : current);
  }, [error, messages, setMessages]);
  useEffect(() => {
    const controller = new AbortController();
    void fetch('/api/pi-resume-chat/status', { signal: controller.signal })
      .then(async response => {
        if (!response.ok) throw new Error('Chat relay status is unavailable.');
        const value = parsePkeChatStatus(await response.json());
        setRelayStatus(value);
        setRelayStatusError(undefined);
      })
      .catch(cause => {
        if (cause instanceof DOMException && cause.name === 'AbortError') return;
        setRelayStatusError(cause instanceof Error ? cause.message : String(cause));
      });
    return () => controller.abort();
  }, []);

  const renderedMessages = useMemo(() => {
    let turnContext = NO_HISTORY_CHAT_CONTEXT;
    return messages.map(message => {
      if (message.role === 'user') {
        turnContext = contextByMessageId.get(message.id) ?? NO_HISTORY_CHAT_CONTEXT;
      }
      return Object.freeze({ message, turnContext });
    });
  }, [contextByMessageId, messages]);
  const pendingMessage = useMemo<UIMessage | undefined>(() => {
    const text = draft.trim();
    return text.length === 0
      ? undefined
      : {
          id: draftMessageId,
          role: 'user',
          parts: [{ type: 'text', text }],
        };
  }, [draft, draftMessageId]);
  const outboundPreview = pendingMessage === undefined
    ? undefined
    : {
        messages: pkeChatTextMessages([...messages, pendingMessage]),
        context: currentContext,
        sources: sourcePayload,
      };
  const outboundBytes = outboundPreview === undefined
    ? 0
    : new TextEncoder().encode(JSON.stringify(outboundPreview)).byteLength;
  const selectedSourceIncluded = sourceEntryIds.includes(selectedSource.entryId);
  const sourceLimitReached = sourceEntryIds.length >= PKE_CHAT_SOURCE_LIMIT;
  const running = status === 'submitted' || status === 'streaming';
  const relayAvailable = relayStatus?.available === true;
  const requestTooLarge = outboundBytes > PKE_CHAT_REQUEST_MAX_BYTES;
  const messageLimitReached = messages.length >= PKE_CHAT_MESSAGE_LIMIT;
  const canSend = relayAvailable && pendingMessage !== undefined &&
    !requestTooLarge && !messageLimitReached;
  const providerLabel = relayStatus === undefined
    ? 'Checking local relay…'
    : relayStatus.provider === 'fake'
      ? 'Test model · local relay'
      : 'DeepSeek V4 Flash · local relay';

  return (
    <section className="pilot-source-chat" aria-labelledby="pilot-source-chat-title">
      <header>
        <div>
          <span className="kicker">Independent chat</span>
          <h4 id="pilot-source-chat-title">Chat</h4>
        </div>
        <strong role="status" aria-live="polite">{providerLabel}</strong>
      </header>
      <div className="pilot-chat-scope" role="group" aria-label="Context for the next message">
        <button
          type="button"
          aria-pressed={contextScope === 'none'}
          onClick={() => setContextScope('none')}
        >
          No history
        </button>
        <button
          type="button"
          aria-pressed={contextScope === 'selected'}
          disabled={selectedSourceItems.length === 0}
          onClick={() => setContextScope('selected')}
        >
          Selected · {selectedSourceItems.length}
        </button>
        <button
          type="button"
          aria-pressed={contextScope === 'path'}
          onClick={() => setContextScope('path')}
        >
          Current path · {projection.chronology.length}
        </button>
      </div>
      <button
        className="pilot-chat-source-toggle"
        type="button"
        aria-pressed={selectedSourceIncluded}
        disabled={!selectedSourceIncluded && sourceLimitReached}
        onClick={() => {
          onToggleSource(selectedSource.entryId);
          if (!selectedSourceIncluded) setContextScope('selected');
        }}
      >
        {selectedSourceIncluded ? 'Remove current moment' : 'Add current moment'}
      </button>
      {contextScope === 'none' ? (
        <p className="pilot-chat-source-empty">
          No activity history will be sent with the next message.
        </p>
      ) : (
        <Sources className="pilot-chat-context" open={messages.length === 0}>
          <SourcesTrigger count={sourceItems.length}>
            Next message context · {contextScope === 'path' ? 'current path' : 'selected'} ·{' '}
            {sourceItems.length} exact source{sourceItems.length === 1 ? '' : 's'}
          </SourcesTrigger>
          <SourcesContent>
            {sourceItems.slice(0, 12).map(item => (
              <article key={item.source.entryId}>
                <div className="pilot-chat-context-heading">
                  <Source onClick={() => onOpenSource(item.source.entryId, projection.leafId)}>
                    source {item.source.entryId} · {item.title}
                  </Source>
                  {contextScope !== 'selected' ? null : (
                    <button
                      type="button"
                      aria-label={`Remove ${item.title} from chat context`}
                      onClick={() => onToggleSource(item.source.entryId)}
                    >
                      Remove
                    </button>
                  )}
                </div>
                <p>{activityTextForDisplay(item)}</p>
                <small>
                  session {item.source.sessionId} · entry {item.source.entryId}
                  {item.source.fragmentIds === undefined
                    ? ''
                    : ` · fragments ${item.source.fragmentIds.join(', ')}`}
                  {' · '}{item.origin.kind} · {item.derivation.kind}
                </small>
              </article>
            ))}
            {sourceItems.length <= 12 ? null : (
              <small>{sourceItems.length - 12} additional exact sources are included in the payload.</small>
            )}
          </SourcesContent>
        </Sources>
      )}
      {sensitiveSourceCount === 0 ? null : (
        <p className="pilot-chat-sensitive-warning" role="status">
          {sensitiveSourceCount} attached excerpt{sensitiveSourceCount === 1 ? '' : 's'} match{' '}
          a potential sensitive-content pattern. They remain visible and will be sent because
          this context was explicitly attached.
        </p>
      )}
      {outboundPreview === undefined ? null : (
        <details
          className="pilot-chat-payload"
          onToggle={event => setShowPayload(event.currentTarget.open)}
        >
          <summary>
            Outbound request preview · {(outboundBytes / 1024).toFixed(1)} KiB
          </summary>
          {showPayload ? <pre>{JSON.stringify(outboundPreview, null, 2)}</pre> : null}
        </details>
      )}
      <Conversation className="pilot-ai-conversation">
        <ConversationContent>
          {messages.length === 0 ? (
            <ConversationEmptyState title="Ask anything." />
          ) : renderedMessages.map(({ message, turnContext }) => {
            const text = message.parts
              .filter(part => part.type === 'text')
              .map(part => part.text)
              .join('');
            const contextLabel = turnContext.context.scope === 'none'
              ? 'No history attached'
              : turnContext.context.scope === 'path'
                ? `Current path · ${turnContext.sources.length} sources`
                : `Selected · ${turnContext.sources.length} sources`;
            const citationSourceEntryIds = new Set(
              turnContext.sources.map(source => source.source.entryId),
            );
            const citationLeafId = turnContext.context.scope === 'none'
              ? undefined
              : turnContext.context.leafId;
            return (
              <Message
                from={message.role}
                data-origin={message.role === 'assistant' ? 'canopy-system' : 'person-authored'}
                data-derivation={message.role === 'assistant' ? 'model-inference' : 'recorded'}
                data-model={message.role === 'assistant' ? (relayStatus?.model ?? PKE_CHAT_MODEL) : undefined}
                key={message.id}
              >
                <span className="visually-hidden">
                  {message.role === 'assistant'
                    ? 'Model suggestion. Attached history, when present, is exact normalized evidence.'
                    : 'Person-authored chat message.'}
                </span>
                <MessageContent>
                  {message.role === 'assistant' ? (
                    <MessageResponse
                      mode={running && messages[messages.length - 1]?.id === message.id
                        ? 'streaming'
                        : 'static'}
                      components={{
                        a: ({ children, href }) => {
                          const entryId = chatCitationEntryId(href, citationSourceEntryIds);
                          if (entryId !== undefined && citationLeafId !== undefined) {
                            return (
                              <Source
                                aria-label={`Open cited source ${entryId}`}
                                className="ai-inline-citation"
                                onClick={() => onOpenSource(entryId, citationLeafId)}
                              >
                                {children}
                              </Source>
                            );
                          }
                          if (
                            href !== undefined &&
                            (href.startsWith('https://') || href.startsWith('http://'))
                          ) {
                            return (
                              <a href={href} rel="noreferrer noopener" target="_blank">
                                {children}
                              </a>
                            );
                          }
                          return <span>{children}</span>;
                        },
                      }}
                    >
                      {sourceLinkedChatMarkdown(text, turnContext)}
                    </MessageResponse>
                  ) : (
                    <div className="ai-message-response">{text}</div>
                  )}
                </MessageContent>
                {message.role === 'user' ? (
                  <small className="pilot-chat-turn-context">{contextLabel}</small>
                ) : turnContext.sources.length === 0 || turnContext.context.scope === 'none' ? null : (
                  <Sources>
                    <SourcesTrigger count={turnContext.sources.length}>{contextLabel}</SourcesTrigger>
                    <SourcesContent>
                      {turnContext.sources.slice(0, 12).map(source => (
                        <Source
                          aria-label={`Open chat source ${source.source.entryId}`}
                          key={source.source.entryId}
                          onClick={() => onOpenSource(
                            source.source.entryId,
                            turnContext.context.scope === 'none'
                              ? projection.leafId
                              : turnContext.context.leafId,
                          )}
                        >
                          source {source.source.entryId} · {source.title}
                        </Source>
                      ))}
                      {turnContext.sources.length <= 12 ? null : (
                        <small>{turnContext.sources.length - 12} additional sources were attached.</small>
                      )}
                    </SourcesContent>
                  </Sources>
                )}
              </Message>
            );
          })}
        </ConversationContent>
        <ConversationScrollButton />
      </Conversation>
      {relayStatus?.available === false ? (
        <p className="pilot-chat-unavailable" role="status">
          Set DEEPSEEK_API_KEY and restart the local server to send messages.
        </p>
      ) : null}
      {relayStatusError === undefined ? null : (
        <p className="pilot-chat-error" role="alert">{relayStatusError}</p>
      )}
      {requestTooLarge ? (
        <p className="pilot-chat-error" role="alert">
          This exact request is {(outboundBytes / 1024 / 1024).toFixed(2)} MiB. The 4 MiB relay limit
          prevents silently truncating the attached path.
        </p>
      ) : null}
      {messageLimitReached ? (
        <p className="pilot-chat-error" role="alert">
          This tab conversation reached the {PKE_CHAT_MESSAGE_LIMIT}-message limit.
        </p>
      ) : null}
      {error === undefined ? null : (
        <p className="pilot-chat-error" role="alert">
          {error.message}
          <button type="button" onClick={clearError}>Dismiss</button>
        </p>
      )}
      <PromptInput
        onSubmit={event => {
          event.preventDefault();
          if (running) {
            void stop();
            restoreUnansweredUserMessage();
            return;
          }
          if (!canSend || pendingMessage === undefined) return;
          const turnContext: PilotChatTurnContext = Object.freeze({
            context: currentContext,
            sources: sourcePayload,
          });
          outboundContextRef.current = currentContext;
          outboundSourcesRef.current = sourcePayload;
          setContextByMessageId(current => {
            const next = new Map(current);
            next.set(pendingMessage.id, turnContext);
            return next;
          });
          setDraft('');
          setDraftMessageId(crypto.randomUUID());
          setShowPayload(false);
          void sendMessage(pendingMessage);
        }}
      >
        <PromptInputBody>
          <PromptInputTextarea
            aria-label="Chat message"
            disabled={!relayAvailable || running || messageLimitReached}
            maxLength={PKE_CHAT_MESSAGE_TEXT_LIMIT}
            placeholder="Ask anything…"
            value={draft}
            onChange={event => setDraft(event.currentTarget.value)}
            onKeyDown={event => {
              if (event.key !== 'Enter' || event.shiftKey || event.nativeEvent.isComposing) return;
              event.preventDefault();
              event.currentTarget.form?.requestSubmit();
            }}
          />
        </PromptInputBody>
        <PromptInputFooter>
          <span>
            {contextScope === 'none'
              ? 'Message only · no activity history attached'
              : `Message + ${sourcePayload.length} exact sources`}
            {' · '}DeepSeek · tab memory only
          </span>
          <PromptInputSubmit
            disabled={!running && !canSend}
            status={status}
          />
        </PromptInputFooter>
      </PromptInput>
    </section>
  );
}

function PilotUnderstandingWorkbench({
  projection,
  entries,
  selectedSource,
  chatInstanceId,
  chatSourceEntryIds,
  onSelectEntry,
  onSelectChatSource,
  onToggleChatSource,
}: {
  readonly projection: ResumeProjection;
  readonly entries: readonly NormalizedEntry[];
  readonly selectedSource: PilotSourceSelection;
  readonly chatInstanceId: string;
  readonly chatSourceEntryIds: readonly string[];
  readonly onSelectEntry: (entryId: string) => void;
  readonly onSelectChatSource: (entryId: string, leafId: string) => void;
  readonly onToggleChatSource: (entryId: string) => void;
}) {
  const phases = useMemo(
    () => buildPilotTimelinePhases(projection.chronology),
    [projection.chronology],
  );
  const entriesById = useMemo(
    () => new Map(entries.map(entry => [entry.id, entry])),
    [entries],
  );
  const operationIndex = useMemo(() => {
    const calls = new Map<string, { readonly entryId: string; readonly name: string }>();
    const results = new Map<string, { readonly entryId: string; readonly name: string }>();
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
    return { calls, results };
  }, [entries]);
  const selectedPhaseId = phases.find(phase =>
    phase.items.some(item => item.source.entryId === selectedSource.entryId),
  )?.id;
  const [expandedPhaseIds, setExpandedPhaseIds] = useState<ReadonlySet<string>>(
    () => new Set(selectedPhaseId === undefined ? [] : [selectedPhaseId]),
  );
  useEffect(() => {
    if (selectedPhaseId === undefined) return;
    setExpandedPhaseIds(current =>
      current.has(selectedPhaseId) ? current : new Set([...current, selectedPhaseId]),
    );
  }, [selectedPhaseId]);
  const [activePane, setActivePane] = useState<PilotWorkbenchPane>('conversation');
  const previousSelectedSourceRef = useRef(selectedSource.entryId);
  useEffect(() => {
    const sourceChanged = previousSelectedSourceRef.current !== selectedSource.entryId;
    previousSelectedSourceRef.current = selectedSource.entryId;
  }, [selectedSource.entryId]);
  const conversationPanelRef = useRef<HTMLElement | null>(null);
  const selectedConversationRef = useRef<HTMLLIElement | null>(null);
  const revealConversationSelectionRef = useRef(false);
  const [inspectorMode, setInspectorMode] = useState<PilotInspectorMode>('discuss');
  const [evidenceMode, setEvidenceMode] = useState<PilotEvidenceMode>('readable');
  const selectedItemIndex = Math.max(
    0,
    projection.chronology.findIndex(item => item.source.entryId === selectedSource.entryId),
  );
  const selectedItem = projection.chronology[selectedItemIndex];
  const selectedRecord = selectedItem === undefined
    ? undefined
    : entriesById.get(selectedItem.source.entryId);
  const selectedPhase = phases.find(phase => phase.id === selectedPhaseId);
  const conversationItems = projection.chronology;
  const normalizedRecord = selectedRecord === undefined
    ? 'This entry was withheld by the bounded import policy.'
    : JSON.stringify(selectedRecord, null, 2);
  let operationRelationship: string | undefined;
  if (selectedRecord?.kind === 'message' && selectedRecord.role === 'assistant') {
    const linkedResults = selectedRecord.toolCalls
      .map(call => operationIndex.results.get(call.id))
      .filter((result): result is { readonly entryId: string; readonly name: string } =>
        result !== undefined,
      );
    if (selectedRecord.toolCalls.length > 0) {
      operationRelationship = `${selectedRecord.toolCalls.map(call => call.name).join(', ')} requested · ${linkedResults.length} matching result${linkedResults.length === 1 ? '' : 's'} recorded`;
    }
  } else if (
    selectedRecord?.kind === 'message' &&
    selectedRecord.role === 'toolResult' &&
    selectedRecord.toolCallId !== undefined
  ) {
    const request = operationIndex.calls.get(selectedRecord.toolCallId);
    operationRelationship = request === undefined
      ? 'Tool result recorded; its request is outside the selected path.'
      : `Result for ${request.name} requested by source entry ${request.entryId}`;
  }

  useEffect(() => {
    if (activePane !== 'conversation') return;
    const frame = window.requestAnimationFrame(() => {
      const panel = conversationPanelRef.current;
      const target = selectedConversationRef.current;
      if (panel === null || target === null) return;
      const usesInternalScroll = window.getComputedStyle(panel).overflowY !== 'visible';
      if (usesInternalScroll) {
        const panelBox = panel.getBoundingClientRect();
        const targetBox = target.getBoundingClientRect();
        const headingHeight = panel.querySelector<HTMLElement>('.pilot-panel-heading')
          ?.getBoundingClientRect().height ?? 0;
        panel.scrollTo({
          top: Math.max(
            0,
            panel.scrollTop + targetBox.top - panelBox.top - headingHeight - 4,
          ),
          behavior: 'auto',
        });
      } else if (revealConversationSelectionRef.current) {
        target.scrollIntoView({ block: 'center', behavior: 'auto' });
      }
      revealConversationSelectionRef.current = false;
    });
    return () => window.cancelAnimationFrame(frame);
  }, [activePane, selectedSource.entryId]);

  const selectFromTimeline = (entryId: string): void => {
    revealConversationSelectionRef.current = true;
    onSelectEntry(entryId);
    setActivePane('conversation');
  };

  const selectConversationAt = (index: number, focus: boolean): void => {
    const item = conversationItems[index];
    if (item === undefined) return;
    onSelectEntry(item.source.entryId);
    if (!focus) return;
    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => {
        const options = conversationPanelRef.current
          ?.querySelectorAll<HTMLElement>('[data-entry-id]');
        [...(options ?? [])]
          .find(option => option.dataset.entryId === item.source.entryId)
          ?.focus({ preventScroll: true });
      });
    });
  };

  const handleConversationKeyDown = (
    event: KeyboardEvent<HTMLLIElement>,
    index: number,
  ): void => {
    let nextIndex: number | undefined;
    switch (event.key) {
      case 'Enter':
      case ' ':
        nextIndex = index;
        break;
      case 'ArrowDown':
        nextIndex = Math.min(conversationItems.length - 1, index + 1);
        break;
      case 'ArrowUp':
        nextIndex = Math.max(0, index - 1);
        break;
      case 'Home':
        nextIndex = 0;
        break;
      case 'End':
        nextIndex = conversationItems.length - 1;
        break;
      default:
        return;
    }
    event.preventDefault();
    selectConversationAt(nextIndex, true);
  };

  return (
    <section className="pilot-workbench" aria-labelledby="pilot-workbench-title">
      <h2 className="visually-hidden" id="pilot-workbench-title">Session understanding</h2>
      <nav className="pilot-workbench-tabs" aria-label="Session understanding views">
        {(['timeline', 'conversation', 'evidence'] as const).map(pane => (
          <button
            type="button"
            data-pane={pane}
            aria-pressed={activePane === pane}
            key={pane}
            onClick={() => setActivePane(pane)}
          >
            {pane === 'timeline' ? 'Timeline' : pane === 'conversation' ? 'Conversation' : 'Evidence'}
          </button>
        ))}
      </nav>
      <div className="pilot-workbench-grid" data-active-pane={activePane}>
        <section
          className="pilot-workbench-panel pilot-timeline"
          data-pane="timeline"
          aria-labelledby="pilot-timeline-title"
        >
          <header className="pilot-panel-heading">
            <div>
              <h3 id="pilot-timeline-title">Timeline</h3>
            </div>
            <p>{phases.length} phases · {projection.chronology.length} recorded events</p>
          </header>
          <ol className="pilot-phase-list">
            {phases.map(phase => {
              const containsSelection = phase === selectedPhase;
              const expanded = expandedPhaseIds.has(phase.id);
              const first = phase.items[0]!;
              const last = phase.items[phase.items.length - 1]!;
              return (
                <li className="pilot-phase" data-selected={containsSelection} key={phase.id}>
                  <button
                    className="pilot-phase-toggle"
                    type="button"
                    aria-expanded={expanded}
                    onClick={() => {
                      setExpandedPhaseIds(current => {
                        const next = new Set(current);
                        if (next.has(phase.id)) next.delete(phase.id);
                        else next.add(phase.id);
                        return next;
                      });
                    }}
                  >
                    <span>Phase {String(phase.index + 1).padStart(2, '0')}</span>
                    <time dateTime={first.timestamp}>
                      {formatWorkbenchTime(first.timestamp)}–{formatWorkbenchTime(last.timestamp)}
                    </time>
                    <strong>{phase.recordedKinds.join(' · ')}</strong>
                    <i aria-hidden="true">{expanded ? '−' : '+'}</i>
                  </button>
                  {expanded ? (
                    <ol className="pilot-event-list">
                      {phase.items.map(item => {
                        const selected = item.source.entryId === selectedSource.entryId;
                        return (
                          <li
                            id={`source-${item.source.entryId}`}
                            data-selected={selected}
                            aria-current={selected ? 'true' : undefined}
                            key={item.id}
                          >
                            <button type="button" onClick={() => selectFromTimeline(item.source.entryId)}>
                              <span>{activityKindLabel(item)}</span>
                              <time dateTime={item.timestamp}>{formatWorkbenchTime(item.timestamp)}</time>
                              <strong>{item.title}</strong>
                              <small>{activityTextForDisplay(item)}</small>
                            </button>
                          </li>
                        );
                      })}
                    </ol>
                  ) : null}
                </li>
              );
            })}
          </ol>
        </section>

        <section
          className="pilot-workbench-panel pilot-conversation"
          data-pane="conversation"
          aria-labelledby="pilot-conversation-title"
          ref={conversationPanelRef}
        >
          <header className="pilot-panel-heading">
            <div>
              <h3 id="pilot-conversation-title">Conversation</h3>
            </div>
            <p>
              Full selected path · {projection.chronology.length} events · selected {selectedItemIndex + 1}
            </p>
          </header>
          <ol
            className="pilot-conversation-list"
            role="listbox"
            aria-label="Recorded conversation"
          >
            {conversationItems.map((item, index) => {
              const selected = item.source.entryId === selectedSource.entryId;
              const record = entriesById.get(item.source.entryId);
              const role = pilotChatRole(item, record);
              const assistantRecord = record?.kind === 'message' && record.role === 'assistant'
                ? record
                : undefined;
              const toolResultRecord = record?.kind === 'message' && record.role === 'toolResult'
                ? record
                : undefined;
              const linkedRequest = toolResultRecord?.toolCallId === undefined
                ? undefined
                : operationIndex.calls.get(toolResultRecord.toolCallId);
              return (
                <li
                  data-role={role}
                  data-entry-id={item.source.entryId}
                  data-anchor={item.anchorKind}
                  data-selected={selected}
                  data-status={item.evidenceStatus}
                  role="option"
                  aria-label={`${conversationSpeaker(role)}: ${item.title}, ${formatWorkbenchTime(item.timestamp)}`}
                  aria-current={selected ? 'true' : undefined}
                  aria-selected={selected}
                  aria-keyshortcuts="ArrowUp ArrowDown Home End Enter Space"
                  tabIndex={selected ? 0 : -1}
                  key={item.id}
                  ref={selected ? selectedConversationRef : undefined}
                  onClick={event => {
                    const selection = window.getSelection();
                    const selectedTextIsInside = selection?.isCollapsed === false &&
                      ((selection.anchorNode !== null && event.currentTarget.contains(selection.anchorNode)) ||
                        (selection.focusNode !== null && event.currentTarget.contains(selection.focusNode)));
                    if (selectedTextIsInside) return;
                    event.currentTarget.focus({ preventScroll: true });
                    selectConversationAt(index, false);
                  }}
                  onKeyDown={event => handleConversationKeyDown(event, index)}
                >
                  <article className="pilot-chat-turn">
                    <header className="pilot-chat-meta">
                      <div>
                        <span className="pilot-chat-author">
                          {conversationSpeaker(role)}
                        </span>
                        <span>{chatAuthorityLabel(item, role)}</span>
                        {selected ? <strong>Selected source</strong> : null}
                      </div>
                      <time dateTime={item.timestamp}>{formatWorkbenchTime(item.timestamp)}</time>
                    </header>
                    <div className="pilot-chat-bubble">
                      {role === 'checkpoint' || role === 'system' || role === 'tool' ? (
                        <strong className="pilot-chat-event-title">{item.title}</strong>
                      ) : null}
                      <p>{activityTextForDisplay(item)}</p>
                      {assistantRecord === undefined || assistantRecord.toolCalls.length === 0 ? null : (
                        <div className="pilot-chat-tool-calls" aria-label="Tool calls in this assistant message">
                          {assistantRecord.toolCalls.map(call => {
                            const result = operationIndex.results.get(call.id);
                            return (
                              <div className="pilot-chat-tool-call" key={call.id}>
                                <div>
                                  <span>Tool call</span>
                                  <strong>{call.name}</strong>
                                  <em>{result === undefined ? 'No result on path' : 'Result recorded'}</em>
                                </div>
                                <dl>
                                  <div><dt>Call</dt><dd>{call.id}</dd></div>
                                  {call.path === undefined ? null : <div><dt>Path</dt><dd>{call.path}</dd></div>}
                                  {call.editCount === undefined ? null : <div><dt>Edits</dt><dd>{call.editCount}</dd></div>}
                                  {call.bashClassification === undefined ? null : (
                                    <div><dt>Kind</dt><dd>{call.bashClassification}</dd></div>
                                  )}
                                  {result === undefined ? null : <div><dt>Result source</dt><dd>{result.entryId}</dd></div>}
                                </dl>
                              </div>
                            );
                          })}
                        </div>
                      )}
                      {linkedRequest === undefined ? null : (
                        <p className="pilot-chat-operation-link">
                          Result for <strong>{linkedRequest.name}</strong> requested in source {linkedRequest.entryId}
                        </p>
                      )}
                      {record?.kind === 'bashExecution' ? (
                        <dl className="pilot-chat-command-meta">
                          <div><dt>Command kind</dt><dd>{record.classification}</dd></div>
                          <div><dt>Exit</dt><dd>{record.exitCode ?? 'unknown'}</dd></div>
                          <div><dt>Cancelled</dt><dd>{record.cancelled ? 'yes' : 'no'}</dd></div>
                        </dl>
                      ) : null}
                      <footer>
                        <span>{normalizedEntryLabel(record)}</span>
                        <span>source {item.source.entryId}</span>
                      </footer>
                    </div>
                  </article>
                </li>
              );
            })}
          </ol>
        </section>

        <section
          className="pilot-workbench-panel pilot-evidence"
          data-pane="evidence"
          id="pilot-inspector"
          aria-labelledby="pilot-inspector-title"
        >
          <header className="pilot-panel-heading">
            <div>
              <h3 id="pilot-inspector-title" tabIndex={-1}>Evidence</h3>
            </div>
            <p>Selected {selectedItemIndex + 1} of {projection.chronology.length}</p>
          </header>
          <div className="pilot-inspector-tabs" role="tablist" aria-label="Evidence panel mode">
            <button
              type="button"
              role="tab"
              aria-selected={inspectorMode === 'discuss'}
              onClick={() => setInspectorMode('discuss')}
            >
              Discuss
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={inspectorMode === 'evidence'}
              onClick={() => setInspectorMode('evidence')}
            >
              Evidence
            </button>
          </div>
          <div hidden={inspectorMode !== 'discuss'} role="tabpanel">
            <PilotSourceChat
              key={chatInstanceId}
              projection={projection}
              selectedSource={selectedSource}
              sourceEntryIds={chatSourceEntryIds}
              onToggleSource={onToggleChatSource}
              onOpenSource={(entryId, leafId) => {
                onSelectChatSource(entryId, leafId);
                setActivePane('evidence');
              }}
            />
          </div>
          {inspectorMode !== 'evidence' ? null : (
            <>
              <div className="pilot-evidence-tabs" role="tablist" aria-label="Evidence representation">
                <button
                  type="button"
                  role="tab"
                  aria-selected={evidenceMode === 'readable'}
                  onClick={() => setEvidenceMode('readable')}
                >
                  Readable
                </button>
                <button
                  type="button"
                  role="tab"
                  aria-selected={evidenceMode === 'normalized'}
                  onClick={() => setEvidenceMode('normalized')}
                >
                  Normalized record
                </button>
              </div>
              {evidenceMode === 'readable' ? (
                <div className="pilot-evidence-readable" role="tabpanel">
                  <section className="pilot-evidence-copy" aria-labelledby="pilot-evidence-copy-title">
                    <span className="kicker">Selected recorded entry</span>
                    <h4 id="pilot-evidence-copy-title">{selectedItem?.title ?? 'Unavailable entry'}</h4>
                    <p>{selectedItem === undefined
                      ? 'No recorded entry is selected.'
                      : activityTextForDisplay(selectedItem)}</p>
                  </section>
                  <dl className="pilot-evidence-metadata">
                    <div><dt>Recorded type</dt><dd>{normalizedEntryLabel(selectedRecord)}</dd></div>
                    <div><dt>Time</dt><dd>{selectedItem === undefined ? 'Unknown' : formatWorkbenchTime(selectedItem.timestamp)}</dd></div>
                    <div><dt>Path position</dt><dd>{selectedItemIndex + 1} of {projection.chronology.length}</dd></div>
                    <div><dt>Terminal path</dt><dd>{projection.leafId}</dd></div>
                    <div><dt>Source entry</dt><dd>{selectedSource.entryId}</dd></div>
                  </dl>
                  {operationRelationship === undefined ? null : (
                    <div className="pilot-operation-relation">
                      <strong>Recorded operation relationship</strong>
                      <p>{operationRelationship}</p>
                    </div>
                  )}
                </div>
              ) : (
                <div className="pilot-evidence-normalized" role="tabpanel">
                  <p>
                    This is the bounded normalized import used by this view, not the unfiltered JSONL line.
                  </p>
                  <pre>{normalizedRecord}</pre>
                </div>
              )}
            </>
          )}
        </section>
      </div>
    </section>
  );
}

function importNoteKind(code: string): string {
  if (code.includes('omitted')) return 'omission';
  if (code === 'content_unavailable') return 'source note';
  if (code.includes('sensitive_pattern') || code.includes('explicit_egress')) {
    return 'egress warning';
  }
  if (code.includes('truncated')) return 'normalization note';
  return 'diagnostic';
}

function Diagnostics({ items }: { readonly items: readonly ResumeDiagnostic[] }) {
  const groups = [...items.reduce((result, item) => {
    const key = `${item.severity}:${item.code}`;
    const current = result.get(key);
    result.set(key, current === undefined
      ? { item, count: 1 }
      : { item: current.item, count: current.count + 1 });
    return result;
  }, new Map<string, { readonly item: ResumeDiagnostic; readonly count: number }>()).values()];
  return (
    <details
      className="diagnostics"
      id="diagnostics"
      aria-labelledby="diagnostics-title"
      hidden={items.length === 0}
    >
      <summary>
        <span id="diagnostics-title">Import notes</span>
        <small>{items.length} notes · {groups.length} categories</small>
      </summary>
      <div className="diagnostics-content">
        <p>
          Notes make normalization and model-egress boundaries visible. Only entries marked
          as omissions indicate that imported data was not represented.
        </p>
        <ul id="diagnostics-list">
          {groups.map(({ item, count }) => (
            <li key={`${item.severity}:${item.code}`}>
              <strong>{importNoteKind(item.code)}</strong>{' '}
              [{item.code}] × {count}: {item.message}
              {item.entryId === undefined ? '' : ` Example entry: ${item.entryId}.`}
            </li>
          ))}
        </ul>
      </div>
    </details>
  );
}

export function ResumeApp() {
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
  const forgetSession = (): void => {
    dispatchPilot({ type: 'reset' });
    dispatch({ type: 'forget' });
  };
  return (
    <main className="pilot-shell">
      <PilotSessionToolbar
        state={state} pathLength={projection?.path.length ?? 0} selectedLeafId={effectiveLeafId}
        onFile={file => void importSessionFile(file)}
        onSelectPath={leafId => { dispatchPilot({ type: 'reset' }); dispatch({ type: 'select-leaf', leafId }); }}
        onForget={forgetSession}
      />
      <section className="pilot-workspace" data-layout="resume">
        {state.isImporting || projection === undefined || effectivePilotSource === undefined ? <PilotEmptyWorkspace state={state} /> : (
          <PilotUnderstandingWorkbench
            projection={projection} entries={state.session.entries} selectedSource={effectivePilotSource}
            chatInstanceId={`${state.sourceMode}:${state.fileInputGeneration}:${state.session.header.sessionId}`}
            chatSourceEntryIds={pilotState.chatSourceEntryIds}
            onSelectEntry={revealSource} onSelectChatSource={revealChatSource}
            onToggleChatSource={entryId => dispatchPilot({ type: 'toggle-chat-source', entryId })}
          />
        )}
      </section>
      <Diagnostics items={diagnostics} />
    </main>
  );
}

export function mountResume(): void {
  const rootElement = document.getElementById('root');
  if (rootElement === null) throw new Error('Resume root element is missing.');

  createRoot(rootElement).render(
    <StrictMode>
      <ResumeApp />
    </StrictMode>,
  );
}
