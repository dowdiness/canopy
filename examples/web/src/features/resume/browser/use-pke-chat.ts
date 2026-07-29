import { useEffect, useMemo, useRef, useState } from 'react';
import { useChat } from '@ai-sdk/react';
import { DefaultChatTransport, type ChatStatus, type UIMessage } from 'ai';
import {
  parsePkeChatStatus,
  pkeChatTextMessages,
  type PkeChatContext,
  type PkeChatSource,
  type PkeChatStatus,
} from '../protocol/chat';

export interface PkeChatTurnContext {
  readonly context: PkeChatContext;
  readonly sources: readonly PkeChatSource[];
}

export interface PkeChatTurn {
  readonly message: UIMessage;
  readonly turnContext: PkeChatTurnContext;
}

const NO_HISTORY_CHAT_CONTEXT: PkeChatTurnContext = Object.freeze({
  context: Object.freeze({ scope: 'none' }),
  sources: Object.freeze([]),
});

export interface PkeChatController {
  readonly draft: string;
  readonly error: Error | undefined;
  readonly messages: readonly UIMessage[];
  readonly pendingMessage: UIMessage | undefined;
  readonly relayStatus: PkeChatStatus | undefined;
  readonly relayStatusError: string | undefined;
  readonly renderedMessages: readonly PkeChatTurn[];
  readonly status: ChatStatus;
  clearError(): void;
  setDraft(draft: string): void;
  stopAndRestoreDraft(): void;
  submit(context: PkeChatContext, sources: readonly PkeChatSource[]): void;
}

export function usePkeChat(sessionId: string): PkeChatController {
  const [draft, setDraft] = useState('');
  const [draftMessageId, setDraftMessageId] = useState(() => crypto.randomUUID());
  const [contextByMessageId, setContextByMessageId] = useState<
    ReadonlyMap<string, PkeChatTurnContext>
  >(() => new Map());
  const [relayStatus, setRelayStatus] = useState<PkeChatStatus>();
  const [relayStatusError, setRelayStatusError] = useState<string>();
  const outboundContextRef = useRef<PkeChatContext>(NO_HISTORY_CHAT_CONTEXT.context);
  const outboundSourcesRef = useRef<readonly PkeChatSource[]>(NO_HISTORY_CHAT_CONTEXT.sources);
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
    id: `pke-chat:${sessionId}`,
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
    restoreUnansweredUserMessage();
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

  const submit = (context: PkeChatContext, sources: readonly PkeChatSource[]): void => {
    if (pendingMessage === undefined) return;
    const turnContext: PkeChatTurnContext = Object.freeze({ context, sources });
    outboundContextRef.current = context;
    outboundSourcesRef.current = sources;
    setContextByMessageId(current => {
      const next = new Map(current);
      next.set(pendingMessage.id, turnContext);
      return next;
    });
    setDraft('');
    setDraftMessageId(crypto.randomUUID());
    void sendMessage(pendingMessage);
  };

  const stopAndRestoreDraft = (): void => {
    void stop();
    restoreUnansweredUserMessage();
  };

  return {
    draft,
    error,
    messages,
    pendingMessage,
    relayStatus,
    relayStatusError,
    renderedMessages,
    status,
    clearError,
    setDraft,
    stopAndRestoreDraft,
    submit,
  };
}
