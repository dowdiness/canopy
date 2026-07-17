import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, realpath, stat, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, join } from 'node:path';
import test from 'node:test';

import {
  createPrivateRun,
  parseMinimalProviderArgs,
  writeTerminalResult,
} from './run-genui-minimal-provider-e2e.mjs';
import { GENUI_PROVIDER_SETTINGS } from '../src/genui-feasibility-provider.js';

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
