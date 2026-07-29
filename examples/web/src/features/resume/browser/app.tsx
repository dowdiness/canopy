import { useChat } from '@ai-sdk/react';
import { DefaultChatTransport, type ChatTransport, type UIMessage } from 'ai';
import {
  StrictMode,
  useEffect,
  useLayoutEffect,
  useMemo,
  useReducer,
  useRef,
  useState,
  type ChangeEvent,
  type Ref,
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
  type NormalizedEntry,
  type ReducedPiSession,
  type ResumeDiagnostic,
  type ResumeProjection,
} from '../core/session';
import { buildWorkbenchView } from './workbench-view-model';
import { useWorkbenchNavigation, Workbench } from './workbench';
import './styles.css';
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

const demoSession = reducePiSession(parsePiSessionJsonl(fixtureSource));

const productionUnavailableChatTransport: ChatTransport<UIMessage> = Object.freeze({
  sendMessages: async () => {
    throw new Error('Resume chat is available only in local development.');
  },
  reconnectToStream: async () => null,
});

const dateTimeFormat = new Intl.DateTimeFormat('en-US', {
  timeZone: 'UTC',
  month: 'short',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
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

const forgottenImportStatus: ImportStatus = Object.freeze({
  message: 'Imported session forgotten. The demo transcript is active again.',
  tone: 'idle',
});

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
        importStatus: forgottenImportStatus,
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
      <h1
        id="pilot-view-title"
        className="visually-hidden"
        tabIndex={-1}
        data-route-heading
      >
        {projectName} session
      </h1>
      <div className="pilot-file-control">
        <label htmlFor="session-file">Open session</label>
        <input
          key={state.fileInputGeneration}
          className="file-input"
          id="session-file"
          type="file"
          data-route-focus="session-file"
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
          data-route-focus="branch-select"
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
          data-route-focus="forget-session"
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


interface PilotChatTurnContext {
  readonly context: PkeChatContext;
  readonly sources: readonly PkeChatSource[];
}

interface PkeCompletedChatTextMessage {
  readonly id: string;
  readonly role: 'user' | 'assistant';
  readonly parts: readonly {
    readonly type: 'text';
    readonly text: string;
  }[];
}

export interface PkeCompletedChatTurn {
  readonly user: PkeCompletedChatTextMessage & { readonly role: 'user' };
  readonly assistant: PkeCompletedChatTextMessage & { readonly role: 'assistant' };
  readonly context: PkeChatContext;
  readonly sources: readonly PkeChatSource[];
}

export interface ResumeRouteSnapshot {
  readonly version: 1;
  readonly loaded: {
    readonly session: ReducedPiSession;
    readonly sourceMode: 'demo' | 'imported';
    readonly importedFileName?: string;
  };
  readonly selectedLeafId: string | null;
  readonly selectedSourceEntryId: string | null;
  readonly completedChat: readonly PkeCompletedChatTurn[];
}

const EMPTY_COMPLETED_CHAT: readonly PkeCompletedChatTurn[] = Object.freeze([]);

const NO_HISTORY_CHAT_CONTEXT: PilotChatTurnContext = Object.freeze({
  context: Object.freeze({ scope: 'none' }),
  sources: Object.freeze([]),
});

const PKE_CHAT_CITATION_HREF_PREFIX = '#canopy-source-';

function completedChatHistory(
  messages: readonly UIMessage[],
  contextByMessageId: ReadonlyMap<string, PilotChatTurnContext>,
): readonly PkeCompletedChatTurn[] {
  const textMessages = pkeChatTextMessages(messages);
  return Object.freeze(textMessages.flatMap((user, index) => {
    if (index % 2 !== 0 || user.role !== 'user') return [];
    const assistant = textMessages[index + 1];
    const turnContext = contextByMessageId.get(user.id);
    if (
      assistant?.role !== 'assistant' ||
      turnContext === undefined ||
      user.parts.length === 0 ||
      assistant.parts.length === 0 ||
      user.parts.some(part => typeof part.text !== 'string') ||
      assistant.parts.some(part => typeof part.text !== 'string')
    ) {
      return [];
    }
    return [Object.freeze({
      user: Object.freeze({
        id: user.id,
        role: 'user' as const,
        parts: Object.freeze(user.parts.map(part => Object.freeze({
          type: 'text' as const,
          text: part.text!,
        }))),
      }),
      assistant: Object.freeze({
        id: assistant.id,
        role: 'assistant' as const,
        parts: Object.freeze(assistant.parts.map(part => Object.freeze({
          type: 'text' as const,
          text: part.text!,
        }))),
      }),
      context: turnContext.context,
      sources: turnContext.sources,
    })];
  }));
}

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

interface PilotSourceChatProps {
  readonly projection: ResumeProjection;
  readonly selectedSource: PilotSourceSelection;
  readonly sourceEntryIds: readonly string[];
  readonly initialCompletedChat: readonly PkeCompletedChatTurn[];
  readonly onToggleSource: (entryId: string) => void;
  readonly onOpenSource: (entryId: string, leafId: string) => void;
  readonly onCompletedChatChange: (history: readonly PkeCompletedChatTurn[]) => void;
}

function PilotSourceChat({
  projection,
  selectedSource,
  sourceEntryIds,
  initialCompletedChat,
  onToggleSource,
  onOpenSource,
  onCompletedChatChange,
}: PilotSourceChatProps) {
  const [draft, setDraft] = useState('');
  const [draftMessageId, setDraftMessageId] = useState(() => crypto.randomUUID());
  const [contextScope, setContextScope] = useState<PkeChatContext['scope']>('none');
  const [contextByMessageId, setContextByMessageId] = useState<
    ReadonlyMap<string, PilotChatTurnContext>
  >(() => new Map(initialCompletedChat.map(turn => [
    turn.user.id,
    Object.freeze({ context: turn.context, sources: turn.sources }),
  ])));
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
  const transport = useMemo<ChatTransport<UIMessage>>(
    () => import.meta.env.DEV
      ? new DefaultChatTransport<UIMessage>({
          api: '/api/pi-resume-chat',
          prepareSendMessagesRequest: ({ messages }) => ({
            body: {
              messages: pkeChatTextMessages(messages),
              context: outboundContextRef.current,
              sources: outboundSourcesRef.current,
            },
          }),
        })
      : productionUnavailableChatTransport,
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
    messages: initialCompletedChat.flatMap(turn => [turn.user, turn.assistant].map(message => ({
      id: message.id,
      role: message.role,
      parts: message.parts.map(part => ({ type: part.type, text: part.text })),
    }))),
    onFinish: ({ messages: completedMessages, isAbort, isDisconnect, isError }) => {
      if (isAbort || isDisconnect || isError) return;
      onCompletedChatChange(completedChatHistory(completedMessages, contextByMessageId));
    },
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
    if (!import.meta.env.DEV) return;
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
  const relayAvailable = import.meta.env.DEV && relayStatus?.available === true;
  const requestTooLarge = outboundBytes > PKE_CHAT_REQUEST_MAX_BYTES;
  const messageLimitReached = messages.length >= PKE_CHAT_MESSAGE_LIMIT;
  const canSend = relayAvailable && pendingMessage !== undefined &&
    !requestTooLarge && !messageLimitReached;
  const providerLabel = !import.meta.env.DEV
    ? 'Chat unavailable · production'
    : relayStatus === undefined
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
      {!import.meta.env.DEV ? (
        <p
          className="pilot-chat-unavailable"
          data-resume-production-chat-unavailable
          role="status"
        >
          Chat is available only in local development. Session inspection remains fully available.
        </p>
      ) : relayStatus?.available === false ? (
        <p className="pilot-chat-unavailable" role="status">
          Set DEEPSEEK_API_KEY and restart the local server to send messages.
        </p>
      ) : null}
      {!import.meta.env.DEV || relayStatusError === undefined ? null : (
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
      {!import.meta.env.DEV ? null : <PromptInput
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
            data-route-focus="chat-message"
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
      </PromptInput>}
    </section>
  );
}

function PilotWorkbenchChat({
  projection,
  selectedSource,
  sourceEntryIds,
  initialCompletedChat,
  onToggleSource,
  onCompletedChatChange,
}: Omit<PilotSourceChatProps, 'onOpenSource'>) {
  const { selectChatSource } = useWorkbenchNavigation();
  return (
    <PilotSourceChat
      projection={projection}
      selectedSource={selectedSource}
      sourceEntryIds={sourceEntryIds}
      initialCompletedChat={initialCompletedChat}
      onToggleSource={onToggleSource}
      onCompletedChatChange={onCompletedChatChange}
      onOpenSource={selectChatSource}
    />
  );
}

function PilotUnderstandingWorkbench({
  projection,
  entries,
  selectedSource,
  chatInstanceId,
  chatSourceEntryIds,
  initialCompletedChat,
  onSelectEntry,
  onSelectChatSource,
  onToggleChatSource,
  onCompletedChatChange,
}: {
  readonly projection: ResumeProjection;
  readonly entries: readonly NormalizedEntry[];
  readonly selectedSource: PilotSourceSelection;
  readonly chatInstanceId: string;
  readonly chatSourceEntryIds: readonly string[];
  readonly initialCompletedChat: readonly PkeCompletedChatTurn[];
  readonly onSelectEntry: (entryId: string) => void;
  readonly onSelectChatSource: (entryId: string, leafId: string) => void;
  readonly onToggleChatSource: (entryId: string) => void;
  readonly onCompletedChatChange: (history: readonly PkeCompletedChatTurn[]) => void;
}) {
  const viewModel = useMemo(
    () => buildWorkbenchView(projection, entries, selectedSource.entryId),
    [entries, projection, selectedSource.entryId],
  );
  return (
    <Workbench.Root
      viewModel={viewModel}
      selectedEntryId={selectedSource.entryId}
      terminalPathId={projection.leafId}
      onSelectEntry={onSelectEntry}
      onSelectChatSource={onSelectChatSource}
      onToggleChatSource={onToggleChatSource}
    >
      <h2 className="visually-hidden" id="pilot-workbench-title">Session understanding</h2>
      <Workbench.Tabs />
      <Workbench.Grid>
        <Workbench.Timeline />
        <Workbench.Conversation />
        <Workbench.Evidence>
          <PilotWorkbenchChat
            key={chatInstanceId}
            projection={projection}
            selectedSource={selectedSource}
            sourceEntryIds={chatSourceEntryIds}
            initialCompletedChat={initialCompletedChat}
            onToggleSource={onToggleChatSource}
            onCompletedChatChange={onCompletedChatChange}
          />
        </Workbench.Evidence>
      </Workbench.Grid>
    </Workbench.Root>
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

interface ResumeAppProps {
  readonly initialSnapshot?: ResumeRouteSnapshot;
  readonly initialDemoRestored?: boolean;
  readonly onSnapshotChange?: (snapshot: ResumeRouteSnapshot) => void;
  readonly onForgetSnapshot?: () => void;
  readonly surfaceRef?: Ref<HTMLDivElement>;
}

export function ResumeApp({
  initialSnapshot,
  initialDemoRestored = false,
  onSnapshotChange,
  onForgetSnapshot,
  surfaceRef,
}: ResumeAppProps = {}) {
  const restoredState: ResumeState = initialSnapshot === undefined
    ? initialDemoRestored
      ? { ...initialResumeState, importStatus: forgottenImportStatus }
      : initialResumeState
    : {
        session: initialSnapshot.loaded.session,
        sourceMode: initialSnapshot.loaded.sourceMode,
        ...(initialSnapshot.loaded.importedFileName === undefined
          ? {}
          : { importedFileName: initialSnapshot.loaded.importedFileName }),
        selectedLeafId: initialSnapshot.selectedLeafId,
        isImporting: false,
        importStatus: {
          message: initialSnapshot.loaded.sourceMode === 'imported'
            ? 'Imported session restored from same-tab memory.'
            : '',
          tone: 'idle',
        },
        fileInputGeneration: 0,
      };
  const restoredPilotState: PilotViewState = initialSnapshot?.selectedSourceEntryId == null
    ? initialPilotViewState
    : {
        selectedSource: { entryId: initialSnapshot.selectedSourceEntryId },
        chatSourceEntryIds: Object.freeze([]),
      };
  const [state, dispatch] = useReducer(reduceResumeState, restoredState);
  const [pilotState, dispatchPilot] = useReducer(reducePilotViewState, restoredPilotState);
  const [ready, setReady] = useState(false);
  useLayoutEffect(() => setReady(true), []);
  const restoredChatInstanceId = initialSnapshot === undefined
    ? undefined
    : `${restoredState.sourceMode}:${restoredState.fileInputGeneration}:${restoredState.session.header.sessionId}`;
  const [completedChatMemory, setCompletedChatMemory] = useState<{
    readonly instanceId: string;
    readonly history: readonly PkeCompletedChatTurn[];
  } | undefined>(() => restoredChatInstanceId === undefined
    ? undefined
    : {
        instanceId: restoredChatInstanceId,
        history: initialSnapshot?.completedChat ?? EMPTY_COMPLETED_CHAT,
      });
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
  const chatInstanceId = `${state.sourceMode}:${state.fileInputGeneration}:${state.session.header.sessionId}`;
  const completedChat = completedChatMemory?.instanceId === chatInstanceId
    ? completedChatMemory.history
    : EMPTY_COMPLETED_CHAT;
  const routeSnapshot = useMemo<ResumeRouteSnapshot>(() => Object.freeze({
    version: 1,
    loaded: Object.freeze({
      session: state.session,
      sourceMode: state.sourceMode,
      ...(state.importedFileName === undefined
        ? {}
        : { importedFileName: state.importedFileName }),
    }),
    selectedLeafId: state.selectedLeafId,
    selectedSourceEntryId: effectivePilotSource?.entryId ?? null,
    completedChat,
  }), [completedChat, effectivePilotSource?.entryId, state.importedFileName,
    state.selectedLeafId, state.session, state.sourceMode]);
  useLayoutEffect(() => {
    onSnapshotChange?.(routeSnapshot);
  }, [onSnapshotChange, routeSnapshot]);
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
    window.history.replaceState(window.history.state, '', `#source-${entryId}`);
  };
  const revealChatSource = (entryId: string, leafId: string): void => {
    if (projection?.leafId === leafId) { revealSource(entryId); return; }
    if (!state.session.entries.some(entry => entry.id === leafId) ||
        !state.session.entries.some(entry => entry.id === entryId)) return;
    dispatchPilot({ type: 'open-source', entryId });
    dispatch({ type: 'select-leaf', leafId });
    window.history.replaceState(window.history.state, '', `#source-${entryId}`);
  };
  const forgetSession = (): void => {
    onForgetSnapshot?.();
    setCompletedChatMemory(undefined);
    dispatchPilot({ type: 'reset' });
    dispatch({ type: 'forget' });
  };
  return (
    <div
      className="resume-surface"
      data-resume-ready={ready ? 'true' : 'false'}
      inert={ready ? undefined : true}
      ref={surfaceRef}
    >
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
              chatInstanceId={chatInstanceId}
              chatSourceEntryIds={pilotState.chatSourceEntryIds}
              initialCompletedChat={completedChat}
              onSelectEntry={revealSource} onSelectChatSource={revealChatSource}
              onToggleChatSource={entryId => dispatchPilot({ type: 'toggle-chat-source', entryId })}
              onCompletedChatChange={history => setCompletedChatMemory({
                instanceId: chatInstanceId,
                history,
              })}
            />
          )}
        </section>
        <Diagnostics items={diagnostics} />
      </main>
    </div>
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
