import { TextDecoder } from 'node:util';

import { GENUI_CANDIDATE_SCHEMA } from './genui-candidate-schema.js';
import {
  GENUI_PROVIDER_SETTINGS,
  buildFeasibilityPrompt,
  canonicalJson,
  sha256Hex,
} from './genui-feasibility-provider.js';

const CLIENT_INFO = Object.freeze({
  name: 'canopy_genui_provider_benchmark',
  title: 'Canopy Generative UI Provider Benchmark',
  version: '1',
});
const ALLOWED_ITEM_TYPES = new Set(['userMessage', 'reasoning', 'agentMessage']);
const SAFE_DELTA_METHODS = new Set([
  'item/agentMessage/delta',
  'item/reasoning/summaryPartAdded',
  'item/reasoning/summaryTextDelta',
  'item/reasoning/textDelta',
]);
const USAGE_FIELDS = Object.freeze([
  'cachedInputTokens',
  'inputTokens',
  'outputTokens',
  'reasoningOutputTokens',
  'totalTokens',
]);

export async function createCodexAppServerSession({
  frozenIdentity,
  spawnProcess,
  experimentalApi = true,
}, deps = {}) {
  if (experimentalApi !== true) {
    throw protocolError('Codex experimental API negotiation is required.');
  }
  validateFrozenIdentity(frozenIdentity);
  if (typeof spawnProcess !== 'function') {
    throw protocolError('Codex process factory is required.');
  }

  const timeoutMs = deps.timeoutMs ?? GENUI_PROVIDER_SETTINGS.timeoutMs;
  if (!Number.isInteger(timeoutMs) || timeoutMs <= 0) {
    throw protocolError('Codex protocol timeout must be a positive integer.');
  }
  const child = await spawnProcess();
  const transport = new JsonlTransport(child, {
    timeoutMs,
    setTimer: deps.setTimer ?? setTimeout,
    clearTimer: deps.clearTimer ?? clearTimeout,
  });

  try {
    const identity = await initializeProcess(transport, frozenIdentity);
    let busy = false;
    let closed = false;
    let failed = false;
    const observedThreadIds = new Set();

    return Object.freeze({
      identity,
      async runSlot({ fixture, slotId }) {
        if (closed || failed || busy) {
          return failure('request_rejected', 'Codex session is unavailable or already running a slot.');
        }
        if (!isRecord(fixture) || typeof fixture.caseId !== 'string' || typeof slotId !== 'string') {
          return failure('request_rejected', 'Codex slot requires a trusted fixture and string slot ID.');
        }
        busy = true;
        const transcriptOffset = transport.transcript.length;
        const now = deps.now ?? (() => performance.now());
        const startedAt = now();
        try {
          const result = await runSlot({
            transport,
            frozenIdentity,
            identity,
            fixture,
            slotId,
            observedThreadIds,
          });
          if (result.classification !== 'success') failed = true;
          return {
            ...result,
            elapsedMs: Math.round(now() - startedAt),
            transcript: transport.transcript.slice(transcriptOffset),
          };
        } catch (error) {
          failed = true;
          const terminal = providerFailure(error);
          await transport.terminate('SIGKILL');
          return {
            ...terminal,
            elapsedMs: Math.round(now() - startedAt),
            transcript: transport.transcript.slice(transcriptOffset),
          };
        } finally {
          busy = false;
        }
      },
      async close() {
        if (closed) return;
        closed = true;
        await transport.terminate('SIGTERM');
      },
    });
  } catch (error) {
    await transport.terminate('SIGKILL');
    throw error;
  }
}

async function initializeProcess(transport, frozenIdentity) {
  await transport.request('initialize', {
    clientInfo: CLIENT_INFO,
    capabilities: { experimentalApi: true },
  });
  transport.notify('initialized', {});

  const accountResult = await transport.request('account/read', { refreshToken: false });
  const authMode = accountResult?.account?.type;
  if (authMode !== frozenIdentity.authMode) {
    throw identityError('Codex authentication mode differs from the frozen identity.');
  }

  const entries = [];
  const requestedCursors = new Set();
  let cursor = null;
  for (;;) {
    const cursorKey = cursor === null ? '<first-page>' : cursor;
    if (requestedCursors.has(cursorKey)) {
      throw protocolError('Codex model catalog cursor is duplicate or cyclic.');
    }
    requestedCursors.add(cursorKey);
    const page = await transport.request('model/list', {
      cursor,
      includeHidden: true,
    });
    if (!isRecord(page) || !Array.isArray(page.data)) {
      throw protocolError('Codex model catalog response is malformed.');
    }
    entries.push(...page.data);
    if (page.nextCursor === null || page.nextCursor === undefined) break;
    if (typeof page.nextCursor !== 'string' || page.nextCursor.length === 0) {
      throw protocolError('Codex model catalog cursor is malformed.');
    }
    cursor = page.nextCursor;
  }

  const selected = entries.filter((entry) => isRecord(entry) && entry.model === frozenIdentity.slug);
  if (selected.length === 0) {
    throw new ProviderBoundaryError('model_not_available', 'Frozen Codex model is absent from the catalog.', true);
  }
  if (selected.length !== 1) {
    throw protocolError('Codex model catalog contains duplicate selected entries.');
  }
  const catalogEntry = selected[0];
  if (!Array.isArray(catalogEntry.supportedReasoningEfforts) || !catalogEntry.supportedReasoningEfforts.some(
    (option) => isRecord(option) && option.reasoningEffort === frozenIdentity.effort,
  )) {
    throw identityError('Frozen Codex reasoning effort is not supported.');
  }
  const catalogEntrySha256 = sha256Hex(canonicalJson(catalogEntry));
  if (catalogEntrySha256 !== frozenIdentity.catalogEntrySha256) {
    throw identityError('Codex model catalog entry differs from the frozen identity.');
  }

  return Object.freeze({
    cliVersion: frozenIdentity.cliVersion,
    slug: frozenIdentity.slug,
    effort: frozenIdentity.effort,
    authMode,
    catalogEntrySha256,
  });
}

function buildThreadStartParams(frozenIdentity) {
  return {
    model: frozenIdentity.slug,
    cwd: '/work',
    approvalPolicy: 'never',
    allowProviderModelFallback: false,
    ephemeral: true,
    dynamicTools: [],
    environments: [],
    runtimeWorkspaceRoots: [],
    selectedCapabilityRoots: [],
    config: { model_reasoning_effort: frozenIdentity.effort },
  };
}

function buildTurnStartParams(frozenIdentity, threadId, prompt) {
  return {
    threadId,
    input: [{ type: 'text', text: prompt }],
    cwd: '/work',
    model: frozenIdentity.slug,
    effort: frozenIdentity.effort,
    approvalPolicy: 'never',
    environments: [],
    runtimeWorkspaceRoots: [],
    sandboxPolicy: {
      type: 'externalSandbox',
      networkAccess: 'restricted',
    },
    outputSchema: GENUI_CANDIDATE_SCHEMA,
  };
}

async function runSlot({
  transport,
  frozenIdentity,
  identity,
  fixture,
  slotId,
  observedThreadIds,
}) {
  const prompt = buildFeasibilityPrompt(fixture);
  const threadResult = await transport.request(
    'thread/start',
    buildThreadStartParams(frozenIdentity),
  );
  validateThreadResult(threadResult, frozenIdentity, observedThreadIds);
  const threadId = threadResult.thread.id;
  const threadStarted = await transport.readNotification('thread/started');
  if (threadStarted.params?.thread?.id !== threadId) {
    throw protocolError('Codex thread/started ID differs from thread/start.');
  }

  const turnResult = await transport.request(
    'turn/start',
    buildTurnStartParams(frozenIdentity, threadId, prompt),
  );
  const turnId = turnResult?.turn?.id;
  if (typeof turnId !== 'string' || turnResult.turn.status !== 'inProgress') {
    throw protocolError('Codex turn/start response is malformed or already terminal.');
  }
  const turnStarted = await transport.readNotification('turn/started');
  if (turnStarted.params?.threadId !== threadId || turnStarted.params?.turn?.id !== turnId) {
    throw protocolError('Codex turn/started identity differs from turn/start.');
  }

  let state = initialTurnState(threadId, turnId);
  for (;;) {
    const message = await transport.readMessage();
    const transition = reduceTurn(state, message, frozenIdentity);
    state = transition.state;
    if (transition.effect.type === 'continue') continue;
    if (transition.effect.type === 'interrupt') {
      transport.requestWithoutResponse('turn/interrupt', {
        threadId,
        turnId,
      });
      throw new ProviderBoundaryError(
        'forbidden_provider_tool',
        transition.effect.message,
        true,
      );
    }
    if (transition.effect.type === 'failure') {
      throw new ProviderBoundaryError(
        transition.effect.classification,
        transition.effect.message,
        transition.effect.globalStop ?? false,
      );
    }

    const candidateJson = transition.effect.candidateJson;
    if (!hasValidUtf8Representation(candidateJson)) {
      throw new ProviderBoundaryError(
        'candidate_invalid_utf8',
        'Codex candidate is not valid UTF-8 text.',
      );
    }
    if (Buffer.byteLength(candidateJson, 'utf8') > GENUI_PROVIDER_SETTINGS.maxCandidateBytes) {
      throw new ProviderBoundaryError(
        'candidate_oversize',
        'Codex candidate exceeds the frozen byte limit.',
      );
    }
    return {
      classification: 'success',
      candidateJson,
      candidateSha256: sha256Hex(candidateJson),
      promptSha256: sha256Hex(prompt),
      caseId: fixture.caseId,
      slotId,
      identity,
      tokenUsage: transition.effect.tokenUsage,
    };
  }
}

function initialTurnState(threadId, turnId) {
  return Object.freeze({
    phase: 'streaming',
    threadId,
    turnId,
    startedItems: Object.freeze({}),
    completedItemIds: Object.freeze([]),
    agentMessages: Object.freeze([]),
    tokenUsage: null,
  });
}

function reduceTurn(state, message, frozenIdentity) {
  if (!isRecord(message)) {
    return terminalProtocolFailure(state, 'Codex emitted a non-object protocol message.');
  }
  if ('id' in message && typeof message.method === 'string') {
    return interrupt(state, `Codex requested forbidden client action: ${message.method}`);
  }
  if (typeof message.method !== 'string' || !isRecord(message.params)) {
    return terminalProtocolFailure(state, 'Codex emitted an unexpected response during a turn.');
  }

  const method = message.method;
  const params = message.params;
  if (method === 'model/rerouted') {
    return failureTransition(
      state,
      'provider_identity_mismatch',
      'Codex rerouted the frozen model.',
      true,
    );
  }
  if (method === 'thread/settings/updated') {
    if (params.threadId !== state.threadId) {
      return terminalProtocolFailure(state, 'Codex settings notification has the wrong thread ID.');
    }
    if (
      params.threadSettings?.model !== frozenIdentity.slug ||
      params.threadSettings?.effort !== frozenIdentity.effort
    ) {
      return failureTransition(
        state,
        'provider_identity_mismatch',
        'Codex thread settings drifted from the frozen model identity.',
        true,
      );
    }
    return continued(state);
  }
  if (method === 'thread/status/changed') {
    if (params.threadId !== state.threadId) {
      return terminalProtocolFailure(state, 'Codex status notification has the wrong thread ID.');
    }
    return continued(state);
  }
  if (SAFE_DELTA_METHODS.has(method)) {
    if (params.threadId !== state.threadId || params.turnId !== state.turnId) {
      return terminalProtocolFailure(state, 'Codex delta notification has the wrong thread or turn ID.');
    }
    return continued(state);
  }
  if (method === 'item/started') return reduceItemStarted(state, params);
  if (method === 'item/completed') return reduceItemCompleted(state, params);
  if (method === 'thread/tokenUsage/updated') return reduceUsage(state, params);
  if (method === 'turn/completed') return reduceTurnCompleted(state, params);
  return terminalProtocolFailure(state, `Codex emitted unsupported notification: ${method}`);
}

function reduceItemStarted(state, params) {
  const identityFailure = validateTurnIdentity(state, params);
  if (identityFailure) return identityFailure;
  const currentItem = params.item;
  if (!isRecord(currentItem) || typeof currentItem.id !== 'string' || typeof currentItem.type !== 'string') {
    return terminalProtocolFailure(state, 'Codex item/started payload is malformed.');
  }
  if (!ALLOWED_ITEM_TYPES.has(currentItem.type)) {
    return interrupt(state, `Codex emitted forbidden item type: ${currentItem.type}`);
  }
  if (currentItem.id in state.startedItems) {
    return terminalProtocolFailure(state, 'Codex started the same item more than once.');
  }
  return continued(Object.freeze({
    ...state,
    startedItems: Object.freeze({
      ...state.startedItems,
      [currentItem.id]: currentItem.type,
    }),
  }));
}

function reduceItemCompleted(state, params) {
  const identityFailure = validateTurnIdentity(state, params);
  if (identityFailure) return identityFailure;
  const currentItem = params.item;
  if (!isRecord(currentItem) || typeof currentItem.id !== 'string' || typeof currentItem.type !== 'string') {
    return terminalProtocolFailure(state, 'Codex item/completed payload is malformed.');
  }
  if (!ALLOWED_ITEM_TYPES.has(currentItem.type)) {
    return interrupt(state, `Codex emitted forbidden item type: ${currentItem.type}`);
  }
  if (state.startedItems[currentItem.id] !== currentItem.type) {
    return terminalProtocolFailure(state, 'Codex completed an item without a matching start.');
  }
  if (state.completedItemIds.includes(currentItem.id)) {
    return terminalProtocolFailure(state, 'Codex completed the same item more than once.');
  }
  if (currentItem.type === 'agentMessage' && typeof currentItem.text !== 'string') {
    return terminalProtocolFailure(state, 'Codex final agent message is not text.');
  }
  const agentMessages = currentItem.type === 'agentMessage'
    ? [...state.agentMessages, currentItem.text]
    : state.agentMessages;
  return continued(Object.freeze({
    ...state,
    completedItemIds: Object.freeze([...state.completedItemIds, currentItem.id]),
    agentMessages: Object.freeze(agentMessages),
  }));
}

function reduceUsage(state, params) {
  const identityFailure = validateTurnIdentity(state, params);
  if (identityFailure) return identityFailure;
  const last = params.tokenUsage?.last;
  if (!isRecord(last) || !USAGE_FIELDS.every((field) => Number.isInteger(last[field]) && last[field] >= 0)) {
    return terminalProtocolFailure(state, 'Codex token usage is malformed.');
  }
  const tokenUsage = Object.freeze(Object.fromEntries(USAGE_FIELDS.map((field) => [field, last[field]])));
  return continued(Object.freeze({ ...state, tokenUsage }));
}

function reduceTurnCompleted(state, params) {
  if (params.threadId !== state.threadId || params.turn?.id !== state.turnId) {
    return terminalProtocolFailure(state, 'Codex turn/completed has the wrong thread or turn ID.');
  }
  const status = params.turn.status;
  if (status === 'failed') {
    return failureTransition(state, 'provider_failed', 'Codex turn failed.');
  }
  if (status === 'interrupted') {
    return failureTransition(state, 'provider_interrupted', 'Codex turn was interrupted.');
  }
  if (status !== 'completed') {
    return terminalProtocolFailure(state, 'Codex turn completed with a non-terminal status.');
  }
  if (Object.keys(state.startedItems).length !== state.completedItemIds.length) {
    return terminalProtocolFailure(state, 'Codex turn completed before every started item completed.');
  }
  if (state.agentMessages.length !== 1) {
    return terminalProtocolFailure(state, 'Codex turn must contain exactly one final agent message.');
  }
  if (state.tokenUsage === null) {
    return terminalProtocolFailure(state, 'Codex turn completed without token telemetry.');
  }
  return {
    state: Object.freeze({ ...state, phase: 'terminal' }),
    effect: Object.freeze({
      type: 'success',
      candidateJson: state.agentMessages[0],
      tokenUsage: state.tokenUsage,
    }),
  };
}

function validateTurnIdentity(state, params) {
  if (params.threadId !== state.threadId || params.turnId !== state.turnId) {
    return terminalProtocolFailure(state, 'Codex notification has the wrong thread or turn ID.');
  }
  return null;
}

function validateThreadResult(result, frozenIdentity, observedThreadIds) {
  if (
    !isRecord(result) ||
    !isRecord(result.thread) ||
    typeof result.thread.id !== 'string' ||
    result.thread.ephemeral !== true ||
    result.thread.path !== null ||
    result.thread.cliVersion !== frozenIdentity.cliVersion
  ) {
    throw identityError('Codex thread identity differs from the frozen process contract.');
  }
  if (result.model !== frozenIdentity.slug || result.reasoningEffort !== frozenIdentity.effort) {
    throw identityError('Codex thread selected a different model or reasoning effort.');
  }
  if (observedThreadIds.has(result.thread.id)) {
    throw protocolError('Codex reused an ephemeral thread ID.');
  }
  observedThreadIds.add(result.thread.id);
}

function validateFrozenIdentity(identity) {
  if (
    !isRecord(identity) ||
    typeof identity.cliVersion !== 'string' ||
    typeof identity.slug !== 'string' ||
    typeof identity.effort !== 'string' ||
    typeof identity.authMode !== 'string' ||
    !isSha256(identity.catalogEntrySha256)
  ) {
    throw protocolError('Frozen Codex identity is malformed.');
  }
}

function hasValidUtf8Representation(value) {
  return typeof value === 'string' && Buffer.from(value, 'utf8').toString('utf8') === value;
}

function continued(state) {
  return { state, effect: Object.freeze({ type: 'continue' }) };
}

function interrupt(state, message) {
  return { state, effect: Object.freeze({ type: 'interrupt', message }) };
}

function terminalProtocolFailure(state, message) {
  return failureTransition(state, 'provider_protocol_error', message);
}

function failureTransition(state, classification, message, globalStop = false) {
  return {
    state: Object.freeze({ ...state, phase: 'terminal' }),
    effect: Object.freeze({ type: 'failure', classification, message, globalStop }),
  };
}

class JsonlTransport {
  constructor(child, { timeoutMs, setTimer, clearTimer }) {
    if (!child?.stdin || !child?.stdout || typeof child.kill !== 'function') {
      throw protocolError('Codex process does not implement the required stdio lifecycle.');
    }
    this.child = child;
    this.timeoutMs = timeoutMs;
    this.setTimer = setTimer;
    this.clearTimer = clearTimer;
    this.nextRequestId = 1;
    this.transcript = [];
    this.messages = new AsyncQueue();
    this.terminated = false;
    this.reader = this.#readStdout();
  }

  async request(method, params) {
    const id = this.nextRequestId++;
    this.#write({ id, method, params });
    const message = await this.readMessage();
    if (!isRecord(message) || message.id !== id || 'method' in message) {
      throw protocolError(`Codex response does not match request ${id} (${method}).`);
    }
    if ('error' in message) {
      throw protocolError(`Codex rejected ${method}: ${remoteErrorMessage(message.error)}`);
    }
    if (!('result' in message)) {
      throw protocolError(`Codex response for ${method} has no result.`);
    }
    return message.result;
  }

  notify(method, params) {
    this.#write({ method, params });
  }

  requestWithoutResponse(method, params) {
    const id = this.nextRequestId++;
    this.#write({ id, method, params });
  }

  async readNotification(expectedMethod) {
    const message = await this.readMessage();
    if (!isRecord(message) || message.method !== expectedMethod || 'id' in message) {
      throw protocolError(`Expected ${expectedMethod} notification.`);
    }
    return message;
  }

  async readMessage() {
    return withTimeout(
      this.messages.shift(),
      this.timeoutMs,
      this.setTimer,
      this.clearTimer,
    );
  }

  async terminate(signal) {
    if (this.terminated) return;
    this.terminated = true;
    try {
      this.child.kill(signal);
    } finally {
      this.messages.fail(protocolError('Codex process terminated.'));
      this.child.stdin.end?.();
      await Promise.resolve(this.child.exit).catch(() => undefined);
      await this.reader.catch(() => undefined);
    }
  }

  #write(message) {
    if (this.terminated) throw protocolError('Codex process is terminated.');
    this.transcript.push(normalizeTranscriptEvent('client', message));
    this.child.stdin.write(`${JSON.stringify(message)}\n`);
  }

  async #readStdout() {
    const decoder = new TextDecoder('utf-8', { fatal: true });
    let buffered = '';
    try {
      for await (const chunk of this.child.stdout) {
        const bytes = typeof chunk === 'string' ? Buffer.from(chunk, 'utf8') : chunk;
        buffered += decoder.decode(bytes, { stream: true });
        for (;;) {
          const newline = buffered.indexOf('\n');
          if (newline < 0) break;
          const line = buffered.slice(0, newline);
          buffered = buffered.slice(newline + 1);
          if (line.length === 0) throw protocolError('Codex emitted an empty JSONL line.');
          let message;
          try {
            message = JSON.parse(line);
          } catch {
            throw protocolError('Codex emitted malformed JSONL.');
          }
          if (!isRecord(message) || 'jsonrpc' in message) {
            throw protocolError('Codex emitted an invalid JSON-RPC envelope.');
          }
          this.transcript.push(normalizeTranscriptEvent('server', message));
          this.messages.push(message);
        }
      }
      buffered += decoder.decode();
      if (buffered.length !== 0) throw protocolError('Codex stdout ended with a partial JSONL line.');
      this.messages.fail(protocolError('Codex stdout reached EOF before session close.'));
    } catch (error) {
      this.messages.fail(asProviderBoundaryError(error));
    }
  }
}

class AsyncQueue {
  constructor() {
    this.values = [];
    this.waiters = [];
    this.error = null;
  }

  push(value) {
    if (this.error !== null) return;
    const waiter = this.waiters.shift();
    if (waiter) waiter.resolve(value);
    else this.values.push(value);
  }

  fail(error) {
    if (this.error !== null) return;
    this.error = error;
    for (const waiter of this.waiters.splice(0)) waiter.reject(error);
  }

  shift() {
    if (this.values.length > 0) return Promise.resolve(this.values.shift());
    if (this.error !== null) return Promise.reject(this.error);
    return new Promise((resolve, reject) => this.waiters.push({ resolve, reject }));
  }
}

function withTimeout(promise, milliseconds, setTimer, clearTimer) {
  return new Promise((resolve, reject) => {
    const timer = setTimer(
      () => reject(new ProviderBoundaryError('provider_timeout', 'Codex protocol timed out.')),
      milliseconds,
    );
    promise.then(
      (value) => { clearTimer(timer); resolve(value); },
      (error) => { clearTimer(timer); reject(error); },
    );
  });
}

function normalizeTranscriptEvent(direction, message) {
  if (typeof message.method === 'string') {
    const params = isRecord(message.params) ? message.params : {};
    return Object.freeze({
      direction,
      method: message.method,
      requestId: 'id' in message ? message.id : null,
      threadId: typeof params.threadId === 'string' ? params.threadId : null,
      turnId: typeof params.turnId === 'string' ? params.turnId : (typeof params.turn?.id === 'string' ? params.turn.id : null),
      itemType: typeof params.item?.type === 'string' ? params.item.type : null,
      terminalStatus: typeof params.turn?.status === 'string' ? params.turn.status : null,
    });
  }
  return Object.freeze({
    direction,
    responseId: message.id ?? null,
    terminalStatus: 'error' in message ? 'error' : 'ok',
  });
}

class ProviderBoundaryError extends Error {
  constructor(classification, message, globalStop = false) {
    super(message);
    this.name = 'ProviderBoundaryError';
    this.classification = classification;
    this.globalStop = globalStop;
  }
}

function protocolError(message) {
  return new ProviderBoundaryError('provider_protocol_error', message);
}

function identityError(message) {
  return new ProviderBoundaryError('provider_identity_mismatch', message, true);
}

function asProviderBoundaryError(error) {
  return error instanceof ProviderBoundaryError
    ? error
    : protocolError(error instanceof Error ? error.message : String(error));
}

function providerFailure(error) {
  const boundaryError = asProviderBoundaryError(error);
  return failure(
    boundaryError.classification,
    boundaryError.message,
    boundaryError.globalStop,
  );
}

function failure(classification, message, globalStop = false) {
  return { classification, message, ...(globalStop ? { globalStop: true } : {}) };
}

function remoteErrorMessage(value) {
  if (isRecord(value) && typeof value.message === 'string') return value.message;
  return 'remote protocol error';
}

function isRecord(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isSha256(value) {
  return typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);
}
