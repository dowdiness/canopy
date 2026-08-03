import test from 'node:test';
import assert from 'node:assert/strict';
import {
  checkBoundaries,
  classifyPath,
  describePath,
  evaluateEdge,
  isClientModule,
  resolveLocalImport,
  staticImports,
} from './check-boundaries.mjs';

test('parses static and literal dynamic imports with the TypeScript AST', () => {
  assert.deepEqual(
    staticImports([
      "import { x } from './x.js'",
      "export { y } from './y.js'",
      "const z = import('./dynamic.js')",
      "const legacy = require('./legacy.cjs')",
      "const ignored = import(variable)",
    ].join('\n')),
    ['./x.js', './y.js', './dynamic.js', './legacy.cjs'],
  );
});

test('accepts same-feature and feature-to-shared edges', () => {
  assert.deepEqual(
    evaluateEdge('src/features/posts/browser/app.ts', 'src/features/posts/core/posts.ts'),
    [],
  );
  assert.deepEqual(
    evaluateEdge('src/features/posts/browser/app.ts', 'src/shared/browser/date.ts'),
    [],
  );
});

test('rejects cross-feature, browser-to-server, and shared-to-feature edges', () => {
  assert.match(
    evaluateEdge('src/features/posts/browser/app.ts', 'src/features/resume/core/session.ts')[0],
    /another feature/,
  );
  assert.match(
    evaluateEdge('src/features/genui/browser/app.ts', 'server/vite/provider.ts')[0],
    /server/,
  );
  assert.match(
    evaluateEdge('src/shared/browser/overlay.ts', 'src/features/posts/browser/app.ts')[0],
    /shared/,
  );
});

test('resolves relative and Vite root-relative local imports', () => {
  const files = new Set([
    'src/features/posts/browser/mount.ts',
    'server/vite/provider.ts',
  ]);
  assert.equal(
    resolveLocalImport('src/pages/posts.tsx', '../features/posts/browser/mount', files),
    'src/features/posts/browser/mount.ts',
  );
  assert.equal(
    resolveLocalImport('src/features/posts/browser/mount.ts', '/server/vite/provider.ts', files),
    'server/vite/provider.ts',
  );
});

test('rejects feature route imports of legacy HTML', () => {
  assert.deepEqual(
    evaluateEdge(
      'src/features/genui-possibilities/route/journey-route.tsx',
      'genui-possibilities.html?raw',
    ),
    ['feature route cannot import legacy HTML'],
  );
});

test('limits future server adapters to feature core and protocol surfaces', () => {
  assert.deepEqual(
    evaluateEdge('server/vite/resume-chat.ts', 'src/features/resume/protocol/chat.ts'),
    [],
  );
  assert.match(
    evaluateEdge('server/vite/resume-chat.ts', 'src/features/resume/browser/chat.ts')[0],
    /server code/,
  );
});

test('rejects browser-layer imports from declared core and protocol paths', () => {
  assert.match(
    evaluateEdge(
      'src/features/resume/core/session.ts',
      'src/features/resume/browser/import-session.ts',
    )[0],
    /browser layers/,
  );
  assert.match(
    evaluateEdge(
      'src/features/resume/protocol/chat.ts',
      'src/shared/browser/fetch-json.ts',
    )[0],
    /browser layers/,
  );
});

test('rejects capabilities from declared core and protocol paths', () => {
  assert.match(
    evaluateEdge('src/features/resume/core/parser.ts', 'node:crypto', 'node:crypto')[0],
    /core\/protocol/,
  );
  assert.match(
    evaluateEdge('src/features/resume/protocol/chat.ts', 'react', 'react')[0],
    /core\/protocol/,
  );
});

test('recognizes Waku pages, route surfaces, and server configuration', () => {
  assert.deepEqual(describePath('src/pages/json.tsx'), { kind: 'page', owner: 'json' });
  assert.deepEqual(describePath('src/pages/_root.tsx'), { kind: 'page', owner: 'shared' });
  assert.deepEqual(
    describePath('src/features/json/route/index.tsx'),
    { kind: 'feature', owner: 'json', layer: 'route' },
  );
  assert.equal(classifyPath('src/waku.server.tsx'), 'server');
  assert.equal(classifyPath('waku.config.ts'), 'server');
  assert.equal(classifyPath('worker-configuration.d.ts'), 'server');
  assert.equal(classifyPath('src/pages.gen.ts'), 'generated');
});

test('allows Waku pages to compose shared and corresponding route surfaces only', () => {
  assert.deepEqual(
    evaluateEdge('src/pages/json.tsx', 'src/features/json/route/index.tsx'),
    [],
  );
  assert.deepEqual(
    evaluateEdge('src/pages/json.tsx', 'src/shared/shell.tsx'),
    [],
  );
  assert.match(
    evaluateEdge('src/pages/json.tsx', 'src/features/json/browser/editor.ts')[0],
    /route surface/,
  );
  assert.match(
    evaluateEdge('src/pages/json.tsx', 'src/features/posts/route/index.tsx')[0],
    /corresponding feature/,
  );
});

test('keeps the shared route-lifecycle core free of React and browser effects', () => {
  assert.deepEqual(
    describePath('src/shared/route-lifecycle/core/reducer.ts'),
    { kind: 'shared', layer: 'core' },
  );
  assert.deepEqual(
    describePath('src/shared/route-lifecycle/browser/provider.tsx'),
    { kind: 'shared', layer: 'browser' },
  );
  assert.match(
    evaluateEdge('src/shared/route-lifecycle/core/reducer.ts', 'react', 'react')[0],
    /route-lifecycle core/,
  );
  assert.match(
    evaluateEdge(
      'src/shared/route-lifecycle/core/reducer.ts',
      'src/shared/route-lifecycle/browser/provider.tsx',
    )[0],
    /route-lifecycle core/,
  );
});

test('recognizes use-client directives and confines generated modules below them', () => {
  assert.equal(isClientModule("'use client';\nimport '@moonbit/crdt-json';"), true);
  assert.equal(isClientModule('/* comment */\n"use client";\nexport {}'), true);
  assert.equal(isClientModule("import '@moonbit/crdt-json';\n'use client';"), false);
  assert.match(
    evaluateEdge('src/pages/json.tsx', '@moonbit/crdt-json', '@moonbit/crdt-json', false)[0],
    /use client/,
  );
  assert.deepEqual(
    evaluateEdge(
      'src/features/json/route/index.tsx',
      '@moonbit/crdt-json',
      '@moonbit/crdt-json',
      true,
    ),
    [],
  );
  assert.match(
    evaluateEdge(
      'src/features/json/browser/editor.ts',
      '@moonbit/crdt-json',
      '@moonbit/crdt-json',
      false,
    )[0],
    /use client/,
  );
});

test('recognizes current exceptions and future top-level runtime vocabulary', () => {
  assert.equal(classifyPath('src/features/resume/browser/app.tsx'), 'resume');
  assert.equal(classifyPath('src/features/resume/browser/components/message.tsx'), 'resume');
  assert.equal(classifyPath('src/features/resume/browser/styles.css'), 'resume');
  assert.equal(classifyPath('src/features/resume/core/session.ts'), 'resume');
  assert.equal(classifyPath('src/features/resume/protocol/chat.ts'), 'resume');
  assert.equal(classifyPath('src/resume-app.tsx'), 'unclassified');
  assert.equal(classifyPath('src/pi-resume-core.ts'), 'unclassified');
  assert.equal(classifyPath('src/pi-resume-chat-protocol.ts'), 'unclassified');
  assert.equal(classifyPath('src/components/ai-elements/message.tsx'), 'unclassified');
  assert.equal(classifyPath('src/resume.css'), 'unclassified');
  assert.equal(classifyPath('src/features/genui/browser/mount.js'), 'genui');
  assert.equal(classifyPath('src/features/genui/browser/styles.css'), 'genui');
  assert.equal(classifyPath('src/features/genui/core/genui-feasibility-flow.js'), 'genui');
  assert.equal(classifyPath('server/genui/feasibility-provider.js'), 'server');
  assert.equal(classifyPath('server/vite/genui-feasibility.ts'), 'server');
  assert.equal(classifyPath('server/vite/genui-provider.ts'), 'server');
  assert.equal(classifyPath('server/vite/ast-grep.ts'), 'server');
  assert.equal(classifyPath('src/shared/decoration-overlay.ts'), 'shared');
  assert.deepEqual(
    describePath('src/features/json/browser/editor.ts'),
    { kind: 'feature', owner: 'json', layer: 'browser' },
  );
});

test('rejects newly added unclassified production modules', () => {
  const root = '/repo/apps/web';
  const files = [`${root}/src/mystery.ts`];
  const violations = checkBoundaries({
    root,
    files,
    readFile: () => 'export const mystery = true',
  });
  assert.deepEqual(violations, [{
    from: 'src/mystery.ts',
    to: 'src/mystery.ts',
    rule: 'source module has no declared owner',
  }]);
});
