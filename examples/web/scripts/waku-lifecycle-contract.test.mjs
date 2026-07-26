import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const wakuPackage = require('waku/package.json');
const clientSourceUrl = import.meta.resolve('waku/router/client');
const clientSourcePath = fileURLToPath(clientSourceUrl);
const clientSource = fs.readFileSync(clientSourcePath, 'utf8');
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
