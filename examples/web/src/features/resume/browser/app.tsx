import {
  StrictMode,
  useEffect,
  useMemo,
  useState,
  type ChangeEvent,
} from 'react';
import { createRoot } from 'react-dom/client';
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
  activityTextForDisplay,
  isSensitiveText,
  type NormalizedEntry,
  type ResumeDiagnostic,
  type ResumeProjection,
} from '../core/session';
import {
  PKE_CHAT_MESSAGE_LIMIT,
  PKE_CHAT_MESSAGE_TEXT_LIMIT,
  PKE_CHAT_MODEL,
  PKE_CHAT_REQUEST_MAX_BYTES,
  PKE_CHAT_SOURCE_LIMIT,
  pkeChatSourceFromActivity,
  pkeChatTextMessages,
  type PkeChatContext,
} from '../protocol/chat';
import {
  type PilotSourceSelection,
  type ResumeState,
} from './resume-state';
import { useResumeSession } from './use-resume-session';
import {
  type PkeChatTurnContext,
  usePkeChat,
} from './use-pke-chat';
import {
  buildWorkbenchView,
} from './workbench-view-model';
import { useWorkbench, Workbench } from './workbench';
import './styles.css';


const dateTimeFormat = new Intl.DateTimeFormat(undefined, {
  month: 'short',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});


function formatTimestamp(value: string): string {
  return dateTimeFormat.format(new Date(value));
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


const PKE_CHAT_CITATION_HREF_PREFIX = '#canopy-source-';

function sourceLinkedChatMarkdown(
  text: string,
  turnContext: PkeChatTurnContext,
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
}: {
  readonly projection: ResumeProjection;
  readonly selectedSource: PilotSourceSelection;
  readonly sourceEntryIds: readonly string[];
}) {
  const {
    onToggleChatSource,
    selectChatSource,
  } = useWorkbench();
  const [contextScope, setContextScope] = useState<PkeChatContext['scope']>('none');
  const [showPayload, setShowPayload] = useState(false);
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
  const {
    clearError,
    draft,
    error,
    messages,
    pendingMessage,
    relayStatus,
    relayStatusError,
    renderedMessages,
    setDraft,
    status,
    stopAndRestoreDraft,
    submit,
  } = usePkeChat(projection.sessionId);
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
          onToggleChatSource(selectedSource.entryId);
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
                  <Source onClick={() => selectChatSource(item.source.entryId, projection.leafId)}>
                    source {item.source.entryId} · {item.title}
                  </Source>
                  {contextScope !== 'selected' ? null : (
                    <button
                      type="button"
                      aria-label={`Remove ${item.title} from chat context`}
                      onClick={() => onToggleChatSource(item.source.entryId)}
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
                                onClick={() => selectChatSource(entryId, citationLeafId)}
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
                          onClick={() => selectChatSource(
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
            stopAndRestoreDraft();
            return;
          }
          if (!canSend) return;
          setShowPayload(false);
          submit(currentContext, sourcePayload);
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
          <PilotSourceChat
            key={chatInstanceId}
            projection={projection}
            selectedSource={selectedSource}
            sourceEntryIds={chatSourceEntryIds}
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

export function ResumeApp() {
  const {
    diagnostics,
    effectiveLeafId,
    effectivePilotSource,
    forgetSession,
    importSessionFile,
    pilotState,
    projection,
    revealChatSource,
    revealSource,
    selectPath,
    state,
    toggleChatSource,
  } = useResumeSession();
  return (
    <main className="pilot-shell">
      <PilotSessionToolbar
        state={state} pathLength={projection?.path.length ?? 0} selectedLeafId={effectiveLeafId}
        onFile={file => void importSessionFile(file)}
        onSelectPath={selectPath}
        onForget={forgetSession}
      />
      <section className="pilot-workspace" data-layout="resume">
        {state.isImporting || projection === undefined || effectivePilotSource === undefined ? <PilotEmptyWorkspace state={state} /> : (
          <PilotUnderstandingWorkbench
            projection={projection} entries={state.session.entries} selectedSource={effectivePilotSource}
            chatInstanceId={`${state.sourceMode}:${state.fileInputGeneration}:${state.session.header.sessionId}`}
            chatSourceEntryIds={pilotState.chatSourceEntryIds}
            onSelectEntry={revealSource} onSelectChatSource={revealChatSource}
            onToggleChatSource={toggleChatSource}
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
