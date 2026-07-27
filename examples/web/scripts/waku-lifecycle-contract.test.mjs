import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { renderToStaticMarkup } from 'react-dom/server';
import {
  createLifecycleState,
  reduceLifecycle,
} from '../src/shared/route-lifecycle/core/reducer.ts';
import {
  createCompatibilityRedirectState,
  MAX_COMPATIBILITY_HISTORY_ATTEMPTS,
  reduceCompatibilityRedirect,
} from '../src/shared/route-lifecycle/core/compatibility-redirect.ts';
import { applyFocusDecision } from '../src/shared/route-lifecycle/browser/focus-manager.ts';
import { ownImperativeSession } from '../src/shared/route-lifecycle/browser/imperative-session.ts';
import {
  NavigationFailureAlert,
  PostCommitRouteError,
} from '../src/shared/route-lifecycle/browser/common-states.ts';
import { recoverPreCommitNavigation } from '../src/shared/route-lifecycle/browser/navigation-recovery.ts';

const require = createRequire(import.meta.url);
const wakuPackage = require('waku/package.json');
const clientSourceUrl = import.meta.resolve('waku/router/client');
const clientSourcePath = fileURLToPath(clientSourceUrl);
const clientSource = fs.readFileSync(clientSourcePath, 'utf8');
const providerSource = fs.readFileSync(
  fileURLToPath(new URL('../src/shared/route-lifecycle/browser/provider.tsx', import.meta.url)),
  'utf8',
);
const clientTypes = fs.readFileSync(
  clientSourcePath.replace(/\.js$/, '.d.ts'),
  'utf8',
);

test('pins the Waku lifecycle seam proved by this migration', () => {
  assert.equal(wakuPackage.version, '1.0.0-beta.8');
  assert.match(clientTypes, /type ChangeRouteEvent = 'start' \| 'complete'/);
  assert.match(clientTypes, /unstable_events: Record<"on" \| "off"/);
  assert.match(clientTypes, /scroll\?: boolean/);
  assert.match(clientTypes, /\(to: RouteHref, options\?: NavigateOptions\): Promise<void>/);
});

test('emits pre-navigation before work and completion only after route commit', () => {
  const start = clientSource.indexOf("emitRouteChangeEvent('start', nextRoute)");
  const resolve = clientSource.indexOf('resolveFollowingErrors(resolveDeps, nextRoute');
  const commit = clientSource.indexOf('routeRef.current = route', start);
  const complete = clientSource.indexOf("emitRouteChangeEvent('complete', route)", commit);
  assert.ok(start >= 0 && resolve > start);
  assert.ok(commit > start && complete > commit);
});

test('keeps scroll in Waku and exposes completion as the focus integration point', () => {
  assert.match(
    clientSource,
    /useLayoutEffect\(\(\)=>\{[\s\S]*?if \(nav\.scroll\) \{[\s\S]*?scrollToRoute/,
  );
  assert.doesNotMatch(clientTypes, /ChangeRouteEvent = [^;]*focus/);
});

test('uses navigation rejection and React boundaries because no Waku error event exists', () => {
  assert.doesNotMatch(clientTypes, /ChangeRouteEvent = [^;]*error/);
  assert.match(clientTypes, /export declare class ErrorBoundary/);
  assert.match(clientSource, /setErr\(e2\);[\s\S]*?throw e2/);
});

test('routes popstate through Waku and leaves route disposal to React unmount cleanup', () => {
  assert.match(clientSource, /window\.addEventListener\('popstate', callback\)/);
  assert.match(clientSource, /changeRoute\(nextRoute, \{[\s\S]*?shouldScroll:/);
  assert.match(clientSource, /return \(\)=>\{[\s\S]*?window\.removeEventListener\('popstate', callback\)/);
});

test('saves before navigation and disposes the source only after route commit', () => {
  const sourceSnapshot = { source: 'let answer = 42' };
  const started = reduceLifecycle(
    createLifecycleState('lambda'),
    {
      type: 'navigation-started',
      mode: 'push',
      to: '/json',
      destination: 'json',
      source: {
        demoId: 'lambda',
        snapshot: sourceSnapshot,
        focusToken: 'editor',
      },
    },
  );

  sourceSnapshot.source = 'mutated after dispatch';
  assert.deepEqual(started.state.snapshots.lambda, {
    value: { source: 'let answer = 42' },
    focusToken: 'editor',
  });
  assert.deepEqual(started.decisions, [
    { type: 'save-snapshot', demoId: 'lambda' },
  ]);

  const committed = reduceLifecycle(started.state, {
    type: 'navigation-committed',
    destination: 'json',
    fragment: null,
  });
  assert.deepEqual(committed.decisions.slice(0, 2), [
    { type: 'dispose-surface', demoId: 'lambda' },
    { type: 'mount-surface', demoId: 'json' },
  ]);
});

test('forget immediately removes the requested route snapshot', () => {
  const withSnapshot = reduceLifecycle(
    createLifecycleState('resume'),
    {
      type: 'navigation-started',
      mode: 'push',
      to: '/',
      destination: null,
      source: {
        demoId: 'resume',
        snapshot: { session: 'normalized' },
        focusToken: 'source-list',
      },
    },
  ).state;

  const result = reduceLifecycle(withSnapshot, { type: 'forget', demoId: 'resume' });

  assert.equal(result.state.snapshots.resume, undefined);
  assert.deepEqual(result.decisions, [{ type: 'forget-snapshot', demoId: 'resume' }]);
});

test('turns push and browser traversal requests into Waku navigation decisions', () => {
  const state = createLifecycleState(null);

  assert.deepEqual(
    reduceLifecycle(state, { type: 'navigation-requested', mode: 'push', to: '/json' }),
    {
      state,
      decisions: [{ type: 'navigate', mode: 'push', to: '/json' }],
    },
  );
  assert.deepEqual(
    reduceLifecycle(state, { type: 'navigation-requested', mode: 'back' }),
    {
      state,
      decisions: [{ type: 'navigate', mode: 'back' }],
    },
  );
  assert.deepEqual(
    reduceLifecycle(state, { type: 'navigation-requested', mode: 'forward' }),
    {
      state,
      decisions: [{ type: 'navigate', mode: 'forward' }],
    },
  );
});

test('pop mounts the latest snapshot and restores stable focus with a heading fallback', () => {
  const saved = reduceLifecycle(
    createLifecycleState('json'),
    {
      type: 'navigation-started',
      mode: 'push',
      to: '/',
      destination: null,
      source: {
        demoId: 'json',
        snapshot: { source: '{"answer":42}' },
        focusToken: 'json-editor',
      },
    },
  ).state;
  const returning = reduceLifecycle(saved, {
    type: 'navigation-started',
    mode: 'pop',
    to: '/json',
    destination: 'json',
  }).state;

  const restored = reduceLifecycle(returning, {
    type: 'navigation-committed',
    destination: 'json',
    fragment: null,
  });
  assert.deepEqual(restored.decisions, [
    { type: 'mount-surface', demoId: 'json', snapshot: { source: '{"answer":42}' } },
    {
      type: 'focus-route',
      preferred: { kind: 'adapter', token: 'json-editor' },
      fallback: 'route-heading',
      preventScroll: true,
    },
  ]);

  const withoutToken = reduceLifecycle(
    {
      ...returning,
      snapshots: { json: { value: { source: '{}' }, focusToken: null } },
    },
    { type: 'navigation-committed', destination: 'json', fragment: null },
  );
  assert.deepEqual(withoutToken.decisions.at(-1), {
    type: 'focus-route',
    preferred: null,
    fallback: 'route-heading',
    preventScroll: true,
  });
});

test('push lets Waku scroll to fragments while focus moves to the route heading', () => {
  const started = reduceLifecycle(createLifecycleState(null), {
    type: 'navigation-started',
    mode: 'push',
    to: '/json',
    destination: 'json',
  }).state;

  const committed = reduceLifecycle(started, {
    type: 'navigation-committed',
    destination: 'json',
    fragment: 'editor',
  });

  assert.deepEqual(committed.decisions.at(-1), {
    type: 'focus-route',
    preferred: null,
    fallback: 'route-heading',
    preventScroll: true,
  });
});

test('a pre-commit failure retains the source route and announces recovery actions', () => {
  const started = reduceLifecycle(
    createLifecycleState('lambda'),
    {
      type: 'navigation-started',
      mode: 'push',
      to: '/json',
      destination: 'json',
      source: {
        demoId: 'lambda',
        snapshot: { source: 'let answer = 42' },
        focusToken: 'editor',
      },
    },
  ).state;

  const failed = reduceLifecycle(started, {
    type: 'navigation-failed',
    message: 'The demo could not be loaded.',
    retryHref: '/json',
  });

  assert.equal(failed.state.activeDemo, 'lambda');
  assert.equal(failed.state.pending, null);
  assert.deepEqual(failed.state.snapshots.lambda?.value, { source: 'let answer = 42' });
  assert.deepEqual(failed.state.error, {
    phase: 'pre-commit',
    message: 'The demo could not be loaded.',
    retryHref: '/json',
  });
  assert.deepEqual(failed.decisions, [{
    type: 'announce-navigation-error',
    phase: 'pre-commit',
    message: 'The demo could not be loaded.',
    retryHref: '/json',
  }]);
});

test('a pre-commit retry clears the error and pushes the retained target', () => {
  const failed = reduceLifecycle(createLifecycleState('lambda'), {
    type: 'navigation-failed',
    message: 'The demo could not be loaded.',
    retryHref: '/json',
  }).state;

  const retried = reduceLifecycle(failed, { type: 'retry' });

  assert.equal(retried.state.error, null);
  assert.deepEqual(retried.decisions, [{ type: 'navigate', mode: 'push', to: '/json' }]);
});

test('a post-commit failure keeps the destination and retries from its retained snapshot', () => {
  const saved = reduceLifecycle(
    createLifecycleState('json'),
    {
      type: 'navigation-started',
      mode: 'push',
      to: '/',
      destination: null,
      source: {
        demoId: 'json',
        snapshot: { source: '{"answer":42}' },
        focusToken: 'json-editor',
      },
    },
  ).state;
  const returning = reduceLifecycle(saved, {
    type: 'navigation-started',
    mode: 'pop',
    to: '/json',
    destination: 'json',
  }).state;
  const committed = reduceLifecycle(returning, {
    type: 'navigation-committed',
    destination: 'json',
    fragment: null,
  }).state;

  const failed = reduceLifecycle(committed, {
    type: 'render-failed',
    demoId: 'json',
    message: 'This demo could not be displayed.',
  });
  assert.equal(failed.state.activeDemo, 'json');
  assert.deepEqual(failed.state.error, {
    phase: 'post-commit',
    demoId: 'json',
    message: 'This demo could not be displayed.',
  });
  assert.deepEqual(failed.decisions, [
    { type: 'dispose-surface', demoId: 'json' },
    {
      type: 'show-route-error',
      demoId: 'json',
      message: 'This demo could not be displayed.',
    },
  ]);

  const retried = reduceLifecycle(failed.state, { type: 'retry' });
  assert.equal(retried.state.error, null);
  assert.deepEqual(retried.decisions, [
    { type: 'dispose-surface', demoId: 'json' },
    { type: 'mount-surface', demoId: 'json', snapshot: { source: '{"answer":42}' } },
  ]);
});

test('focus manager falls back to the route heading without changing scroll', () => {
  const focusCalls = [];
  const heading = { focus: (options) => focusCalls.push(['heading', options]) };
  const document = {
    getElementById: () => null,
    querySelector: (selector) => selector === '[data-route-heading]' ? heading : null,
  };
  const session = { restoreFocus: () => false };

  const outcome = applyFocusDecision(
    {
      type: 'focus-route',
      preferred: { kind: 'adapter', token: 'missing-control' },
      fallback: 'route-heading',
      preventScroll: true,
    },
    { document, session },
  );

  assert.equal(outcome, 'route-heading');
  assert.deepEqual(focusCalls, [['heading', { preventScroll: true }]]);
});

test('imperative sessions defensively own snapshots and dispose idempotently', () => {
  const mutableSnapshot = { source: 'initial' };
  let disposeCount = 0;
  const session = ownImperativeSession({
    snapshot: () => mutableSnapshot,
    restoreFocus: (token) => token === 'editor',
    dispose: () => { disposeCount += 1; },
  });

  const captured = session.snapshot();
  const restoredBeforeDispose = session.restoreFocus('editor');
  mutableSnapshot.source = 'changed later';
  session.dispose();
  session.dispose();

  assert.deepEqual(captured, { source: 'initial' });
  assert.equal(restoredBeforeDispose, true);
  assert.equal(session.restoreFocus('editor'), false);
  assert.equal(disposeCount, 1);
});

test('common failure states expose accessible recovery without leaking error details', () => {
  const preCommit = renderToStaticMarkup(NavigationFailureAlert({
    message: 'The demo could not be loaded.',
    retryHref: '/json',
    onRetry: () => {},
  }));
  assert.match(preCommit, /role="alert"/);
  assert.match(preCommit, />Retry</);
  assert.match(preCommit, /href="\/json"[^>]*>Open directly</);

  const postCommit = renderToStaticMarkup(PostCommitRouteError({
    message: 'The restored editor state is unavailable.',
    onRetry: () => {},
  }));
  assert.match(postCommit, /data-route-error-heading="true"/);
  assert.match(postCommit, /The restored editor state is unavailable\./);
  assert.match(postCommit, />Retry</);
  assert.match(postCommit, /href="\/"[^>]*>Back to demos</);
  assert.doesNotMatch(postCommit, /stack|payload|exception/i);
});

test('the provider shell handles the reducer post-commit error decision', () => {
  assert.match(
    providerSource,
    /decision\.type === 'show-route-error'[\s\S]*?setRouteErrorMessage\(decision\.message\)/,
  );
});

test('pre-commit recovery records the failure before traversing back', () => {
  const calls = [];
  recoverPreCommitNavigation(
    { back: () => { calls.push(['back']); } },
    () => { calls.push(['remember']); },
  );

  assert.deepEqual(calls, [
    ['remember'],
    ['back'],
  ]);
});

test('compatibility redirects track only legacy routes carrying fragments', () => {
  const initial = createCompatibilityRedirectState();
  const ordinary = reduceCompatibilityRedirect(initial, {
    type: 'navigation-started',
    route: { path: '/unknown.html', query: 'source=client', hash: '#focus' },
  });
  assert.equal(ordinary.state.pending, null);
  assert.deepEqual(ordinary.decision, { type: 'none' });

  const withoutFragment = reduceCompatibilityRedirect(initial, {
    type: 'navigation-started',
    route: { path: '/json.html', query: 'source=client', hash: '' },
  });
  assert.equal(withoutFragment.state.pending, null);

  const completed = reduceCompatibilityRedirect(initial, {
    type: 'navigation-completed',
    route: { path: '/json', query: 'source=client', hash: '#focus' },
  });
  assert.deepEqual(completed.decision, {
    type: 'commit-navigation',
    path: '/json',
    fragment: 'focus',
    reportPendingFailure: true,
  });
});

test('compatibility redirects wait for the hash-stripped history commit', () => {
  const started = reduceCompatibilityRedirect(createCompatibilityRedirectState(), {
    type: 'navigation-started',
    route: { path: '/json.html', query: 'source=client', hash: '#legacy-focus' },
  });
  assert.deepEqual(started.state.pending, {
    id: 0,
    canonicalPath: '/json',
    query: 'source=client',
    hash: '#legacy-focus',
  });

  const completed = reduceCompatibilityRedirect(started.state, {
    type: 'navigation-completed',
    route: { path: '/json', query: 'source=client', hash: '' },
  });
  assert.deepEqual(completed.decision, {
    type: 'observe-history',
    repairId: 0,
    attempt: 0,
  });

  const retry = reduceCompatibilityRedirect(completed.state, {
    type: 'history-observed',
    repairId: 0,
    attempt: 0,
    pathname: '/foundation',
    search: '',
  });
  assert.deepEqual(retry.decision, {
    type: 'observe-history',
    repairId: 0,
    attempt: 1,
  });
});

test('compatibility redirects restore the fragment and suppress the repair start', () => {
  const started = reduceCompatibilityRedirect(createCompatibilityRedirectState(), {
    type: 'navigation-started',
    route: { path: '/json.html', query: 'source=client', hash: '#legacy-focus' },
  });
  const readyToRepair = reduceCompatibilityRedirect(started.state, {
    type: 'history-observed',
    repairId: 0,
    attempt: 2,
    pathname: '/json',
    search: '?source=client',
  });
  assert.deepEqual(readyToRepair.decision, {
    type: 'replace-history',
    repairId: 0,
    href: '/json?source=client#legacy-focus',
  });

  const repairStarted = reduceCompatibilityRedirect(readyToRepair.state, {
    type: 'navigation-started',
    route: { path: '/json', query: 'source=client', hash: '#legacy-focus' },
  });
  assert.deepEqual(repairStarted.decision, { type: 'suppress-navigation-start' });

  const repaired = reduceCompatibilityRedirect(repairStarted.state, {
    type: 'navigation-completed',
    route: { path: '/json', query: 'source=client', hash: '#legacy-focus' },
  });
  assert.equal(repaired.state.pending, null);
  assert.deepEqual(repaired.decision, {
    type: 'commit-navigation',
    path: '/json',
    fragment: 'legacy-focus',
    reportPendingFailure: true,
  });
});

test('compatibility redirect polling fails closed after the existing retry limit', () => {
  const started = reduceCompatibilityRedirect(createCompatibilityRedirectState(), {
    type: 'navigation-started',
    route: { path: '/markdown.html', query: '', hash: '#preview' },
  });
  const timedOut = reduceCompatibilityRedirect(started.state, {
    type: 'history-observed',
    repairId: 0,
    attempt: MAX_COMPATIBILITY_HISTORY_ATTEMPTS,
    pathname: '/foundation',
    search: '',
  });

  assert.equal(timedOut.state.pending, null);
  assert.deepEqual(timedOut.decision, {
    type: 'commit-navigation',
    path: '/markdown',
    fragment: null,
    reportPendingFailure: false,
  });
});

test('compatibility redirect replacement failure clears repair state before recovery', () => {
  const started = reduceCompatibilityRedirect(createCompatibilityRedirectState(), {
    type: 'navigation-started',
    route: { path: '/json.html', query: 'source=client', hash: '#legacy-focus' },
  });
  const inactiveFailure = reduceCompatibilityRedirect(started.state, {
    type: 'replace-rejected',
    repairId: 0,
  });
  assert.deepEqual(inactiveFailure.decision, { type: 'none' });

  const active = reduceCompatibilityRedirect(started.state, {
    type: 'history-observed',
    repairId: 0,
    attempt: 0,
    pathname: '/json',
    search: '?source=client',
  });
  const failed = reduceCompatibilityRedirect(active.state, {
    type: 'replace-rejected',
    repairId: 0,
  });
  assert.equal(failed.state.pending, null);
  assert.equal(failed.state.activeRepairId, null);
  assert.deepEqual(failed.decision, {
    type: 'recover-navigation',
    href: '/json?source=client#legacy-focus',
  });
});

test('new navigation and disposal invalidate queued compatibility retries', () => {
  const started = reduceCompatibilityRedirect(createCompatibilityRedirectState(), {
    type: 'navigation-started',
    route: { path: '/json.html', query: '', hash: '#focus' },
  });
  const superseded = reduceCompatibilityRedirect(started.state, {
    type: 'navigation-started',
    route: { path: '/markdown', query: '', hash: '' },
  });
  const staleObservation = reduceCompatibilityRedirect(superseded.state, {
    type: 'history-observed',
    repairId: 0,
    attempt: 1,
    pathname: '/json',
    search: '',
  });
  assert.deepEqual(staleObservation.decision, { type: 'none' });

  const disposed = reduceCompatibilityRedirect(started.state, { type: 'disposed' });
  const afterDisposal = reduceCompatibilityRedirect(disposed.state, {
    type: 'history-observed',
    repairId: 0,
    attempt: 1,
    pathname: '/json',
    search: '',
  });
  assert.equal(disposed.state.disposed, true);
  assert.equal(disposed.state.pending, null);
  assert.deepEqual(afterDisposal.decision, { type: 'none' });
});
