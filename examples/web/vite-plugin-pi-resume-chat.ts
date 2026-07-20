import { createDeepSeek } from '@ai-sdk/deepseek';
import {
  convertToModelMessages,
  createUIMessageStream,
  createUIMessageStreamResponse,
  safeValidateUIMessages,
  streamText,
  type UIMessage,
} from 'ai';
import type { Connect, Plugin } from 'vite';
import {
  PKE_CHAT_DEEPSEEK_PROVIDER_OPTIONS,
  PKE_CHAT_MODEL,
  PKE_CHAT_PROVIDER,
  PKE_CHAT_REQUEST_MAX_BYTES,
  PkeChatProtocolError,
  buildPkeChatSystemPrompt,
  parsePkeChatEnvelope,
  validatePkeChatMessages,
  type PkeChatContext,
  type PkeChatSource,
  type PkeChatStatus,
} from './src/pi-resume-chat-protocol.ts';
import {
  isLoopbackAddress,
  isSameOrigin,
} from './src/pi-resume-chat-protocol.ts';

const PKE_CHAT_FAKE_MODEL = 'pke-chat-fake-v1' as const;
const PKE_CHAT_OUTPUT_TOKEN_LIMIT = 1_600;

interface PkeChatProvider {
  readonly status: PkeChatStatus;
  readonly respond: (
    messages: UIMessage[],
    context: PkeChatContext,
    sources: readonly PkeChatSource[],
    signal: AbortSignal,
  ) => Promise<Response>;
}

export function piResumeChatPlugin(): Plugin {
  const provider = createPkeChatProvider(process.env);
  return {
    name: 'pi-resume-chat-relay',
    apply: 'serve',
    configureServer(server) {
      server.middlewares.use(
        '/api/pi-resume-chat/status',
        (request, response) => statusHandler(request, response, provider.status),
      );
      server.middlewares.use(
        '/api/pi-resume-chat',
        (request, response) => chatHandler(request, response, provider),
      );
    },
  };
}

function createPkeChatProvider(env: NodeJS.ProcessEnv): PkeChatProvider {
  if (env.PI_RESUME_CHAT_FAKE === '1') {
    const delayMilliseconds = fakeDelayMilliseconds(env);
    return Object.freeze({
      status: Object.freeze({
        available: true,
        provider: 'fake',
        model: PKE_CHAT_FAKE_MODEL,
        localRelay: true,
      }),
      respond: async (messages, context, sources, signal) =>
        fakeChatResponse(messages, context, sources, signal, delayMilliseconds),
    });
  }

  const apiKey = env.DEEPSEEK_API_KEY;
  const available = typeof apiKey === 'string' && apiKey.length > 0;
  const status: PkeChatStatus = Object.freeze({
    available,
    provider: PKE_CHAT_PROVIDER,
    model: PKE_CHAT_MODEL,
    localRelay: true,
  });
  if (!available) {
    return Object.freeze({
      status,
      respond: async () => {
        throw new PkeChatUnavailableError();
      },
    });
  }

  const deepSeek = createDeepSeek({ apiKey });
  return Object.freeze({
    status,
    respond: async (messages, context, sources, signal) => {
      const result = streamText({
        model: deepSeek(PKE_CHAT_MODEL),
        system: buildPkeChatSystemPrompt(context, sources),
        messages: await convertToModelMessages(messages),
        maxOutputTokens: PKE_CHAT_OUTPUT_TOKEN_LIMIT,
        providerOptions: PKE_CHAT_DEEPSEEK_PROVIDER_OPTIONS,
        abortSignal: signal,
      });
      return result.toUIMessageStreamResponse({
        onError: () => 'DeepSeek could not complete this response.',
      });
    },
  });
}

async function statusHandler(
  request: Connect.IncomingMessage,
  response: Connect.ServerResponse,
  status: PkeChatStatus,
): Promise<void> {
  if (request.method !== 'GET') {
    sendJson(response, 405, { message: 'Only GET is supported.' });
    return;
  }
  if (!guardLocalRequest(request, response, false)) return;
  sendJson(response, 200, status);
}

async function chatHandler(
  request: Connect.IncomingMessage,
  response: Connect.ServerResponse,
  provider: PkeChatProvider,
): Promise<void> {
  if (request.method !== 'POST') {
    sendJson(response, 405, { message: 'Only POST is supported.' });
    return;
  }
  if (!guardLocalRequest(request, response, true)) return;
  if (!request.headers['content-type']?.toLowerCase().startsWith('application/json')) {
    sendJson(response, 415, { message: 'Content-Type must be application/json.' });
    return;
  }
  if (!provider.status.available) {
    sendJson(response, 503, {
      message: 'DeepSeek chat is unavailable. Set DEEPSEEK_API_KEY and restart the local server.',
    });
    return;
  }

  const controller = new AbortController();
  let completed = false;
  const abort = (): void => {
    if (!completed) controller.abort();
  };
  request.once('aborted', abort);
  response.once('close', abort);

  try {
    const envelope = parsePkeChatEnvelope(await readJsonBody(request));
    const validated = await safeValidateUIMessages<UIMessage>({ messages: envelope.messages });
    if (!validated.success) {
      throw new PkeChatProtocolError('invalid_chat_messages', 'Chat messages failed validation.');
    }
    const messages = validatePkeChatMessages(validated.data);
    const providerResponse = await provider.respond(
      messages,
      envelope.context,
      envelope.sources,
      controller.signal,
    );
    if (controller.signal.aborted || response.destroyed) return;
    await pipeWebResponse(providerResponse, response, controller.signal);
    completed = true;
  } catch (error) {
    completed = true;
    if (response.destroyed) return;
    if (error instanceof PkeChatRequestTooLargeError) {
      sendJson(response, 413, { message: 'Chat request exceeds the 4 MiB limit.' });
    } else if (error instanceof PkeChatProtocolError) {
      sendJson(response, 400, { message: error.message });
    } else if (error instanceof PkeChatUnavailableError) {
      sendJson(response, 503, { message: 'DeepSeek chat is unavailable.' });
    } else if (controller.signal.aborted || isAbortError(error)) {
      sendJson(response, 499, { message: 'Chat request aborted.' });
    } else {
      sendJson(response, 502, { message: 'DeepSeek chat failed.' });
    }
  } finally {
    request.off('aborted', abort);
    response.off('close', abort);
  }
}

function fakeChatResponse(
  messages: UIMessage[],
  context: PkeChatContext,
  sources: readonly PkeChatSource[],
  signal: AbortSignal,
  delayMilliseconds: number,
): Response {
  const question = messages[messages.length - 1]?.parts
    .filter(part => part.type === 'text')
    .map(part => part.text)
    .join(' ') ?? '';
  const firstSource = sources[0]?.source.entryId;
  const answer = context.scope === 'none' || firstSource === undefined
    ? [
        `I can answer “${question}” without attached activity history.`,
        '',
        '**Context:**',
        '',
        '- No session source was sent.',
        '- This remains model-generated text.',
      ].join('\n')
    : context.scope === 'path'
      ? [
          `I can discuss “${question}” with the attached terminal path.`,
          '',
          '**Context:**',
          '',
          `- First exact source: [source:${firstSource}]`,
          '- Scope: current terminal path.',
        ].join('\n')
      : [
          `I can discuss “${question}” from the attached moments.`,
          '',
          '**Context:**',
          '',
          `- First exact source: [source:${firstSource}]`,
          '- Scope: explicitly selected moments.',
        ].join('\n');
  const stream = createUIMessageStream({
    originalMessages: messages,
    execute: async ({ writer }) => {
      await abortableDelay(delayMilliseconds, signal);
      if (signal.aborted) return;
      const suffix = messages.length.toString();
      writer.write({ type: 'start', messageId: `fake-assistant-message-${suffix}` });
      writer.write({ type: 'start-step' });
      writer.write({ type: 'text-start', id: `fake-text-${suffix}` });
      writer.write({ type: 'text-delta', id: `fake-text-${suffix}`, delta: answer });
      writer.write({ type: 'text-end', id: `fake-text-${suffix}` });
      writer.write({ type: 'finish-step' });
      writer.write({ type: 'finish', finishReason: 'stop' });
    },
  });
  return createUIMessageStreamResponse({ stream });
}

function guardLocalRequest(
  request: Connect.IncomingMessage,
  response: Connect.ServerResponse,
  requireOrigin: boolean,
): boolean {
  const host = request.headers.host;
  const origin = request.headers.origin;
  const protocol = 'encrypted' in request.socket && request.socket.encrypted === true
    ? 'https:'
    : 'http:';
  const originAccepted = typeof host === 'string' && (
    origin === undefined ? !requireOrigin : isSameOrigin(origin, host, protocol)
  );
  if (!isLoopbackAddress(request.socket.remoteAddress) || !originAccepted) {
    sendJson(response, 403, { message: 'Origin or loopback check failed.' });
    return false;
  }
  return true;
}

async function pipeWebResponse(
  source: Response,
  target: Connect.ServerResponse,
  signal: AbortSignal,
): Promise<void> {
  target.statusCode = source.status;
  source.headers.forEach((value, name) => target.setHeader(name, value));
  target.setHeader('cache-control', 'no-store');
  if (source.body === null) {
    target.end();
    return;
  }
  const reader = source.body.getReader();
  try {
    while (!signal.aborted) {
      const { done, value } = await reader.read();
      if (done) break;
      target.write(Buffer.from(value));
    }
  } finally {
    if (signal.aborted) await reader.cancel();
  }
  if (!target.destroyed) target.end();
}

class PkeChatRequestTooLargeError extends Error {}
class PkeChatUnavailableError extends Error {}

async function readJsonBody(request: AsyncIterable<Uint8Array>): Promise<unknown> {
  const chunks: Uint8Array[] = [];
  let bytes = 0;
  for await (const chunk of request) {
    bytes += chunk.byteLength;
    if (bytes > PKE_CHAT_REQUEST_MAX_BYTES) throw new PkeChatRequestTooLargeError();
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new PkeChatProtocolError('invalid_chat_json', 'Chat request is not valid JSON.');
  }
}

function fakeDelayMilliseconds(env: NodeJS.ProcessEnv): number {
  const parsed = Number(env.PI_RESUME_CHAT_FAKE_DELAY_MS ?? '40');
  return Number.isInteger(parsed) && parsed >= 0 && parsed <= 2_000 ? parsed : 40;
}

function abortableDelay(milliseconds: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal.aborted) {
      reject(new DOMException('Aborted', 'AbortError'));
      return;
    }
    const timer = setTimeout(resolve, milliseconds);
    signal.addEventListener('abort', () => {
      clearTimeout(timer);
      reject(new DOMException('Aborted', 'AbortError'));
    }, { once: true });
  });
}

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === 'AbortError';
}

function sendJson(
  response: Connect.ServerResponse,
  status: number,
  body: unknown,
): void {
  response.statusCode = status;
  response.setHeader('content-type', 'application/json; charset=utf-8');
  response.setHeader('cache-control', 'no-store');
  response.end(JSON.stringify(body));
}
