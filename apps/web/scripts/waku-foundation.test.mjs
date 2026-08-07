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

test('uses Waku as the default development and build system', () => {
  const pkg = JSON.parse(fs.readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
  assert.equal(pkg.scripts.dev, 'waku dev');
  assert.equal(pkg.scripts.build, 'bash scripts/build-waku.sh');
  assert.equal(pkg.scripts.preview, 'bash scripts/serve-waku-preview.sh');
  assert.equal(pkg.scripts['dev:waku'], 'waku dev');
  assert.equal(pkg.scripts['build:waku'], 'bash scripts/build-waku.sh');
  assert.equal(pkg.scripts['build:deploy'], 'sh scripts/build-deploy.sh');
  assert.equal(pkg.scripts['build:deploy:waku'], 'sh scripts/build-deploy.sh waku');
  for (const script of ['dev:vite', 'build:vite', 'dev:dual']) {
    assert.equal(pkg.scripts[script], undefined, `${script} must be removed`);
  }
  assert.equal(
    pkg.scripts['test:waku:preview'],
    'playwright test --config=playwright.waku-preview.config.ts && playwright test --config=playwright.waku-preload.config.ts',
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
  assert.equal(pkg.devDependencies['@tailwindcss/vite'], '^4.3.3');
  assert.equal(pkg.devDependencies.vite, '^8.1.5');
  assert.equal(pkg.devDependencies['@vitejs/plugin-react'], undefined);
  assert.equal(pkg.devDependencies['rollup-plugin-visualizer'], undefined);
  assert.equal(pkg.engines.node, '^24.0.0 || ^22.15.0');
});

test('retires legacy delivery artifacts while preserving the inactive spike', () => {
  const retiredPaths = [
    'index.html',
    'json.html',
    'markdown.html',
    'memo.html',
    'posts.html',
    'resume.html',
    'genui.html',
    'genui-possibilities.html',
    'src/entries/lambda.ts',
    'src/entries/json.ts',
    'src/entries/markdown.ts',
    'src/entries/memo.ts',
    'src/entries/posts.ts',
    'src/entries/resume.ts',
    'src/entries/genui.js',
    'src/entries/genui-possibilities.js',
    'src/features/lambda/browser/mount.ts',
    'src/features/json/browser/mount.ts',
    'src/features/markdown/browser/mount.ts',
    'src/features/memo/browser/mount.ts',
    'src/tailwind.css',
    'vite.config.ts',
    'playwright.config.ts',
    'playwright.preview.config.ts',
    'scripts/dev-dual.sh',
  ];
  for (const retiredPath of retiredPaths) {
    assert.equal(
      fs.existsSync(new URL(`../${retiredPath}`, import.meta.url)),
      false,
      `${retiredPath} must stay retired`,
    );
  }
  assert.equal(
    fs.existsSync(new URL('../spike-block-input.html', import.meta.url)),
    true,
  );

  for (const config of [
    '../playwright.feasibility.config.ts',
    '../playwright.minimal-provider.config.ts',
  ]) {
    const source = fs.readFileSync(new URL(config, import.meta.url), 'utf8');
    assert.match(source, /npm run dev:waku/);
    assert.match(source, /\/genui/);
    assert.doesNotMatch(source, /npx vite/);
    assert.doesNotMatch(source, /genui\.html/);
  }
});

test('gives Cloudflare Workers Builds an explicit Waku production target', () => {
  const deployScript = fs.readFileSync(
    new URL('./build-deploy.sh', import.meta.url),
    'utf8',
  );
  assert.match(deployScript, /\$\{1:-waku\}/);
  assert.match(deployScript, /MOONBIT_VERSION="0\.10\.4\+ade96c819"/);
  assert.match(deployScript, /bash -s -- "\$MOONBIT_VERSION"/);
  assert.match(deployScript, /cd deps\/graphviz/);
  assert.doesNotMatch(deployScript, /cd graphviz/);
  assert.match(deployScript, /npm run build:waku/);
  assert.doesNotMatch(deployScript, /vite build/);

  const deployWorkflow = fs.readFileSync(
    new URL('../../../.github/workflows/deploy-cloudflare.yml', import.meta.url),
    'utf8',
  );
  assert.doesNotMatch(deployWorkflow, /^\s+npm-dir:\s*examples\/web\s*$/m);
  assert.doesNotMatch(
    deployWorkflow,
    /^\s+deploy-dir:\s*examples\/web(?:\/dist)?\s*$/m,
  );
  assert.match(deployWorkflow, /^\s+- name: ideal$/m);
  assert.match(
    deployWorkflow,
    /DST="\$GITHUB_WORKSPACE\/apps\/\$EXAMPLE\/_build\/js\/release\/build\/\$MOD\/main"/,
  );

  // prosemirror stays in examples/ (unlike the apps/*/web consumers), so it
  // must reach the shared plugin at apps/web/vite-plugin-moonbit.ts.
  const prosemirrorConfig = fs.readFileSync(
    new URL(
      '../../../examples/prosemirror/vite.config.ts',
      import.meta.url,
    ),
    'utf8',
  );
  assert.match(
    prosemirrorConfig,
    /from '\.\.\/\.\.\/apps\/web\/vite-plugin-moonbit'/,
  );
  assert.doesNotMatch(prosemirrorConfig, /\.\.\/web\/vite-plugin-moonbit/);
});

test('keeps Waku build, browser, and workerd jobs as the web repository gate', () => {
  const ci = fs.readFileSync(new URL('../../../.github/workflows/ci.yml', import.meta.url), 'utf8');
  assert.match(ci, /^  waku-build:\n/m);
  assert.match(ci, /^  waku-e2e:\n/m);
  assert.match(ci, /^  waku-workerd:\n/m);
  assert.doesNotMatch(ci, /^  web-e2e:\n/m);
  assert.match(ci, /npm run build:waku/);
  assert.match(ci, /npm run check:waku-bundles/);
  assert.match(ci, /npm run check:waku-types/);
  assert.match(
    ci,
    /npx wrangler deploy --config wrangler\.waku\.jsonc --dry-run --env preview[\s\S]*--outfile "\$\{RUNNER_TEMP\}\/waku-preview-worker\.bundle"/,
  );
  assert.match(
    ci,
    /npx wrangler check startup[\s\S]*--worker "\$\{RUNNER_TEMP\}\/waku-preview-worker\.bundle"/,
  );
  assert.match(
    ci,
    /npx wrangler deploy --config wrangler\.waku\.jsonc --dry-run --env production[\s\S]*--outfile "\$\{RUNNER_TEMP\}\/waku-production-worker\.bundle"/,
  );
  assert.match(
    ci,
    /npx wrangler check startup[\s\S]*--worker "\$\{RUNNER_TEMP\}\/waku-production-worker\.bundle"/,
  );
  assert.match(ci, /npm run test:waku:e2e/);
  assert.match(ci, /npm run test:waku:preview/);
  assert.match(ci, /npm run test:waku:workerd/);
  const wakuE2e = ci.slice(ci.indexOf('  waku-e2e:'), ci.indexOf('  waku-workerd:'));
  assert.match(wakuE2e, /needs: \[build-js, changes, waku-build\]/);
  assert.match(
    wakuE2e,
    /Download Waku production build[\s\S]*name: waku-web-build-\$\{\{ github\.run_attempt \}\}[\s\S]*path: apps\/web\/dist[\s\S]*npm run test:waku:e2e[\s\S]*CANOPY_SKIP_WAKU_BUILD: 1[\s\S]*npm run test:waku:preview/,
  );
  assert.doesNotMatch(wakuE2e, /npm run build:waku/);
  assert.match(ci, /npm run create:waku-release-manifest/);
  assert.match(ci, /name: waku-web-build-\$\{\{ github\.run_attempt \}\}/);
  assert.match(
    ci,
    /name: waku-web-release-manifest-\$\{\{ github\.run_attempt \}\}/,
  );
  assert.match(ci, /retention-days: 30/);
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
  assert.doesNotMatch(aggregate, /needs\.web-e2e\.result/);
});

test('uses one canonical Waku production deployment configuration', () => {
  const canonicalConfig = new URL('../wrangler.jsonc', import.meta.url);
  const externalCompatibilityConfig = new URL('../wrangler.waku.jsonc', import.meta.url);
  assert.equal(fs.existsSync(canonicalConfig), true);
  assert.equal(fs.lstatSync(externalCompatibilityConfig).isSymbolicLink(), true);
  assert.equal(fs.readlinkSync(externalCompatibilityConfig), 'wrangler.jsonc');
  assert.equal(
    fs.readFileSync(externalCompatibilityConfig, 'utf8'),
    fs.readFileSync(canonicalConfig, 'utf8'),
  );

  const wakuWrangler = JSON.parse(fs.readFileSync(canonicalConfig, 'utf8'));
  assert.equal(wakuWrangler.main, 'dist/server/index.js');
  assert.deepEqual(wakuWrangler.compatibility_flags, ['nodejs_compat']);
  assert.deepEqual(wakuWrangler.assets, {
    binding: 'ASSETS',
    directory: './dist/public',
    html_handling: 'drop-trailing-slash',
    run_worker_first: true,
  });
  assert.equal(wakuWrangler.no_bundle, true);
  assert.deepEqual(wakuWrangler.rules, [{
    type: 'ESModule',
    globs: ['**/*.js', '**/*.mjs'],
  }]);
  assert.equal(wakuWrangler.env.preview.name, 'canopy-web-waku-preview');
  assert.equal(wakuWrangler.env.production.name, 'canopy-examples');
  const signalingBinding = [{
    binding: 'SIGNALING',
    service: 'crdt-signaling-server',
  }];
  assert.deepEqual(wakuWrangler.services, signalingBinding);
  assert.deepEqual(wakuWrangler.env.preview.services, signalingBinding);
  assert.deepEqual(wakuWrangler.env.production.services, signalingBinding);
  assert.deepEqual(wakuWrangler.version_metadata, { binding: 'WORKER_VERSION' });
  assert.deepEqual(wakuWrangler.env.preview.version_metadata, {
    binding: 'WORKER_VERSION',
  });
  assert.deepEqual(wakuWrangler.env.production.version_metadata, {
    binding: 'WORKER_VERSION',
  });
  assert.deepEqual(wakuWrangler.observability, {
    enabled: true,
    logs: {
      enabled: true,
      head_sampling_rate: 1,
      invocation_logs: false,
    },
    traces: { enabled: false },
  });
  assert.equal(wakuWrangler.vars, undefined);

  const smoke = fs.readFileSync(new URL('./smoke-waku-worker.sh', import.meta.url), 'utf8');
  assert.match(
    smoke,
    /wrangler dev[\s\S]*-c wrangler\.waku\.jsonc[\s\S]*-c wrangler-signaling\.toml/,
  );
  assert.doesNotMatch(smoke, /--env preview/);
  assert.match(smoke, /canonical_paths=/);
  assert.match(smoke, /legacy_paths=/);
  assert.match(smoke, /\/RSC\/R\$\{legacy\}\.txt/);
  assert.match(smoke, /data-memo-production-unavailable/);
  assert.match(smoke, /id="api-key"\|Fix Typos\|data-imperative-demo-host="memo"/);
  assert.match(smoke, /Run recorded candidate/);
  assert.match(smoke, /'\/api\/genui-feasibility'/);
  assert.match(smoke, /smoke-signaling-websocket\.mjs/);
  assert.match(smoke, /--cloudflare-local/);
});
