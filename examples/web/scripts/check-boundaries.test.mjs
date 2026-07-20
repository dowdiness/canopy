import test from 'node:test';
import assert from 'node:assert/strict';
import {
  checkBoundaries,
  classifyPath,
  describePath,
  evaluateEdge,
  evaluateHtmlEntryScripts,
  htmlEntryAccepted,
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
    resolveLocalImport('src/entries/posts.ts', '../features/posts/browser/mount', files),
    'src/features/posts/browser/mount.ts',
  );
  assert.equal(
    resolveLocalImport('src/features/posts/browser/mount.ts', '/server/vite/provider.ts', files),
    'server/vite/provider.ts',
  );
});

test('requires entries to import the matching feature browser surface only', () => {
  assert.deepEqual(
    evaluateEdge('src/entries/posts.ts', 'src/features/posts/browser/mount.ts'),
    [],
  );
  assert.match(
    evaluateEdge('src/entries/posts.ts', 'src/features/posts/core/posts.ts')[0],
    /entry/,
  );
  assert.match(
    evaluateEdge('src/entries/posts.ts', 'src/shared/browser/date.ts')[0],
    /entry/,
  );
  assert.match(
    evaluateEdge('src/entries/posts.ts', 'react', 'react')[0],
    /entry/,
  );
});

test('requires HTML to load a current entry or the target-shaped entry module', () => {
  assert.equal(htmlEntryAccepted('/src/post-app.ts', 'posts', 'src/post-app.ts'), true);
  assert.equal(htmlEntryAccepted('/src/post-store.ts', 'posts', 'src/post-app.ts'), false);
  assert.equal(htmlEntryAccepted('/src/entries/posts.ts', 'posts', 'src/post-app.ts'), true);
  assert.equal(htmlEntryAccepted('/src/features/posts/core/posts.ts', 'posts', 'src/post-app.ts'), false);
  assert.equal(htmlEntryAccepted('/src/entries/resume.tsx', 'posts', 'src/post-app.ts'), false);
  assert.deepEqual(
    evaluateHtmlEntryScripts('posts.html', 'posts', [], 'src/post-app.ts'),
    [{
      from: 'posts.html',
      to: '<missing>',
      rule: 'HTML entry must load at least one corresponding browser entry module',
    }],
  );
  assert.deepEqual(
    evaluateHtmlEntryScripts(
      'posts.html',
      'posts',
      ['/src/entries/posts.ts'],
      'src/post-app.ts',
    ),
    [],
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

test('recognizes current exceptions and future top-level runtime vocabulary', () => {
  assert.equal(classifyPath('src/main.ts'), 'lambda');
  assert.equal(classifyPath('src/components/ai-elements/message.tsx'), 'resume');
  assert.equal(classifyPath('src/genui-feasibility-provider.js'), 'server');
  assert.equal(classifyPath('server/vite/genui-provider.ts'), 'server');
  assert.deepEqual(
    describePath('src/features/json/browser/editor.ts'),
    { kind: 'feature', owner: 'json', layer: 'browser' },
  );
});

test('rejects newly added unclassified production modules', () => {
  const root = '/repo/examples/web';
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
