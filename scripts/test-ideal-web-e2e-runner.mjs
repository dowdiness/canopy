import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const runner = resolve(root, 'scripts/test-ideal-web-e2e.sh');

function list(args) {
  const result = spawnSync('bash', [runner, ...args], {
    cwd: root,
    encoding: 'utf8',
    timeout: 60_000,
    maxBuffer: 10 * 1024 * 1024,
  });
  assert.ifError(result.error);
  return result;
}

function files(result) {
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const report = JSON.parse(result.stdout.slice(result.stdout.indexOf('{')));
  return report.suites.map((suite) => suite.file).sort();
}

const options = ['--list', '--reporter=json'];

test('an explicit spec selects only that file in either argument order', () => {
  const expected = ['seed.spec.ts'];
  assert.deepEqual(files(list(['e2e/seed.spec.ts', ...options])), expected);
  assert.deepEqual(files(list([...options, 'e2e/seed.spec.ts'])), expected);
});

test('an unmatched spec fails in either argument order', () => {
  for (const args of [
    ['e2e/does-not-exist.spec.ts', ...options],
    [...options, 'e2e/does-not-exist.spec.ts'],
  ]) {
    const result = list(args);
    assert.equal(result.status, 1, result.stdout + result.stderr);
    const report = JSON.parse(result.stdout.slice(result.stdout.indexOf('{')));
    assert.deepEqual(report.suites, []);
  }
});

test('the functional selection excludes performance specs', () => {
  const selected = files(list(options));
  assert.ok(selected.includes('seed.spec.ts'));
  assert.ok(!selected.includes('editor-response.perf.spec.ts'));
});

test('explicit performance selection cannot enter the functional runner', () => {
  const result = list([...options, 'e2e/editor-response.perf.spec.ts']);
  assert.equal(result.status, 1, result.stdout + result.stderr);
  const report = JSON.parse(result.stdout.slice(result.stdout.indexOf('{')));
  assert.deepEqual(report.suites, []);
});
