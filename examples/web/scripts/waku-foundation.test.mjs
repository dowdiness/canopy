import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

import {
  moonbitBuildCoordinator,
  moonbitImportIds,
  moonbitModules,
} from '../moonbit-artifacts.mjs';
import {
  installMoonbitOutputReload,
  moonbitPlugin,
} from '../vite-plugin-moonbit.ts';
import { inspectWakuBundles } from './check-waku-bundles.mjs';
import {
  fetchWakuBuildPreviewWithRetry,
  isWakuBuildPreviewRequest,
} from './waku-build-fetch-retry.mjs';

const expectedModules = [
  ['@moonbit/crdt-lambda', '../..', '_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.js'],
  ['@moonbit/crdt-json', '../..', '_build/js/release/build/dowdiness/canopy/ffi/json/json.js'],
  ['@moonbit/crdt-markdown', '../..', '_build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.js'],
  ['@moonbit/crdt-jsx', '../..', '_build/js/release/build/dowdiness/canopy/ffi/jsx/jsx.js'],
  ['@moonbit/graphviz', '../..', '_build/js/release/build/dowdiness/graphviz/browser/browser.js'],
];

test('keeps the five generated MoonBit virtual IDs and output paths stable', () => {
  assert.deepEqual(
    moonbitModules.map(({ name, path, output }) => [name, path, output]),
    expectedModules,
  );
  assert.deepEqual(moonbitImportIds, expectedModules.map(([name]) => name));
});

test('keeps the Waku generated-module probe client-only and complete', () => {
  const probe = fs.readFileSync(
    new URL('../src/shared/browser/moonbit-client-probe.tsx', import.meta.url),
    'utf8',
  );
  assert.match(probe, /^'use client';/);
  for (const id of moonbitImportIds) {
    assert.match(probe, new RegExp(`import\\(['"]${id}['"]\\)`));
  }
});

test('coordinates one root MoonBit build for all virtual modules', () => {
  assert.deepEqual(moonbitBuildCoordinator, {
    path: '../..',
    buildFlags: [],
  });
  assert.equal(new Set(moonbitModules.map(({ path }) => path)).size, 1);
});

test('rejects a missing MoonBit build coordinator with a clear error', () => {
  assert.throws(
    () => moonbitPlugin({ modules: [] }),
    { message: '[MoonBit] A build coordinator is required' },
  );
});

test('invalidates generated importers and fully reloads after an output write', async () => {
  const changedPath = '/repo/_build/json.js';
  const generatedModule = { importers: new Set([{ id: 'client-importer' }]) };
  const invalidated = [];
  const messages = [];
  let onChange;
  const server = {
    watcher: {
      add: () => {},
      on: (event, handler) => {
        if (event === 'change') onChange = handler;
      },
    },
    moduleGraph: {
      getModuleById: (id) => id === '@moonbit/crdt-json' ? generatedModule : undefined,
      invalidateModule: (module) => invalidated.push(module),
    },
    ws: { send: (message) => messages.push(message) },
  };

  installMoonbitOutputReload(server, [{
    name: '@moonbit/crdt-json',
    absoluteOutputPath: changedPath,
  }]);
  await onChange(changedPath);

  assert.deepEqual(invalidated, [generatedModule, { id: 'client-importer' }]);
  assert.deepEqual(messages, [{ type: 'full-reload', path: '*' }]);
});

test('detects each generated runtime fingerprint in a server/RSC bundle', () => {
  const bundles = [
    ['crdt-lambda', '@moonbit/crdt-lambda', 'assemble_lambda_handle'],
    ['crdt-json', '@moonbit/crdt-json', 'assemble_json_handle'],
    ['crdt-markdown', '@moonbit/crdt-markdown', 'assemble_markdown_handle'],
    ['crdt-jsx', '@moonbit/crdt-jsx', 'jsx_session_new'],
    ['graphviz', '@moonbit/graphviz', 'render_dot_to_svg'],
  ];
  const result = inspectWakuBundles({
    serverBundles: bundles.map(([name, , fingerprint]) => ({
      name: `dist/server/ssr/${name}.js`,
      source: fingerprint,
    })),
    clientBundles: bundles.map(([name, , fingerprint]) => ({
      name: `${name}-a.js`,
      source: fingerprint,
    })),
  });
  assert.deepEqual(
    result.serverLeaks,
    bundles.map(([name, id]) => ({ id, file: `dist/server/ssr/${name}.js` })),
  );
  assert.deepEqual(result.missingClientModules, []);
});

test('rejects the development-only Mini-ML AST Grep request in production bundles', () => {
  const result = inspectWakuBundles({
    serverBundles: [],
    clientBundles: [{
      name: 'dist/public/assets/ml-a.js',
      source: 'fetch("/api/ast-grep")',
    }],
  });
  assert.deepEqual(result.productionClientArtifactLeaks, [{
    capability: 'Mini-ML AST Grep request',
    fingerprint: '/api/ast-grep',
    file: 'dist/public/assets/ml-a.js',
  }]);
});

test('rejects Resume relay requests, secrets, and middleware in production bundles', () => {
  const fingerprints = [
    ['Resume chat request', '/api/pi-resume-chat'],
    ['Resume chat secret', 'DEEPSEEK_API_KEY'],
    ['Resume chat relay', 'pi-resume-chat-relay'],
  ];
  const source = fingerprints.map(([, fingerprint]) => fingerprint).join('\n');
  const result = inspectWakuBundles({
    serverBundles: [{ name: 'dist/server/worker.js', source }],
    clientBundles: [{ name: 'dist/public/assets/resume-a.js', source }],
  });
  assert.deepEqual(result.productionClientArtifactLeaks, fingerprints.map(([
    capability,
    fingerprint,
  ]) => ({
    capability,
    fingerprint,
    file: 'dist/public/assets/resume-a.js',
  })));
  assert.deepEqual(result.productionServerArtifactLeaks, fingerprints.map(([
    capability,
    fingerprint,
  ]) => ({
    capability,
    fingerprint,
    file: 'dist/server/worker.js',
  })));
});

test('rejects GenUI live-study endpoints, hooks, and provider markers in production bundles', () => {
  const fingerprints = [
    ['GenUI live feasibility request', '/api/genui-feasibility'],
    ['GenUI feasibility development hook', '__canopyGenUiFeasibilityTest'],
    ['GenUI development hook', '__canopyGenUiTest'],
    ['GenUI local provider URL', '127.0.0.1:11434'],
    ['GenUI local provider model', 'GENUI_OLLAMA_MODEL'],
  ];
  const source = fingerprints.map(([, fingerprint]) => fingerprint).join('\n');
  const result = inspectWakuBundles({
    serverBundles: [{ name: 'dist/server/worker.js', source }],
    clientBundles: [{ name: 'dist/public/assets/genui-a.js', source }],
  });
  const expected = (file) => fingerprints.map(([capability, fingerprint]) => ({
    capability,
    fingerprint,
    file,
  }));
  assert.deepEqual(
    result.productionClientArtifactLeaks,
    expected('dist/public/assets/genui-a.js'),
  );
  assert.deepEqual(
    result.productionServerArtifactLeaks,
    expected('dist/server/worker.js'),
  );
});

test('rejects Memo development and provider capabilities outside the shared Lambda artifact', () => {
  const providerFingerprints = [
    'https://generativelanguage.googleapis.com/v1beta/models/',
    'canopy_llm_fix_typos',
    'canopy_llm_edit',
  ];
  const result = inspectWakuBundles({
    serverBundles: [],
    clientBundles: [{
      name: 'dist/public/assets/memo-route-a.js',
      source: [
        'data-memo-ready',
        'The Memo runtime is unavailable on the client',
        ...providerFingerprints,
      ].join('\n'),
    }, {
      name: 'dist/public/assets/crdt-lambda-a.js',
      source: ['assemble_lambda_handle', ...providerFingerprints].join('\n'),
    }],
  });
  assert.deepEqual(result.productionClientArtifactLeaks, [
    {
      capability: 'Memo development shell',
      fingerprint: 'data-memo-ready',
      file: 'dist/public/assets/memo-route-a.js',
    },
    {
      capability: 'Memo client module',
      fingerprint: 'The Memo runtime is unavailable on the client',
      file: 'dist/public/assets/memo-route-a.js',
    },
    {
      capability: 'Memo provider URL',
      fingerprint: 'https://generativelanguage.googleapis.com/v1beta/models/',
      file: 'dist/public/assets/memo-route-a.js',
    },
    {
      capability: 'Memo provider function',
      fingerprint: 'canopy_llm_fix_typos',
      file: 'dist/public/assets/memo-route-a.js',
    },
    {
      capability: 'Memo provider function',
      fingerprint: 'canopy_llm_edit',
      file: 'dist/public/assets/memo-route-a.js',
    },
  ]);
});

test('keeps Vite defaults while exposing explicit dual-run commands', () => {
  const pkg = JSON.parse(fs.readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  assert.equal(pkg.scripts.dev, 'vite');
  assert.equal(pkg.scripts.build, 'vite build');
  assert.equal(pkg.scripts['dev:vite'], 'vite');
  assert.equal(pkg.scripts['build:vite'], 'vite build');
  assert.equal(pkg.scripts['dev:waku'], 'waku dev');
  assert.equal(pkg.scripts['dev:dual'], 'bash scripts/dev-dual.sh');
  assert.equal(pkg.scripts['build:waku'], 'bash scripts/build-waku.sh');
  assert.equal(
    pkg.scripts['test:waku:preview'],
    'playwright test --config=playwright.waku-preview.config.ts',
  );
  assert.equal(
    pkg.scripts['generate:waku-types'],
    'wrangler types worker-configuration.d.ts --config wrangler.waku.jsonc',
  );
  assert.equal(
    pkg.scripts['check:waku-types'],
    'wrangler types --config wrangler.waku.jsonc --check',
  );
  assert.equal(pkg.dependencies.waku, '1.0.0-beta.8');
  assert.equal(pkg.devDependencies.wrangler, '4.114.0');
  assert.equal(pkg.engines.node, '^24.0.0 || ^22.15.0');
});

test('retries only the Waku adapter internal preview startup race', async () => {
  assert.equal(
    isWakuBuildPreviewRequest('http://127.0.0.1:4173/__waku_internal_build_static_files'),
    true,
  );
  assert.equal(isWakuBuildPreviewRequest('http://127.0.0.1:4173/genui'), false);
  assert.equal(
    isWakuBuildPreviewRequest('https://example.com/__waku_internal_build_static_files'),
    false,
  );

  const calls = [];
  const waits = [];
  const response = await fetchWakuBuildPreviewWithRetry(
    'http://127.0.0.1:4173/__waku_internal_build_static_files',
    undefined,
    {
      attempts: 3,
      delayMs: 5,
      fetchFn: async (input) => {
        calls.push(input);
        if (calls.length < 3) {
          throw new TypeError('fetch failed', {
            cause: Object.assign(new Error('connection refused'), { code: 'ECONNREFUSED' }),
          });
        }
        return new Response('ok');
      },
      wait: async (delayMs) => { waits.push(delayMs); },
    },
  );

  assert.equal(await response.text(), 'ok');
  assert.equal(calls.length, 3);
  assert.deepEqual(waits, [5, 5]);

  for (const [url, code] of [
    ['http://127.0.0.1:4173/genui', 'ECONNREFUSED'],
    ['http://127.0.0.1:4173/__waku_internal_build_static_files', 'ECONNRESET'],
  ]) {
    let failureCalls = 0;
    const expectedError = new TypeError('fetch failed', {
      cause: Object.assign(new Error('non-retryable failure'), { code }),
    });
    await assert.rejects(
      fetchWakuBuildPreviewWithRetry(url, undefined, {
        fetchFn: async () => {
          failureCalls += 1;
          throw expectedError;
        },
        wait: async () => { throw new Error('unexpected retry'); },
      }),
      (error) => error === expectedError,
    );
    assert.equal(failureCalls, 1);
  }

  const buildScript = fs.readFileSync(new URL('./build-waku.sh', import.meta.url), 'utf8');
  assert.match(buildScript, /CANOPY_WAKU_BUILD_FETCH_RETRY=1/);
  assert.match(buildScript, /--import=.\/scripts\/waku-build-fetch-retry\.mjs/);
});

test('runs both development servers behind one external root watcher', () => {
  const script = fs.readFileSync(new URL('./dev-dual.sh', import.meta.url), 'utf8');
  assert.equal(script.match(/moon build --target js --release --watch/g)?.length, 1);
  assert.equal(script.match(/CANOPY_EXTERNAL_MOON_WATCH=1/g)?.length, 2);
  assert.match(script, /npm run dev:vite/);
  assert.match(script, /npm run dev:waku/);
});

test('adds parallel Waku build, browser, and workerd jobs to the repository gate', () => {
  const ci = fs.readFileSync(new URL('../../../.github/workflows/ci.yml', import.meta.url), 'utf8');
  assert.match(ci, /^  waku-build:\n/m);
  assert.match(ci, /^  waku-e2e:\n/m);
  assert.match(ci, /^  waku-workerd:\n/m);
  assert.match(ci, /npm run build:waku/);
  assert.match(ci, /npm run check:waku-bundles/);
  assert.match(ci, /npm run check:waku-types/);
  assert.match(
    ci,
    /npx wrangler deploy --config wrangler\.waku\.jsonc --dry-run --env preview/,
  );
  assert.match(
    ci,
    /npx wrangler check startup --config wrangler\.waku\.jsonc --env preview/,
  );
  assert.match(ci, /npm run test:waku:e2e/);
  assert.match(ci, /npm run test:waku:preview/);
  assert.match(ci, /npm run test:waku:workerd/);
  assert.match(
    ci,
    /Build Waku for production browser probes[\s\S]*npm run build:waku[\s\S]*npm run test:waku:e2e[\s\S]*CANOPY_SKIP_WAKU_BUILD: 1[\s\S]*npm run test:waku:preview/,
  );
  const previewServer = fs.readFileSync(
    new URL('./serve-waku-preview.sh', import.meta.url),
    'utf8',
  );
  assert.match(previewServer, /CANOPY_SKIP_WAKU_BUILD/);
  assert.match(previewServer, /test -f dist\/server\/index\.js/);
  assert.match(previewServer, /test -f dist\/public\/index\.html/);
  const aggregate = ci.slice(ci.indexOf('  all-checks-passed:'));
  assert.match(aggregate, /^      - waku-build$/m);
  assert.match(aggregate, /^      - waku-e2e$/m);
  assert.match(aggregate, /^      - waku-workerd$/m);
  assert.match(aggregate, /needs\.waku-build\.result/);
  assert.match(aggregate, /needs\.waku-e2e\.result/);
  assert.match(aggregate, /needs\.waku-workerd\.result/);
});

test('isolates the non-deploying Waku foundation from the existing Vite deployment', () => {
  const legacyWrangler = JSON.parse(
    fs.readFileSync(new URL('../wrangler.jsonc', import.meta.url), 'utf8'),
  );
  assert.deepEqual(legacyWrangler, {
    name: 'canopy-lambda-editor',
    compatibility_date: '2026-01-04',
    assets: { directory: 'dist' },
  });

  const wakuWrangler = JSON.parse(
    fs.readFileSync(new URL('../wrangler.waku.jsonc', import.meta.url), 'utf8'),
  );
  assert.equal(wakuWrangler.main, 'dist/server/index.js');
  assert.deepEqual(wakuWrangler.compatibility_flags, ['nodejs_compat']);
  assert.deepEqual(wakuWrangler.assets, {
    binding: 'ASSETS',
    directory: './dist/public',
    html_handling: 'drop-trailing-slash',
  });
  assert.equal(wakuWrangler.no_bundle, true);
  assert.deepEqual(wakuWrangler.rules, [{
    type: 'ESModule',
    globs: ['**/*.js', '**/*.mjs'],
  }]);
  assert.equal(wakuWrangler.env.preview.name, 'canopy-web-waku-preview');
  assert.equal(wakuWrangler.env.production.name, 'canopy-web-waku-production');
  assert.equal(wakuWrangler.services, undefined);
  assert.equal(wakuWrangler.vars, undefined);

  const smoke = fs.readFileSync(new URL('./smoke-waku-worker.sh', import.meta.url), 'utf8');
  assert.match(smoke, /wrangler dev --config wrangler\.waku\.jsonc --env preview/);
  assert.match(smoke, /127\.0\.0\.1:\$\{PORT\}\/memo/);
  assert.match(smoke, /data-memo-production-unavailable/);
  assert.match(smoke, /id="api-key"\|Fix Typos\|data-imperative-demo-host="memo"/);
  assert.match(smoke, /127\.0\.0\.1:\$\{PORT\}\/genui/);
  assert.match(smoke, /Run recorded candidate/);
  assert.match(smoke, /127\.0\.0\.1:\$\{PORT\}\/api\/genui-feasibility/);
});
