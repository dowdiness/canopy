import {
  forwardRef,
  useImperativeHandle,
  type KeyboardEvent,
} from 'react';
import {
  activityTextForDisplay,
  type ActivityItem,
  type NormalizedEntry,
} from '../core/session';
import {
  activityKindLabel,
  normalizedEntryLabel,
} from './workbench-view-model';
import { useConversationSelectionScroll } from './use-conversation-selection-scroll';


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


export interface ConversationPaneHandle {
  revealConversationSelection: () => void;
}

export interface ConversationPaneProps {
  readonly active: boolean;
  readonly conversationItems: readonly ActivityItem[];
  readonly entriesById: ReadonlyMap<string, NormalizedEntry>;
  readonly operationIndex: Readonly<{
    readonly calls: ReadonlyMap<string, { readonly entryId: string; readonly name: string }>;
    readonly results: ReadonlyMap<string, { readonly entryId: string; readonly name: string }>;
  }>;
  readonly selectedEntryId: string;
  readonly selectedItemIndex: number;
  readonly totalEvents: number;
  readonly formatTime: (value: string) => string;
  readonly onSelectEntry: (entryId: string) => void;
}

export const ConversationPane = forwardRef<ConversationPaneHandle, ConversationPaneProps>(
  function ConversationPane(props, ref) {
    const {
      active,
      conversationItems,
      entriesById,
      operationIndex,
      selectedEntryId,
      selectedItemIndex,
      totalEvents,
      formatTime,
      onSelectEntry,
    } = props;

    const {
      conversationPanelRef,
      revealConversationSelection,
      selectedConversationRef,
    } = useConversationSelectionScroll(active, selectedEntryId);

    useImperativeHandle(ref, () => ({
      revealConversationSelection,
    }));

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
            Full selected path · {totalEvents} events · selected {selectedItemIndex + 1}
          </p>
        </header>
        <ol
          className="pilot-conversation-list"
          role="listbox"
          aria-label="Recorded conversation"
        >
          {conversationItems.map((item, index) => {
            const selected = item.source.entryId === selectedEntryId;
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
                aria-label={`${conversationSpeaker(role)}: ${item.title}, ${formatTime(item.timestamp)}`}
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
                    <time dateTime={item.timestamp}>{formatTime(item.timestamp)}</time>
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
    );
  },
);
