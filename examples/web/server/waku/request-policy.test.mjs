import assert from 'node:assert/strict';
import test from 'node:test';
import { Hono } from 'hono/tiny';
import {
  decideWakuRequest,
  SIGNALING_PATH,
} from './request-policy.ts';
import { createWorkerTelemetryRecord } from './observability.ts';
import { createWakuRequestMiddleware } from './signaling-proxy.ts';

const aliases = [
  ['/json.html', '/json'],
  ['/markdown.html', '/markdown'],
  ['/memo.html', '/memo'],
  ['/posts.html', '/posts'],
  ['/resume.html', '/resume'],
  ['/genui.html', '/genui'],
  ['/genui-possibilities.html', '/journey'],
];

test('maps only the seven exact compatibility paths to permanent redirects', () => {
  aliases.forEach(([pathname, canonical]) => {
    assert.deepEqual(
      decideWakuRequest({
        pathname,
        search: '?source=legacy&mode=review',
      }),
      {
        action: 'redirect',
        location: `${canonical}?source=legacy&mode=review`,
        routeClass: 'compatibility-alias',
        capability: 'navigation',
      },
    );
    assert.deepEqual(
      decideWakuRequest({
        pathname: `/RSC/R${pathname}.txt`,
        search: '?query=kept',
      }),
      {
        action: 'redirect',
        location: `/RSC/R${canonical}.txt?query=kept`,
        routeClass: 'compatibility-alias',
        capability: 'rsc',
      },
    );
  });

  for (const pathname of ['/index.html', '/json.html/child', '/unknown.html']) {
    assert.equal(
      decideWakuRequest({ pathname, search: '' }).action,
      'continue',
    );
  }
});

test('delegates the exact signaling ingress without owning endpoint semantics', () => {
  assert.deepEqual(
    decideWakuRequest({
      pathname: SIGNALING_PATH,
      search: '?room=kept-by-request',
    }),
    {
      action: 'proxy-signaling',
      routeClass: 'signaling',
      capability: 'websocket',
    },
  );
  assert.equal(
    decideWakuRequest({ pathname: '/json', search: '' }).action,
    'continue',
  );
  assert.deepEqual(
    decideWakuRequest({ pathname: '/assets/app-123.js', search: '?immutable=1' }),
    {
      action: 'serve-static-asset',
      routeClass: 'static-asset',
      capability: 'static-asset',
    },
  );
});

test('builds a closed privacy-safe telemetry record', () => {
  const secret = 'private-session-and-api-key';
  const record = createWorkerTelemetryRecord({
    deploymentVersion: 'version-123',
    routeClass: 'canonical-demo',
    capability: 'application',
    status: 200,
    errorCategory: 'none',
    requestUrl: `https://example.test/json?draft=${secret}`,
    requestBody: secret,
    requestHeaders: { authorization: secret },
  });

  assert.deepEqual(Object.keys(record), [
    'event',
    'deploymentVersion',
    'routeClass',
    'capability',
    'status',
    'errorCategory',
  ]);
  assert.equal(Object.isFrozen(record), true);
  assert.doesNotMatch(JSON.stringify(record), new RegExp(secret));
});

function requestApp({
  signaling,
  records,
  assets = { fetch: async () => new Response('asset response') },
}) {
  const app = new Hono();
  app.use(createWakuRequestMiddleware({
    app,
    emit: (record) => records.push(record),
  }));
  app.all('*', (context) => context.text('waku response'));
  return {
    fetch: (request) => app.fetch(request, {
      ASSETS: assets,
      SIGNALING: signaling,
      WORKER_VERSION: { id: 'version-123' },
    }),
  };
}

test('forwards the original static asset Request through the asset binding', async () => {
  const records = [];
  let forwardedRequest;
  const app = requestApp({
    records,
    assets: {
      fetch: async (request) => {
        forwardedRequest = request;
        return new Response('immutable asset', {
          status: 200,
          headers: { 'cache-control': 'public, max-age=31536000, immutable' },
        });
      },
    },
    signaling: { fetch: async () => new Response(null, { status: 204 }) },
  });
  const request = new Request('https://example.test/assets/app-123.js?immutable=1');

  const response = await app.fetch(request);

  assert.equal(forwardedRequest, request);
  assert.equal(await response.text(), 'immutable asset');
  assert.equal(
    response.headers.get('cache-control'),
    'public, max-age=31536000, immutable',
  );
  assert.deepEqual(records, [{
    event: 'canopy.worker.request',
    deploymentVersion: 'version-123',
    routeClass: 'static-asset',
    capability: 'static-asset',
    status: 200,
    errorCategory: 'none',
  }]);
});

test('forwards the original WebSocket Request through the service binding', async () => {
  const records = [];
  let forwardedRequest;
  const app = requestApp({
    records,
    signaling: {
      fetch: async (request) => {
        forwardedRequest = request;
        return new Response(null, {
          status: 204,
          headers: { 'x-signaling-test': 'forwarded' },
        });
      },
    },
  });
  const request = new Request(
    `https://example.test${SIGNALING_PATH}?room=original`,
    { headers: { Upgrade: 'websocket', 'x-client-marker': 'unchanged' } },
  );

  const response = await app.fetch(request);

  assert.equal(forwardedRequest, request);
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('x-signaling-test'), 'forwarded');
  assert.deepEqual(records, [{
    event: 'canopy.worker.request',
    deploymentVersion: 'version-123',
    routeClass: 'signaling',
    capability: 'websocket',
    status: 204,
    errorCategory: 'none',
  }]);
});

test('handles redirects, non-upgrades, and binding failures without leaking details', async () => {
  const records = [];
  const secret = 'binding-error-with-private-chat';
  const app = requestApp({
    records,
    assets: { fetch: async () => { throw new Error(secret); } },
    signaling: {
      fetch: async (request) => {
        if (request.headers.get('upgrade') === null) {
          return new Response('Expected WebSocket upgrade', { status: 426 });
        }
        throw new Error(secret);
      },
    },
  });

  const redirect = await app.fetch(new Request(
    'https://example.test/json.html?source=legacy',
  ));
  assert.equal(redirect.status, 308);
  assert.equal(redirect.headers.get('location'), '/json?source=legacy');

  const assetUnavailable = await app.fetch(new Request(
    'https://example.test/assets/private-session.js',
  ));
  assert.equal(assetUnavailable.status, 502);
  assert.equal(await assetUnavailable.text(), 'Asset temporarily unavailable');

  const nonUpgrade = await app.fetch(new Request(
    `https://example.test${SIGNALING_PATH}`,
  ));
  assert.equal(nonUpgrade.status, 426);

  const unavailable = await app.fetch(new Request(
    `https://example.test${SIGNALING_PATH}`,
    { headers: { Upgrade: 'websocket' } },
  ));
  assert.equal(unavailable.status, 502);
  assert.equal(await unavailable.text(), 'Signaling temporarily unavailable');
  assert.doesNotMatch(JSON.stringify(records), new RegExp(secret));
  assert.deepEqual(records.map((record) => record.errorCategory), [
    'none',
    'asset-unavailable',
    'none',
    'signaling-unavailable',
  ]);
});

test('turns uncaught Waku failures into safe document and RSC responses', async () => {
  const records = [];
  const secret = 'private-stack-and-imported-session';
  const app = new Hono();
  app.use(createWakuRequestMiddleware({
    app,
    emit: (record) => records.push(record),
  }));
  app.all('*', () => { throw new Error(secret); });
  const environment = {
    SIGNALING: { fetch: async () => new Response(null, { status: 204 }) },
    WORKER_VERSION: { id: 'version-safe-error' },
  };

  const documentResponse = await app.fetch(new Request(
    'https://example.test/json?draft=private',
    { headers: { Accept: 'text/html' } },
  ), environment);
  assert.equal(documentResponse.status, 500);
  assert.match(await documentResponse.text(), /Route temporarily unavailable/);

  const rscResponse = await app.fetch(new Request(
    'https://example.test/RSC/R/json.txt?draft=private',
    { headers: { Accept: 'text/x-component' } },
  ), environment);
  assert.equal(rscResponse.status, 500);
  assert.equal(await rscResponse.text(), 'Route temporarily unavailable');
  assert.doesNotMatch(JSON.stringify(records), new RegExp(secret));
  assert.deepEqual(records.map((record) => record.errorCategory), [
    'waku-unhandled',
    'waku-unhandled',
  ]);
});
