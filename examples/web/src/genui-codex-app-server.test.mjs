import assert from 'node:assert/strict';
import { PassThrough, Writable } from 'node:stream';
import test from 'node:test';

import { GENUI_CANDIDATE_SCHEMA } from './genui-candidate-schema.js';
import {
  createCodexAppServerSession,
} from './genui-codex-app-server.js';
import {
  buildFeasibilityPrompt,
  canonicalJson,
  sha256Hex,
} from './genui-feasibility-provider.js';
import { GENUI_FEASIBILITY_FIXTURES } from './genui-feasibility-fixtures.js';

const MODEL_ENTRY = Object.freeze({
  id: 'gpt-5.6-luna',
  model: 'gpt-5.6-luna',
  displayName: 'GPT-5.6 Luna',
  description: 'test catalog entry',
  defaultReasoningEffort: 'medium',
  supportedReasoningEfforts: [
    { reasoningEffort: 'low', description: 'low' },
    { reasoningEffort: 'medium', description: 'medium' },
  ],
  isDefault: false,
  hidden: false,
});
const FROZEN_IDENTITY = Object.freeze({
  cliVersion: '0.144.4',
  slug: 'gpt-5.6-luna',
  effort: 'medium',
  authMode: 'chatgpt',
  catalogEntrySha256: sha256Hex(canonicalJson(MODEL_ENTRY)),
});
const FIXTURE = GENUI_FEASIBILITY_FIXTURES[0];
const CANDIDATE = '{\n  "type": "Stack",\n  "label": "日本語"\n}\n';
const USAGE_LAST = Object.freeze({
  cachedInputTokens: 3,
  inputTokens: 17,
  outputTokens: 11,
  reasoningOutputTokens: 5,
  totalTokens: 28,
});
const USAGE_TOTAL = Object.freeze({
  cachedInputTokens: 30,
  inputTokens: 170,
  outputTokens: 110,
  reasoningOutputTokens: 50,
  totalTokens: 280,
});
const SERVER_REQUEST_METHODS = Object.freeze([
  'item/commandExecution/requestApproval',
  'item/fileChange/requestApproval',
  'item/tool/requestUserInput',
  'mcpServer/elicitation/request',
  'item/permissions/requestApproval',
  'item/tool/call',
  'account/chatgptAuthTokens/refresh',
  'attestation/generate',
  'currentTime/read',
  'applyPatchApproval',
  'execCommandApproval',
]);
const FORBIDDEN_ITEM_TYPES = Object.freeze([
  'hookPrompt',
  'plan',
  'commandExecution',
  'fileChange',
  'mcpToolCall',
  'dynamicToolCall',
  'collabAgentToolCall',
  'subAgentActivity',
  'webSearch',
  'imageView',
  'sleep',
  'imageGeneration',
  'enteredReviewMode',
  'exitedReviewMode',
  'contextCompaction',
]);

function response(request, result) {
  return { id: request.id, result };
}

function notification(method, params) {
  return { method, params };
}

function initializeResult() {
  return {
    userAgent: 'codex-test',
    codexHome: '/codex-home',
    platformFamily: 'unix',
    platformOs: 'linux',
  };
}

function thread(id = 'thread-1') {
  return {
    id,
    cliVersion: FROZEN_IDENTITY.cliVersion,
    cwd: '/work',
    ephemeral: true,
    path: null,
    modelProvider: 'openai',
  };
}

function turn(id = 'turn-1', status = 'inProgress', items = []) {
  return { id, status, items, error: null };
}

function item(id, type, fields = {}) {
  return { id, type, ...fields };
}

function itemStarted(threadId, turnId, value) {
  return notification('item/started', {
    threadId,
    turnId,
    item: value,
    startedAtMs: 1,
  });
}

function itemCompleted(threadId, turnId, value) {
  return notification('item/completed', {
    threadId,
    turnId,
    item: value,
    completedAtMs: 2,
  });
}

function usageNotification(threadId = 'thread-1', turnId = 'turn-1') {
  return notification('thread/tokenUsage/updated', {
    threadId,
    turnId,
    tokenUsage: {
      last: USAGE_LAST,
      total: USAGE_TOTAL,
      modelContextWindow: 200_000,
    },
  });
}

function successfulTurnEvents({
  candidate = CANDIDATE,
  threadId = 'thread-1',
  turnId = 'turn-1',
  includeAgent = true,
  duplicateAgent = false,
  itemType = null,
} = {}) {
  const user = item('user-1', 'userMessage', {
    content: [{ type: 'text', text: buildFeasibilityPrompt(FIXTURE) }],
  });
  const reasoning = item('reasoning-1', 'reasoning', {
    summary: ['must never enter transcript'],
    content: ['private reasoning'],
  });
  const agent = item('agent-1', 'agentMessage', { text: candidate });
  const events = [
    itemStarted(threadId, turnId, user),
    itemCompleted(threadId, turnId, user),
    itemStarted(threadId, turnId, reasoning),
    itemCompleted(threadId, turnId, reasoning),
  ];
  if (itemType !== null) {
    const forbidden = item('forbidden-1', itemType, { text: 'forbidden' });
    events.push(itemStarted(threadId, turnId, forbidden));
    return events;
  }
  if (includeAgent) {
    events.push(itemStarted(threadId, turnId, agent), itemCompleted(threadId, turnId, agent));
  }
  if (duplicateAgent) {
    const second = item('agent-2', 'agentMessage', { text: candidate });
    events.push(itemStarted(threadId, turnId, second), itemCompleted(threadId, turnId, second));
  }
  events.push(
    usageNotification(threadId, turnId),
    notification('turn/completed', {
      threadId,
      turn: turn(turnId, 'completed', []),
    }),
  );
  return events;
}

function handshakeSteps({ account = { type: 'chatgpt', email: null, planType: 'plus' }, pages } = {}) {
  const modelPages = pages ?? [{ data: [MODEL_ENTRY], nextCursor: null }];
  const steps = [
    {
      assertRequest(request) {
        assert.equal(request.method, 'initialize');
        assert.equal('jsonrpc' in request, false);
        assert.equal(request.params.capabilities.experimentalApi, true);
        assert.deepEqual(request.params.clientInfo, {
          name: 'canopy_genui_provider_benchmark',
          title: 'Canopy Generative UI Provider Benchmark',
          version: '1',
        });
      },
      emit: (request) => [response(request, initializeResult())],
    },
    {
      assertRequest(request) {
        assert.deepEqual(request, { method: 'initialized', params: {} });
      },
    },
    {
      assertRequest(request) {
        assert.equal(request.method, 'account/read');
        assert.deepEqual(request.params, { refreshToken: false });
      },
      emit: (request) => [response(request, { account, requiresOpenaiAuth: true })],
    },
  ];
  for (let index = 0; index < modelPages.length; index += 1) {
    steps.push({
      assertRequest(request) {
        assert.equal(request.method, 'model/list');
        assert.equal(request.params.cursor, index === 0 ? null : modelPages[index - 1].nextCursor);
        assert.equal(request.params.includeHidden, true);
      },
      emit: (request) => [response(request, modelPages[index])],
    });
  }
  return steps;
}

function successfulRunSteps({
  candidate = CANDIDATE,
  threadId = 'thread-1',
  turnId = 'turn-1',
  turnEvents,
  threadResponse = {},
  responseFirst = true,
} = {}) {
  const startedThread = thread(threadId);
  const startedTurn = turn(turnId);
  const threadResult = {
    thread: startedThread,
    model: FROZEN_IDENTITY.slug,
    modelProvider: 'openai',
    reasoningEffort: FROZEN_IDENTITY.effort,
    cwd: '/work',
    approvalPolicy: 'never',
    approvalsReviewer: 'user',
    sandbox: { type: 'externalSandbox', networkAccess: 'restricted' },
    ...threadResponse,
  };
  const threadMessages = [
    response({ id: '__placeholder__' }, threadResult),
    notification('thread/started', { thread: startedThread }),
  ];
  if (!responseFirst) threadMessages.reverse();
  return [
    {
      assertRequest(request) {
        assert.equal(request.method, 'thread/start');
        assert.equal(request.params.model, FROZEN_IDENTITY.slug);
        assert.equal(request.params.allowProviderModelFallback, false);
        assert.equal(request.params.ephemeral, true);
        assert.equal(request.params.cwd, '/work');
        assert.equal(request.params.approvalPolicy, 'never');
        assert.deepEqual(request.params.dynamicTools, []);
        assert.deepEqual(request.params.environments, []);
        assert.deepEqual(request.params.runtimeWorkspaceRoots, []);
        assert.deepEqual(request.params.selectedCapabilityRoots, []);
        assert.deepEqual(request.params.config, {
          model_reasoning_effort: FROZEN_IDENTITY.effort,
        });
      },
      emit(request) {
        return threadMessages.map((message) => message.id === '__placeholder__'
          ? { ...message, id: request.id }
          : message);
      },
    },
    {
      assertRequest(request) {
        assert.equal(request.method, 'turn/start');
        assert.equal(request.params.threadId, threadId);
        assert.equal(request.params.model, FROZEN_IDENTITY.slug);
        assert.equal(request.params.effort, FROZEN_IDENTITY.effort);
        assert.equal(request.params.cwd, '/work');
        assert.equal(request.params.approvalPolicy, 'never');
        assert.deepEqual(request.params.environments, []);
        assert.deepEqual(request.params.runtimeWorkspaceRoots, []);
        assert.deepEqual(request.params.sandboxPolicy, {
          type: 'externalSandbox',
          networkAccess: 'restricted',
        });
        assert.deepEqual(request.params.input, [{
          type: 'text',
          text: buildFeasibilityPrompt(FIXTURE),
        }]);
        assert.deepEqual(request.params.outputSchema, GENUI_CANDIDATE_SCHEMA);
      },
      emit(request) {
        return [
          response(request, { turn: startedTurn }),
          notification('turn/started', { threadId, turn: startedTurn }),
          ...(turnEvents ?? successfulTurnEvents({ candidate, threadId, turnId })),
        ];
      },
    },
  ];
}

function createScriptedProcess(steps) {
  const stdout = new PassThrough();
  const stderr = new PassThrough();
  const writes = [];
  const kills = [];
  let inputBuffer = '';
  let stepIndex = 0;
  const stdin = new Writable({
    write(chunk, _encoding, callback) {
      inputBuffer += chunk.toString('utf8');
      try {
        while (inputBuffer.includes('\n')) {
          const newline = inputBuffer.indexOf('\n');
          const line = inputBuffer.slice(0, newline);
          inputBuffer = inputBuffer.slice(newline + 1);
          if (line === '') continue;
          const request = JSON.parse(line);
          writes.push(request);
          const step = steps[stepIndex++];
          if (!step && request.method === 'turn/interrupt') continue;
          assert.ok(step, `Unexpected client message: ${line}`);
          step.assertRequest?.(request);
          const emitted = step.emit?.(request) ?? [];
          for (const message of emitted) {
            if (typeof message === 'string') stdout.write(`${message}\n`);
            else stdout.write(`${JSON.stringify(message)}\n`);
          }
          if (step.endStdout) stdout.end();
        }
        callback();
      } catch (error) {
        callback(error);
      }
    },
  });
  const child = {
    stdin,
    stdout,
    stderr,
    writes,
    kills,
    exit: Promise.resolve({ code: 0, signal: null }),
    kill(signal) {
      kills.push(signal);
      stdout.end();
      stderr.end();
      return true;
    },
  };
  return child;
}

async function createSession({ steps, frozenIdentity = FROZEN_IDENTITY, deps = {} }) {
  const child = createScriptedProcess(steps);
  const session = await createCodexAppServerSession({
    frozenIdentity,
    spawnProcess: () => child,
  }, {
    timeoutMs: 50,
    ...deps,
  });
  return { child, session };
}

async function runScript({
  handshake = handshakeSteps(),
  run = successfulRunSteps(),
  frozenIdentity = FROZEN_IDENTITY,
  deps,
} = {}) {
  const { child, session } = await createSession({
    steps: [...handshake, ...run],
    frozenIdentity,
    deps,
  });
  const result = await session.runSlot({ fixture: FIXTURE, slotId: 'slot-1' });
  return { child, session, result };
}

test('negotiates experimental API and preserves exact candidate bytes and per-turn usage', async () => {
  const { child, session, result } = await runScript();

  assert.equal(result.classification, 'success');
  assert.equal(result.candidateJson, CANDIDATE);
  assert.deepEqual(Buffer.from(result.candidateJson, 'utf8'), Buffer.from(CANDIDATE, 'utf8'));
  assert.equal(result.candidateSha256, sha256Hex(CANDIDATE));
  assert.equal(result.promptSha256, sha256Hex(buildFeasibilityPrompt(FIXTURE)));
  assert.deepEqual(result.tokenUsage, USAGE_LAST);
  assert.notDeepEqual(result.tokenUsage, USAGE_TOTAL);
  assert.deepEqual(result.identity, FROZEN_IDENTITY);
  assert.equal(result.caseId, FIXTURE.caseId);
  assert.equal(result.slotId, 'slot-1');
  assert.equal(result.transcript.some((event) => JSON.stringify(event).includes('private reasoning')), false);
  assert.equal(result.transcript.some((event) => JSON.stringify(event).includes(CANDIDATE)), false);
  assert.equal(new Set(child.writes.filter((entry) => 'id' in entry).map((entry) => entry.id)).size, 5);
  await session.close();
});

test('rejects a session configuration that omits experimental API negotiation', async () => {
  let spawned = false;
  await assert.rejects(
    () => createCodexAppServerSession({
      frozenIdentity: FROZEN_IDENTITY,
      spawnProcess: () => { spawned = true; return createScriptedProcess([]); },
      experimentalApi: false,
    }),
    (error) => error.classification === 'provider_protocol_error',
  );
  assert.equal(spawned, false);
});

test('paginates the catalog once and rejects duplicate or cyclic cursors', async () => {
  const pages = [
    { data: [], nextCursor: 'page-2' },
    { data: [MODEL_ENTRY], nextCursor: null },
  ];
  const { session } = await createSession({ steps: handshakeSteps({ pages }) });
  assert.deepEqual(session.identity, FROZEN_IDENTITY);
  await session.close();

  for (const repeatedCursor of ['page-2', 'page-1']) {
    const cyclicPages = repeatedCursor === 'page-2'
      ? [{ data: [], nextCursor: 'page-2' }, { data: [], nextCursor: 'page-2' }]
      : [{ data: [], nextCursor: 'page-1' }, { data: [], nextCursor: 'page-2' }, { data: [], nextCursor: 'page-1' }];
    await assert.rejects(
      () => createSession({ steps: handshakeSteps({ pages: cyclicPages }) }),
      (error) => error.classification === 'provider_protocol_error',
    );
  }
});

test('fails closed on missing model, unsupported effort, catalog drift, and auth drift', async () => {
  const cases = [
    {
      name: 'missing model',
      handshake: handshakeSteps({ pages: [{ data: [], nextCursor: null }] }),
      classification: 'model_not_available',
    },
    {
      name: 'unsupported effort',
      handshake: handshakeSteps({
        pages: [{ data: [{ ...MODEL_ENTRY, supportedReasoningEfforts: [] }], nextCursor: null }],
      }),
      classification: 'provider_identity_mismatch',
    },
    {
      name: 'catalog drift',
      handshake: handshakeSteps({
        pages: [{ data: [{ ...MODEL_ENTRY, description: 'drift' }], nextCursor: null }],
      }),
      classification: 'provider_identity_mismatch',
    },
    {
      name: 'auth drift',
      handshake: handshakeSteps({ account: { type: 'apiKey' } }),
      classification: 'provider_identity_mismatch',
    },
  ];
  for (const fixtureCase of cases) {
    await assert.rejects(
      () => createSession({ steps: fixtureCase.handshake }),
      (error) => error.classification === fixtureCase.classification,
      fixtureCase.name,
    );
  }
});

test('rejects model reroute and response identity drift as global failures', async () => {
  const reroute = notification('model/rerouted', {
    threadId: 'thread-1',
    turnId: 'turn-1',
    fromModel: FROZEN_IDENTITY.slug,
    toModel: 'other-model',
    reason: 'highRiskCyberActivity',
  });
  const rerouted = await runScript({
    run: successfulRunSteps({ turnEvents: [reroute] }),
  });
  assert.equal(rerouted.result.classification, 'provider_identity_mismatch');
  assert.equal(rerouted.result.globalStop, true);

  const settingsDrift = await runScript({
    run: successfulRunSteps({
      turnEvents: [notification('thread/settings/updated', {
        threadId: 'thread-1',
        threadSettings: {
          model: 'other-model',
          effort: FROZEN_IDENTITY.effort,
        },
      })],
    }),
  });
  assert.equal(settingsDrift.result.classification, 'provider_identity_mismatch');
  assert.equal(settingsDrift.result.globalStop, true);

  const drifted = await runScript({
    run: successfulRunSteps({ threadResponse: { model: 'other-model' } }),
  });
  assert.equal(drifted.result.classification, 'provider_identity_mismatch');
  assert.equal(drifted.result.globalStop, true);
});

test('correlates response IDs and rejects a notification before its response', async () => {
  const wrongIdSteps = handshakeSteps();
  wrongIdSteps[0] = {
    emit: (request) => [response({ id: request.id + 99 }, initializeResult())],
  };
  await assert.rejects(
    () => createSession({ steps: wrongIdSteps }),
    (error) => error.classification === 'provider_protocol_error',
  );

  const outOfOrder = await runScript({
    run: successfulRunSteps({ responseFirst: false }),
  });
  assert.equal(outOfOrder.result.classification, 'provider_protocol_error');
});

test('rejects wrong thread and turn IDs and completion before item completion', async () => {
  for (const events of [
    successfulTurnEvents({ threadId: 'wrong-thread' }),
    successfulTurnEvents({ turnId: 'wrong-turn' }),
    [notification('turn/completed', { threadId: 'thread-1', turn: turn('turn-1', 'completed') })],
  ]) {
    const { result } = await runScript({ run: successfulRunSteps({ turnEvents: events }) });
    assert.equal(result.classification, 'provider_protocol_error');
  }
});

test('classifies malformed JSONL, EOF, failed, interrupted, timeout, and process exit terminally', async () => {
  const malformed = await runScript({
    run: successfulRunSteps({ turnEvents: ['{malformed'] }),
  });
  assert.equal(malformed.result.classification, 'provider_protocol_error');

  const eofRun = successfulRunSteps({ turnEvents: [] });
  eofRun[1].endStdout = true;
  const eof = await runScript({ run: eofRun });
  assert.equal(eof.result.classification, 'provider_protocol_error');

  for (const status of ['failed', 'interrupted']) {
    const terminal = await runScript({
      run: successfulRunSteps({
        turnEvents: [notification('turn/completed', {
          threadId: 'thread-1',
          turn: { ...turn('turn-1', status), error: status === 'failed' ? { message: 'failed' } : null },
        })],
      }),
    });
    assert.equal(terminal.result.classification, status === 'failed' ? 'provider_failed' : 'provider_interrupted');
  }

  const timeout = await runScript({
    run: successfulRunSteps({ turnEvents: [] }),
    deps: { timeoutMs: 5 },
  });
  assert.equal(timeout.result.classification, 'provider_timeout');
  assert.equal(timeout.child.kills.length, 1);
});

test('requires exactly one completed final agent message', async () => {
  for (const events of [
    successfulTurnEvents({ includeAgent: false }),
    successfulTurnEvents({ duplicateAgent: true }),
  ]) {
    const { result } = await runScript({ run: successfulRunSteps({ turnEvents: events }) });
    assert.equal(result.classification, 'provider_protocol_error');
  }
});

test('rejects every forbidden v0.144.4 ThreadItem discriminator', async () => {
  for (const type of FORBIDDEN_ITEM_TYPES) {
    const { child, result } = await runScript({
      run: successfulRunSteps({ turnEvents: successfulTurnEvents({ itemType: type }) }),
    });
    assert.equal(result.classification, 'forbidden_provider_tool', type);
    assert.equal(result.globalStop, true, type);
    assert.equal(child.writes.some((entry) => entry.method === 'turn/interrupt'), true, type);
  }
});

test('rejects unknown item types and every v0.144.4 server-to-client request', async () => {
  const unknown = await runScript({
    run: successfulRunSteps({
      turnEvents: successfulTurnEvents({ itemType: 'futureUnknownItem' }),
    }),
  });
  assert.equal(unknown.result.classification, 'forbidden_provider_tool');

  for (const method of SERVER_REQUEST_METHODS) {
    const { result } = await runScript({
      run: successfulRunSteps({
        turnEvents: [{ id: 'server-request-1', method, params: {} }],
      }),
    });
    assert.equal(result.classification, 'forbidden_provider_tool', method);
    assert.equal(result.globalStop, true, method);
  }
});

test('preserves non-ASCII whitespace and rejects oversize or invalid UTF-8 candidates', async () => {
  const exact = '  {\n\t"label":"é・日本語"\n}\n';
  const preserved = await runScript({ run: successfulRunSteps({ candidate: exact }) });
  assert.equal(preserved.result.candidateJson, exact);
  assert.deepEqual(Buffer.from(preserved.result.candidateJson), Buffer.from(exact));

  const oversize = await runScript({
    run: successfulRunSteps({ candidate: 'x'.repeat(65_537) }),
  });
  assert.equal(oversize.result.classification, 'candidate_oversize');

  const invalid = await runScript({
    run: successfulRunSteps({ candidate: '\ud800' }),
  });
  assert.equal(invalid.result.classification, 'candidate_invalid_utf8');
});

test('serializes slots and makes close idempotent', async () => {
  const { session } = await createSession({
    steps: [...handshakeSteps(), ...successfulRunSteps()],
  });
  const first = session.runSlot({ fixture: FIXTURE, slotId: 'slot-1' });
  const second = await session.runSlot({ fixture: FIXTURE, slotId: 'slot-2' });
  assert.equal(second.classification, 'request_rejected');
  assert.equal((await first).classification, 'success');
  await session.close();
  await session.close();
});
