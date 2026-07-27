import { createHash } from 'node:crypto';
import {
  mkdir,
  readFile,
  readdir,
  writeFile,
} from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RELEASE_SCHEMA = 'canopy.waku-release.v1';

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function requireIdentity(identity) {
  if (!/^[0-9a-f]{40}$/.test(identity.headSha)) {
    throw new Error('GITHUB_SHA must be a full 40-character lowercase commit SHA.');
  }
  if (!/^\d+$/.test(identity.runId) || identity.runId === '0') {
    throw new Error('GITHUB_RUN_ID must be a positive integer.');
  }
  if (!/^\d+$/.test(identity.runAttempt) || identity.runAttempt === '0') {
    throw new Error('GITHUB_RUN_ATTEMPT must be a positive integer.');
  }
  if (!/^[^/\s]+\/[^/\s]+$/.test(identity.repository)) {
    throw new Error('GITHUB_REPOSITORY must be an owner/repository pair.');
  }
}

export function createReleaseManifest({ identity, tools, config, files }) {
  requireIdentity(identity);
  if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(tools.waku) ||
    !/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(tools.wrangler)) {
    throw new Error('Waku and Wrangler must use exact package versions.');
  }
  if (config.path !== 'wrangler.waku.jsonc' ||
    !Number.isSafeInteger(config.size) || config.size < 1 ||
    !/^[0-9a-f]{64}$/.test(config.sha256)) {
    throw new Error('The Waku Wrangler config metadata is invalid.');
  }
  if (files.length === 0) throw new Error('The Waku dist artifact is empty.');

  const orderedFiles = files
    .map((file) => Object.freeze({ ...file }))
    .sort((left, right) => left.path < right.path ? -1 : left.path > right.path ? 1 : 0);
  if (new Set(orderedFiles.map((file) => file.path)).size !== orderedFiles.length) {
    throw new Error('The Waku dist artifact contains duplicate paths.');
  }
  for (const file of orderedFiles) {
    if (file.path === '' || file.path.startsWith('/') || file.path.includes('\\') ||
      file.path.split('/').includes('..') ||
      !Number.isSafeInteger(file.size) || file.size < 0 ||
      !/^[0-9a-f]{64}$/.test(file.sha256)) {
      throw new Error('The Waku dist artifact contains invalid file metadata.');
    }
  }

  const artifactSha256 = sha256(JSON.stringify(orderedFiles));
  return Object.freeze({
    schema: RELEASE_SCHEMA,
    repository: identity.repository,
    headSha: identity.headSha,
    runId: identity.runId,
    runAttempt: identity.runAttempt,
    tools: Object.freeze({ ...tools }),
    config: Object.freeze({ ...config }),
    artifact: Object.freeze({
      root: 'dist',
      sha256: artifactSha256,
      files: Object.freeze(orderedFiles),
    }),
  });
}

async function collectFiles(root, relative = '') {
  const directory = path.join(root, relative);
  const entries = await readdir(directory, { withFileTypes: true });
  entries.sort((left, right) => left.name < right.name ? -1 : left.name > right.name ? 1 : 0);
  const files = [];
  for (const entry of entries) {
    const relativePath = path.posix.join(relative.split(path.sep).join('/'), entry.name);
    if (entry.isDirectory()) {
      files.push(...await collectFiles(root, relativePath));
    } else if (entry.isFile()) {
      const content = await readFile(path.join(root, relativePath));
      files.push({
        path: relativePath,
        size: content.byteLength,
        sha256: sha256(content),
      });
    } else {
      throw new Error(`Unsupported dist entry: ${relativePath}`);
    }
  }
  return files;
}

export async function generateReleaseManifest({ projectDirectory, outputPath, identity }) {
  const packageJson = JSON.parse(await readFile(
    path.join(projectDirectory, 'package.json'),
    'utf8',
  ));
  const configContent = await readFile(
    path.join(projectDirectory, 'wrangler.waku.jsonc'),
  );
  const manifest = createReleaseManifest({
    identity,
    tools: {
      waku: packageJson.dependencies?.waku,
      wrangler: packageJson.devDependencies?.wrangler,
    },
    config: {
      path: 'wrangler.waku.jsonc',
      size: configContent.byteLength,
      sha256: sha256(configContent),
    },
    files: await collectFiles(path.join(projectDirectory, 'dist')),
  });
  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(manifest, null, 2)}\n`, {
    encoding: 'utf8',
    flag: 'wx',
  });
  return manifest;
}

async function main() {
  if (process.argv.length !== 3) {
    throw new Error(
      'Usage: node scripts/create-waku-release-manifest.mjs <output-path>',
    );
  }
  const projectDirectory = path.resolve(
    path.dirname(fileURLToPath(import.meta.url)),
    '..',
  );
  await generateReleaseManifest({
    projectDirectory,
    outputPath: path.resolve(process.argv[2]),
    identity: {
      repository: process.env.GITHUB_REPOSITORY ?? '',
      headSha: process.env.GITHUB_SHA ?? '',
      runId: process.env.GITHUB_RUN_ID ?? '',
      runAttempt: process.env.GITHUB_RUN_ATTEMPT ?? '',
    },
  });
}

if (process.argv[1] !== undefined &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
