import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, readdir, realpath, stat, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, join } from 'node:path';
import { EventEmitter } from 'node:events';
import { spawn } from 'node:child_process';
import { PassThrough } from 'node:stream';
import test from 'node:test';

import {
  classifyCandidate,
  createPrivateRun,
  parseMinimalProviderArgs,
  runMinimalProviderE2E,
  runProviderAttempt,
  writeTerminalResult,
} from './run-genui-minimal-provider-e2e.mjs';
import { runProviderProcess } from './genui-minimal-provider-process.mjs';
import { GENUI_PROVIDER_SETTINGS } from '../src/genui-feasibility-provider.js';
import { recordedFeasibilityCandidateJson } from '../src/genui-recorded-candidates.js';

const fixtureId = 'orders-pending-attention';

async function sandbox() {
  const root = await mkdtemp(join(tmpdir(), 'canopy-minimal-e2e-'));
  const repositoryRoot = await realpath(join(import.meta.dirname, '../../..'));
  return { root, repositoryRoot };
}

function argv(outputDir, extra = []) {
  return ['--fixture', fixtureId, '--model', 'test-model', '--output-dir', outputDir, ...extra];
}

function configurationError(fn) {
  assert.throws(fn, error => error.code === 'configuration_error' && error.message.length > 0);
}

for (const bad of [
  [], ['--fixture', fixtureId],
  ['--fixture', fixtureId, '--model', ''],
  ['--fixture', 'missing', '--model', 'm', '--output-dir', '/tmp/x'],
  ['--fixture', fixtureId, '--fixture', fixtureId, '--model', 'm', '--output-dir', '/tmp/x'],
  ['--fixture', fixtureId, '--model', 'm', '--output-dir', '/tmp/x', '--wat', 'x'],
  ['--fixture', fixtureId, '--model', 'm', '--output-dir', '/tmp/x', '--timeout-ms', '0'],
  ['--fixture', fixtureId, '--model', 'm', '--output-dir', '/tmp/x', '--timeout-ms', '1.5'],
]) {
  test(`CLI rejects ${JSON.stringify(bad)}`, () => configurationError(() => parseMinimalProviderArgs(bad, { repositoryRoot: '/repo' })));
}

test('CLI applies default timeout', () => {
  const parsed = parseMinimalProviderArgs(argv('/tmp/new-run'), { repositoryRoot: '/repo' });
  assert.equal(parsed.timeoutMs, GENUI_PROVIDER_SETTINGS.timeoutMs);
});

test('output path accepts one canonical external child and creates private artifacts', async () => {
  const { root, repositoryRoot } = await sandbox();
  const outputDir = join(root, 'run');
  const options = parseMinimalProviderArgs(argv(outputDir), { repositoryRoot });
  const run = await createPrivateRun(options, { repositoryRoot, now: () => '2026-07-17T00:00:00.000Z' });
  assert.equal((await stat(outputDir)).mode & 0o777, 0o700);
  for (const path of [run.paths.request, run.paths.providerEvents]) assert.equal((await stat(path)).mode & 0o777, 0o600);
  const request = JSON.parse(await readFile(run.paths.request, 'utf8'));
  assert.equal(request.fixtureId, fixtureId);
  assert.equal(request.model, 'test-model');
  assert.equal(request.expectedProviderInvocationCount, 1);
  assert.equal(typeof request.promptSha256, 'string');
  assert.equal(typeof request.schemaSha256, 'string');
  assert.equal(Object.hasOwn(request, 'candidateJson'), false);
  await writeTerminalResult(run, { classification: 'provider_failed', safeMessage: 'test' });
  assert.equal((await stat(run.paths.result)).mode & 0o777, 0o600);
  await assert.rejects(() => writeTerminalResult(run, { classification: 'provider_failed' }));
});

test('output path rejects aliases and unsafe parents before run creation', async () => {
  const { root, repositoryRoot } = await sandbox();
  const existing = join(root, 'existing');
  await mkdir(existing);
  const alias = join(root, 'repo-link');
  await symlink(repositoryRoot, alias);
  for (const outputDir of ['relative', existing, join(root, 'missing', 'run'), join(repositoryRoot, 'run'), `${root}/../${basename(root)}/alias`, join(alias, 'run')]) {
    const options = parseMinimalProviderArgs(argv(outputDir), { repositoryRoot });
    await assert.rejects(() => createPrivateRun(options, { repositoryRoot }), error => error.code === 'configuration_error');
  }
});

test('provider lifecycle performs exactly one fixed Codex invocation', async () => {
  const { root, repositoryRoot } = await sandbox();
  const options = parseMinimalProviderArgs(argv(join(root, 'run')), { repositoryRoot });
  const run = await createPrivateRun(options, { repositoryRoot });
  const calls = [];
  const monotonicTimes = [100, 125];
  const child = new EventEmitter();
  child.pid = 12345;
  child.stdin = new PassThrough();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.kill = () => true;
  const resultPromise = runProviderAttempt(run, options, {
    spawnProcess(command, args, spawnOptions) {
      calls.push({ command, args, spawnOptions });
      queueMicrotask(() => {
        child.stdout.end();
        child.stderr.end();
        child.emit('exit', 0, null);
      });
      return child;
    },
    providerInvocation: { command: 'codex', prefixArgs: [] },
    monotonicNow: () => monotonicTimes.shift(),
  });
  const result = await resultPromise;
  assert.equal(result.classification, 'success');
  assert.equal(result.invocationCount, 1);
  assert.equal(result.providerDurationMs, 25);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].command, 'codex');
  assert.equal(calls[0].args.filter(value => value === 'exec').length, 1);
  for (const flag of ['--json', '--ephemeral', '--ignore-user-config', '--ignore-rules', '--skip-git-repo-check', '--sandbox', '--model', '--output-schema', '--output-last-message']) {
    assert.equal(calls[0].args.filter(value => value === flag).length, 1);
  }
  assert.equal(calls[0].args.at(-1), '-');
  assert.equal(calls[0].spawnOptions.cwd, run.paths.work);
});

test('provider event artifact write failures remain terminal', async () => {
  const { root, repositoryRoot } = await sandbox();
  const options = parseMinimalProviderArgs(argv(join(root, 'run')), { repositoryRoot });
  const run = await createPrivateRun(options, { repositoryRoot });
  const child = new EventEmitter();
  child.pid = 24680;
  child.stdin = new PassThrough();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.kill = () => true;
  const eventsStream = new PassThrough();
  await assert.rejects(runProviderProcess(run, options, {
    spawnProcess() {
      queueMicrotask(() => {
        eventsStream.destroy(new Error('artifact write failed'));
        child.stdout.end('{}\n');
        child.emit('exit', 0, null);
      });
      return child;
    },
    providerInvocation: { command: 'codex', prefixArgs: [] },
    eventsStream,
    outputSettleMs: 5,
  }), /artifact write failed/);
});

test('provider timeout kills the process group and settles inherited output', { timeout: 15_000 }, async () => {
  const { root, repositoryRoot } = await sandbox();
  const options = parseMinimalProviderArgs(argv(join(root, 'run'), ['--timeout-ms', '1']), { repositoryRoot });
  const run = await createPrivateRun(options, { repositoryRoot });
  const child = new EventEmitter();
  child.pid = 24680;
  child.stdin = new PassThrough();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.kill = () => true;
  const signals = [];
  const startedAt = Date.now();
  const observed = await runProviderAttempt(run, options, {
    spawnProcess: () => child,
    providerInvocation: { command: 'codex', prefixArgs: [] },
    platform: 'linux',
    terminationGraceMs: 10,
    outputSettleMs: 10,
    kill(pid, signal) {
      signals.push([pid, signal]);
      if (signal === 'SIGKILL') child.emit('exit', null, signal);
    },
  });
  assert.equal(observed.classification, 'provider_timeout');
  assert.deepEqual(signals, [[-24680, 'SIGTERM'], [-24680, 'SIGKILL']]);
  assert.ok(Date.now() - startedAt < 1_000, 'injected lifecycle bounds must avoid the production grace period');
});
test('timeout kills a live provider grandchild after bounded escalation', { timeout: 15_000 }, async () => {
  if (process.platform === 'win32') return;
  const { root, repositoryRoot } = await sandbox();
  const scriptPath = join(root, 'provider-tree.mjs');
  const heartbeatPath = join(root, 'heartbeat');
  const pidPath = join(root, 'grandchild-pid');
  await writeFile(scriptPath, `
    import { spawn } from 'node:child_process';
    import { writeFileSync } from 'node:fs';
    const heartbeat = process.argv[2];
    const pidFile = process.argv[3];
    const grandchild = spawn(process.execPath, ['-e', \`
      const { appendFileSync } = require('node:fs');
      process.on('SIGTERM', () => {});
      setInterval(() => appendFileSync(process.argv[1], '.'), 20);
    \`, heartbeat], { stdio: 'ignore' });
    writeFileSync(pidFile, String(grandchild.pid));
    process.on('SIGTERM', () => {});
    setInterval(() => {}, 1000);
  `);
  const options = parseMinimalProviderArgs(argv(join(root, 'run'), ['--timeout-ms', '250']), { repositoryRoot });
  const run = await createPrivateRun(options, { repositoryRoot });
  let spawnCount = 0;
  const observed = await runProviderAttempt(run, options, {
    spawnProcess(_command, _args, spawnOptions) {
      spawnCount += 1;
      return spawn(process.execPath, [scriptPath, heartbeatPath, pidPath], spawnOptions);
    },
    providerInvocation: { command: 'codex', prefixArgs: [] },
    terminationGraceMs: 100,
  });
  assert.equal(observed.classification, 'provider_timeout');
  assert.equal(spawnCount, 1);
  assert.ok((await readFile(heartbeatPath, 'utf8')).length > 0);
  const grandchildPid = Number(await readFile(pidPath, 'utf8'));
  await new Promise(resolve => setTimeout(resolve, 100));
  assert.throws(() => process.kill(grandchildPid, 0), error => error.code === 'ESRCH');
});

test('timeout force-kills descendants after the provider parent exits', { timeout: 15_000 }, async () => {
  if (process.platform === 'win32') return;
  const { root, repositoryRoot } = await sandbox();
  const scriptPath = join(root, 'provider-parent-exits.mjs');
  const heartbeatPath = join(root, 'parent-exits-heartbeat');
  const pidPath = join(root, 'parent-exits-grandchild-pid');
  await writeFile(scriptPath, `
    import { spawn } from 'node:child_process';
    import { writeFileSync } from 'node:fs';
    const heartbeat = process.argv[2];
    const pidFile = process.argv[3];
    const grandchild = spawn(process.execPath, ['-e', \`
      const { appendFileSync } = require('node:fs');
      process.on('SIGTERM', () => {});
      setInterval(() => appendFileSync(process.argv[1], '.'), 20);
    \`, heartbeat], { stdio: 'ignore' });
    writeFileSync(pidFile, String(grandchild.pid));
    process.on('SIGTERM', () => process.exit(0));
    setInterval(() => {}, 1000);
  `);
  const options = parseMinimalProviderArgs(argv(join(root, 'run'), ['--timeout-ms', '250']), { repositoryRoot });
  const run = await createPrivateRun(options, { repositoryRoot });
  const observed = await runProviderAttempt(run, options, {
    spawnProcess(_command, _args, spawnOptions) {
      return spawn(process.execPath, [scriptPath, heartbeatPath, pidPath], spawnOptions);
    },
    providerInvocation: { command: 'codex', prefixArgs: [] },
    terminationGraceMs: 100,
  });
  assert.equal(observed.classification, 'provider_timeout');
  assert.ok((await readFile(heartbeatPath, 'utf8')).length > 0);
  const grandchildPid = Number(await readFile(pidPath, 'utf8'));
  await new Promise(resolve => setTimeout(resolve, 100));
  try {
    assert.throws(() => process.kill(grandchildPid, 0), error => error.code === 'ESRCH');
  } finally {
    try { process.kill(grandchildPid, 'SIGKILL'); } catch {}
  }
});


test('provider interruption terminates without retry', async () => {
  const { root, repositoryRoot } = await sandbox();
  const options = parseMinimalProviderArgs(argv(join(root, 'run')), { repositoryRoot });
  const run = await createPrivateRun(options, { repositoryRoot });
  const child = new EventEmitter();
  child.pid = 13579;
  child.stdin = new PassThrough();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.kill = () => true;
  const attempt = runProviderAttempt(run, options, {
    spawnProcess: () => child,
    providerInvocation: { command: 'codex', prefixArgs: [] },
    platform: 'linux',
    kill(_pid, signal) {
      child.stdout.end();
      child.stderr.end();
      child.emit('exit', null, signal);
    },
  });
  setTimeout(() => process.emit('SIGINT'), 10);
  const observed = await attempt;
  assert.equal(observed.classification, 'provider_failed');
  assert.equal(observed.interrupted, true);
  assert.equal(observed.invocationCount, 1);
});

test('Windows timeout awaits forced tree termination after the child exits', async () => {
  const { root, repositoryRoot } = await sandbox();
  const options = parseMinimalProviderArgs(argv(join(root, 'run'), ['--timeout-ms', '1']), { repositoryRoot });
  const run = await createPrivateRun(options, { repositoryRoot });
  const child = new EventEmitter();
  child.pid = 97531;
  child.stdin = new PassThrough();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.kill = () => true;
  let resolveForcedTermination;
  const forcedTermination = new Promise(resolve => { resolveForcedTermination = resolve; });
  let completed = false;
  const attempt = runProviderAttempt(run, options, {
    spawnProcess: () => child,
    providerInvocation: { command: 'codex', prefixArgs: [] },
    platform: 'win32',
    terminationGraceMs: 5,
    outputSettleMs: 5,
    terminateWindowsTree(_pid, force) {
      if (!force) {
        child.stdout.end();
        child.stderr.end();
        queueMicrotask(() => child.emit('exit', 0, null));
        return Promise.resolve();
      }
      return forcedTermination;
    },
  }).then(result => {
    completed = true;
    return result;
  });
  await new Promise(resolve => setTimeout(resolve, 20));
  assert.equal(completed, false);
  resolveForcedTermination();
  const observed = await attempt;
  assert.equal(observed.classification, 'provider_timeout');
});

test('Windows forced tree termination has a bounded wait', { timeout: 15_000 }, async () => {
  const { root, repositoryRoot } = await sandbox();
  const options = parseMinimalProviderArgs(argv(join(root, 'run'), ['--timeout-ms', '1']), { repositoryRoot });
  const run = await createPrivateRun(options, { repositoryRoot });
  const child = new EventEmitter();
  child.pid = 13579;
  child.stdin = new PassThrough();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.kill = () => true;
  const startedAt = Date.now();
  const observed = await runProviderAttempt(run, options, {
    spawnProcess: () => child,
    providerInvocation: { command: 'codex', prefixArgs: [] },
    platform: 'win32',
    terminationGraceMs: 5,
    forceTerminationMs: 5,
    outputSettleMs: 5,
    terminateWindowsTree(_pid, force) {
      if (!force) {
        child.stdout.end();
        child.stderr.end();
        queueMicrotask(() => child.emit('exit', 0, null));
        return Promise.resolve();
      }
      return new Promise(() => {});
    },
  });
  assert.equal(observed.classification, 'provider_timeout');
  assert.ok(Date.now() - startedAt < 1_000);
});

test('provider early stdin close is classified without an uncaught EPIPE', { timeout: 15_000 }, async () => {
  const { root, repositoryRoot } = await sandbox();
  const providerPath = join(root, 'provider-closes-stdin.mjs');
  await writeFile(providerPath, 'process.stdin.destroy(); process.exit(2);');
  const options = parseMinimalProviderArgs(argv(join(root, 'run')), { repositoryRoot });
  const run = await createPrivateRun(options, { repositoryRoot });
  run.request.prompt = 'x'.repeat(1_048_576);
  const observed = await runProviderAttempt(run, options, {
    providerInvocation: { command: process.execPath, prefixArgs: [providerPath] },
  });
  assert.equal(observed.classification, 'provider_failed');
  assert.equal(observed.exitCode, 2);
  assert.equal(observed.invocationCount, 1);
});

test('provider stderr is UTF-8 safe and bounded by retained bytes', async () => {
  const { root, repositoryRoot } = await sandbox();
  const options = parseMinimalProviderArgs(argv(join(root, 'run')), { repositoryRoot });
  const run = await createPrivateRun(options, { repositoryRoot });
  const child = new EventEmitter();
  child.pid = 86420;
  child.stdin = new PassThrough();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.kill = () => true;
  const euro = Buffer.from('€');
  const observed = await runProviderAttempt(run, options, {
    spawnProcess() {
      queueMicrotask(() => {
        child.stderr.write(euro.subarray(0, 1));
        child.stderr.write(euro.subarray(1));
        child.stderr.write('x'.repeat(16_380));
        child.stderr.write(euro.subarray(0, 1));
        child.stderr.write(euro.subarray(1));
        child.stdout.end();
        child.stderr.end();
        child.emit('exit', 2, null);
      });
      return child;
    },
    providerInvocation: { command: 'codex', prefixArgs: [] },
  });
  assert.equal(observed.classification, 'provider_failed');
  assert.equal(observed.stderr.startsWith('€'), true);
  assert.ok(Buffer.byteLength(observed.stderr) <= 16_384);
  assert.equal(observed.stderr.includes('\uFFFD'), false);
  assert.equal(observed.stderrTruncated, true);
});

test('candidate boundaries distinguish missing, invalid UTF-8, malformed, and oversize output', async () => {
  const { root } = await sandbox();
  const candidatePath = join(root, 'candidate.json');
  assert.equal((await classifyCandidate(candidatePath, 65_536)).classification, 'provider_failed');
  await writeFile(candidatePath, Buffer.from([0xff]));
  assert.equal((await classifyCandidate(candidatePath, 65_536)).classification, 'candidate_invalid');
  await writeFile(candidatePath, '{');
  assert.equal((await classifyCandidate(candidatePath, 65_536)).classification, 'candidate_invalid');
  await writeFile(candidatePath, ' '.repeat(65_535) + '0');
  assert.equal((await classifyCandidate(candidatePath, 65_536)).bytes.length, 65_536);
  await writeFile(candidatePath, ' '.repeat(65_536) + '0');
  assert.equal((await classifyCandidate(candidatePath, 65_536)).classification, 'candidate_oversize');
});

async function runWithBrowserOutcome(outcome) {
  const { root, repositoryRoot } = await sandbox();
  const outputDir = join(root, 'run');
  const options = parseMinimalProviderArgs(argv(outputDir), { repositoryRoot });
  const child = new EventEmitter();
  child.pid = 12345;
  child.stdin = new PassThrough();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.kill = () => true;
  const observed = await runMinimalProviderE2E(options, {
    repositoryRoot,
    runBrowser: async () => outcome,
    spawnProcess(_command, args) {
      queueMicrotask(async () => {
        const outputFlag = args.indexOf('--output-last-message');
        await writeFile(args[outputFlag + 1], '{}');
        child.stdout.end();
        child.stderr.end();
        child.emit('exit', 0, null);
      });
      return child;
    },
  });
  return observed;
}

test('MoonBit classifications and failed success predicates remain terminal failures', async () => {
  const schemaInvalid = { classification: 'candidate_validation_error', diagnostics: ['schema'] };
  assert.deepEqual((await runWithBrowserOutcome(schemaInvalid)).result.diagnostics, ['schema']);
  for (const outcome of [
    { classification: 'success', rubric: { passed: false }, session: { success: true } },
    { classification: 'success', rubric: { passed: true }, session: { success: false } },
  ]) {
    const observed = await runWithBrowserOutcome(outcome);
    assert.equal(observed.exitCode, 1);
    assert.deepEqual(observed.result.rubric, outcome.rubric);
    assert.deepEqual(observed.result.session, outcome.session);
  }
});

test('fake provider traverses real browser and MoonBit commit path', { timeout: 360_000 }, async () => {
  const { root, repositoryRoot } = await sandbox();
  const fakeProvider = join(root, 'fake-provider.mjs');
  const candidateJson = recordedFeasibilityCandidateJson(fixtureId);
  await writeFile(fakeProvider, [
    "import { writeFile } from 'node:fs/promises';",
    "const outputFlag = process.argv.indexOf('--output-last-message');",
    "if (outputFlag < 0) process.exit(2);",
    `await writeFile(process.argv[outputFlag + 1], ${JSON.stringify(candidateJson)});`,
    "process.stdout.write(JSON.stringify({ type: 'turn.completed' }) + '\\n');",
  ].join('\n'));
  const outputDir = join(root, 'run');
  const options = parseMinimalProviderArgs(argv(outputDir, ['--timeout-ms', '300000']), { repositoryRoot });
  const observed = await runMinimalProviderE2E(options, {
    repositoryRoot,
    providerInvocation: { command: process.execPath, prefixArgs: [fakeProvider] },
  });
  assert.equal(observed.exitCode, 0);
  assert.equal(observed.result.classification, 'success');
  assert.equal(observed.result.rubric.passed, true);
  assert.equal(observed.result.session.success, true);
  assert.deepEqual((await readdir(outputDir)).sort(), ['candidate.json', 'provider-events.jsonl', 'request.json', 'result.json']);
});
