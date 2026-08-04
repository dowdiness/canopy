import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import {
  createReleaseManifest,
  generateReleaseManifest,
} from './create-waku-release-manifest.mjs';

const identity = {
  repository: 'dowdiness/canopy',
  headSha: '0123456789abcdef0123456789abcdef01234567',
  runId: '123456',
  runAttempt: '2',
};

test('creates a deterministic, sorted, immutable release identity', () => {
  const manifest = createReleaseManifest({
    identity,
    tools: { waku: '1.0.0-beta.8', wrangler: '4.114.0' },
    config: {
      path: 'wrangler.waku.jsonc',
      size: 2,
      sha256: 'a'.repeat(64),
    },
    files: [
      { path: 'server/index.js', size: 2, sha256: 'b'.repeat(64) },
      { path: 'public/index.html', size: 1, sha256: 'c'.repeat(64) },
      { path: 'public/é.js', size: 3, sha256: 'd'.repeat(64) },
      { path: 'public/z.js', size: 4, sha256: 'e'.repeat(64) },
    ],
  });

  assert.deepEqual(manifest.artifact.files.map((file) => file.path), [
    'public/index.html',
    'public/z.js',
    'public/é.js',
    'server/index.js',
  ]);
  assert.match(manifest.artifact.sha256, /^[0-9a-f]{64}$/);
  assert.equal(Object.isFrozen(manifest), true);
  assert.equal(Object.isFrozen(manifest.artifact.files), true);
  assert.equal(Object.isFrozen(manifest.artifact.files[0]), true);
});

test('rejects ambiguous identities, loose tool versions, and duplicate artifact paths', () => {
  const base = {
    identity,
    tools: { waku: '1.0.0-beta.8', wrangler: '4.114.0' },
    config: {
      path: 'wrangler.waku.jsonc',
      size: 2,
      sha256: 'a'.repeat(64),
    },
    files: [{ path: 'server/index.js', size: 2, sha256: 'b'.repeat(64) }],
  };
  assert.throws(() => createReleaseManifest({
    ...base,
    identity: { ...identity, runAttempt: '' },
  }));
  assert.throws(() => createReleaseManifest({
    ...base,
    tools: { ...base.tools, wrangler: '^4.114.0' },
  }));
  assert.throws(() => createReleaseManifest({
    ...base,
    files: [...base.files, { ...base.files[0] }],
  }));
  assert.throws(() => createReleaseManifest({
    ...base,
    files: [{ ...base.files[0], path: 'server\\index.js' }],
  }));
});

test('hashes the generated dist and writes the manifest outside the artifact', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'canopy-waku-manifest-'));
  try {
    await mkdir(path.join(directory, 'dist', 'public'), { recursive: true });
    await mkdir(path.join(directory, 'dist', 'server'), { recursive: true });
    await writeFile(path.join(directory, 'dist', 'public', 'index.html'), '<main>Canopy</main>');
    await writeFile(path.join(directory, 'dist', 'server', 'index.js'), 'export default {}');
    await writeFile(path.join(directory, 'package.json'), JSON.stringify({
      dependencies: { waku: '1.0.0-beta.8' },
      devDependencies: { wrangler: '4.114.0' },
    }));
    await writeFile(path.join(directory, 'wrangler.waku.jsonc'), '{}');
    const outputPath = path.join(directory, 'release', 'manifest.json');

    const manifest = await generateReleaseManifest({
      projectDirectory: directory,
      outputPath,
      identity,
    });
    const persisted = JSON.parse(await readFile(outputPath, 'utf8'));

    assert.deepEqual(persisted, manifest);
    assert.deepEqual(persisted.artifact.files.map((file) => file.path), [
      'public/index.html',
      'server/index.js',
    ]);
    assert.equal(persisted.artifact.files.some((file) => file.path.includes('release')), false);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
