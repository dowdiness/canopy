# Supported Waku architecture on Cloudflare

**Issue:** [Verify the supported Waku architecture on Cloudflare](https://github.com/dowdiness/canopy/issues/948)
**Checked:** 2026-07-25
**Decision:** Use one Waku Cloudflare Worker for the React application and a separate Cloudflare Worker for signaling and Durable Objects. Put the Waku Worker behind the official `waku/adapters/cloudflare` adapter, serve Waku's generated `dist/public` assets through Workers Static Assets, and expose the signaling Worker to the Waku Worker with a Wrangler service binding. Browser WebSocket requests should enter through a Waku route/middleware and be forwarded as the original upgrade request to the service binding; the browser must not try to use the binding directly.

This is a supported composition of the documented Waku and Workers primitives, not a claim that Waku currently embeds Durable Objects or ships a turnkey signaling proxy.

## Target shape

```text
Browser
  | HTTPS documents, RSC payloads, server-function calls,
  | and (if desired) WebSocket upgrade at /signaling/*
  v
Waku Worker
  | Waku Cloudflare adapter: RSC + SSR + server functions
  | Workers Static Assets: dist/public
  | Cloudflare bindings: secrets and SIGNALING service binding
  |-- SIGNALING.fetch(original Request) --> Signaling Worker
                                             | Durable Object namespace
                                             `-- SignalingRoom / WebSocket coordination
```

The Waku Worker and signaling Worker remain independently deployable. The target Worker must exist before the caller is deployed, and both Workers must be in the same Cloudflare account for the ordinary service-binding configuration.

## Capability-by-capability result

| Requirement | Supported arrangement | Boundary / limitation |
|---|---|---|
| React Server Components | Waku's normal server/client boundary, built with `waku/adapters/cloudflare`; components are server components unless marked `'use client'`. | Server code runs in the Worker (or at build time for static routes); it is not shipped in the client bundle. Avoid Node-only dependencies and filesystem assumptions. ([Waku server/client components](https://github.com/wakujs/waku/blob/151d325428197fba10a93c7626b605756a8d880c/docs/guides/learn/server-and-client-components.mdx), [Waku Cloudflare runtime notes](https://github.com/wakujs/waku/blob/151d325428197fba10a93c7626b605756a8d880c/docs/guides/cloudflare.mdx#notes-on-cloudflares-workerd-runtime)) |
| SSR | Use the Cloudflare adapter without `static: true`; dynamic pages render on each request and static pages are prerendered during `waku build`. Waku's Cloudflare starter config uses `@cloudflare/vite-plugin` so build/dev run in workerd. | Request-specific headers/cookies/authentication belong in dynamic rendering. `nodejs_compat` does not make Cloudflare filesystem access available to server-side functions. ([Waku Cloudflare guide](https://github.com/wakujs/waku/blob/151d325428197fba10a93c7626b605756a8d880c/docs/guides/cloudflare.mdx), [Waku rendering model](https://github.com/wakujs/waku/blob/151d325428197fba10a93c7626b605756a8d880c/docs/guides/learn/static-and-dynamic-rendering.mdx)) |
| Static assets | `waku build` emits `dist/public`; Wrangler's `assets.directory` points there. Assets-first routing is the default, with the Worker handling misses; `ASSETS.fetch()` is available when an assets binding is configured. | A static-only deployment is valid only when all required behavior is build-time. RSC payloads generated for static navigation are part of the published output; dynamic routes, APIs, server actions/functions, and request-time auth require the Worker. ([Waku Cloudflare static/dynamic output](https://github.com/wakujs/waku/blob/151d325428197fba10a93c7626b605756a8d880c/docs/guides/cloudflare.mdx#static-vs-dynamic-routing-and-fetching-assets), [Cloudflare Static Assets](https://developers.cloudflare.com/workers/static-assets/), [Waku static deployments](https://github.com/wakujs/waku/blob/151d325428197fba10a93c7626b605756a8d880c/docs/guides/static-deployments.mdx)) |
| Server functions / actions | Waku dispatches server-function calls as `input.type === 'call'`; the handler executes the function and can return its value in an RSC response. Server actions/form submissions are handled through the HTTP path and `tryAction`. | These execute in the Waku Worker and must use Worker-compatible APIs. They are not static-only features. ([Waku Minimal API: request types and server functions](https://github.com/wakujs/waku/blob/151d325428197fba10a93c7626b605756a8d880c/docs/guides/minimal-api.mdx#handlerequestinput-utils), [server-function pattern](https://github.com/wakujs/waku/blob/151d325428197fba10a93c7626b605756a8d880c/docs/guides/minimal-api.mdx#server-functions)) |
| Secrets | Store secrets as Cloudflare Worker secrets and read them through the Waku server environment (`env` from `cloudflare:workers`, or the adapter's `env` path). Keep them in server components/functions/middleware only. | Secrets are per Worker. A secret attached to the signaling Worker is not automatically visible to Waku, and a service binding does not require putting a URL token in the browser. Do not put secret values in client-bundled/Vite `VITE_*` variables. ([Cloudflare Secrets](https://developers.cloudflare.com/workers/configuration/secrets/), [Cloudflare bindings](https://developers.cloudflare.com/workers/runtime-apis/bindings/), [Waku Cloudflare bindings example](https://github.com/wakujs/waku/blob/151d325428197fba10a93c7626b605756a8d880c/docs/guides/cloudflare.mdx#accessing-cloudflare-bindings-execution-context-and-requestresponse-objects)) |
| Waku → separate Signaling Worker | Add a `services` binding to the Waku Worker's Wrangler config, e.g. `{ "binding": "SIGNALING", "service": "crdt-signaling-server" }`. Forward HTTP requests with `env.SIGNALING.fetch(request)`. For browser signaling, forward the original `Upgrade: websocket` request from a Waku route/middleware; Cloudflare documents Workers `fetch` with WebSocket upgrades and service-binding HTTP request forwarding. | This is an HTTP/service-binding composition, not a Durable Object binding in Waku. The service binding is only available to the Waku Worker; the browser reaches the Waku public endpoint. Treat the WebSocket proxy as an integration boundary and verify it with `wrangler dev`/an end-to-end handshake because the Waku guide documents the DO split but does not provide a ready-made WebSocket proxy implementation. ([Waku DO limitation](https://github.com/wakujs/waku/blob/151d325428197fba10a93c7626b605756a8d880c/docs/guides/cloudflare.mdx#accessing-cloudflare-bindings-execution-context-and-requestresponse-objects), [Cloudflare service bindings](https://developers.cloudflare.com/workers/runtime-apis/bindings/service-bindings/), [service-binding HTTP](https://developers.cloudflare.com/workers/runtime-apis/bindings/service-bindings/http/), [Cloudflare WebSockets](https://developers.cloudflare.com/workers/examples/websockets/)) |

## Durable Objects are intentionally separate

Waku's official Cloudflare guide currently states that Durable Objects cannot be defined in a Waku app. Its supported workaround is to create the Durable Object in another Cloudflare Worker and connect from Waku through a service binding. Therefore the existing `SignalingRoom` Worker is the correct ownership boundary for room membership, WebSocket lifecycle, and signaling coordination; do not import its DO class or `DurableObjectNamespace` into the Waku Worker.

Cloudflare's own WebSocket guidance also makes the same architectural division: a Worker or Durable Object can terminate WebSockets, while a Durable Object is the coordination point for multiple clients. The target signaling Worker already follows that model. Its current implementation uses a single `global-room` DO ID and standard WebSocket event handlers; that behavior is an existing application constraint, not something Waku changes. ([local signaling Worker](../../examples/web/signaling-worker.js), [local DO config](../../examples/web/wrangler-signaling.toml), [Cloudflare WebSocket guidance](https://developers.cloudflare.com/durable-objects/best-practices/websockets/))

## Custom server-entry behavior

`src/waku.server.tsx` is the Waku server entry referenced by the Cloudflare Wrangler `main` field. The supported application shape is the official adapter around a router or handler object:

```tsx
import { fsRouter } from 'waku';
import adapter from 'waku/adapters/cloudflare';

const router = fsRouter(import.meta.glob('./pages/**/*.{tsx,ts}'));
export default adapter(router);
```

Custom request behavior should be composed in that entry (for example, a custom `handleRequest` that forwards a signaling path before delegating to the router) or in the adapter's middleware hooks. The adapter's `fetch` is the platform entry: it passes Cloudflare `env` into Waku, invokes the Hono/Waku request pipeline, and supplies the platform-shaped default export. The adapter's `handlers` option is for additional Workers handlers such as queues; it is not a supported replacement for the adapter's own `fetch` handler. ([Waku Cloudflare example](https://github.com/wakujs/waku/blob/151d325428197fba10a93c7626b605756a8d880c/docs/guides/cloudflare.mdx#additional-handlers), [Cloudflare adapter source](https://github.com/wakujs/waku/blob/151d325428197fba10a93c7626b605756a8d880c/packages/waku/src/adapters/cloudflare.ts), [adapter authoring](https://github.com/wakujs/waku/blob/151d325428197fba10a93c7626b605756a8d880c/docs/guides/adapter-authoring.mdx))

A fully custom `unstable_defineServerEntry` is possible for adapter authors, but it bypasses Waku's router/Minimal API conveniences and assumes responsibility for the server-entry `fetch`/`build` contract. It is not needed for this architecture; use the official Cloudflare adapter and customize the request handler only where the signaling boundary requires it. ([Waku direct server entries](https://github.com/wakujs/waku/blob/151d325428197fba10a93c7626b605756a8d880c/docs/guides/adapter-authoring.mdx#direct-server-entries), [Waku Minimal API](https://github.com/wakujs/waku/blob/151d325428197fba10a93c7626b605756a8d880c/docs/guides/minimal-api.mdx#adapter-authors))

## Local repository constraints

The current `examples/web` deployment is not a Waku deployment yet:

- [`examples/web/wrangler.jsonc`](../../examples/web/wrangler.jsonc) declares only `assets.directory: "dist"`; it has no Worker `main`, `services` binding, or Waku `dist/public` output.
- [`examples/web/wrangler-signaling.toml`](../../examples/web/wrangler-signaling.toml) is a separate Worker with the `SIGNALING_ROOM` Durable Object binding and SQLite migration.
- [`examples/web/MODULE_MAP.md`](../../examples/web/MODULE_MAP.md) records the eight Vite HTML surfaces and explicitly places `signaling-server.js`, `signaling-worker.js`, and both Wrangler configs outside those browser entry graphs. Its Vite server relays are development/integration shells, not Waku server entries.

Consequently, the supported target is a migration architecture, not a claim that the current Vite config can be deployed as Waku without changes. The Waku Worker needs its own `src/waku.server.tsx`, Waku build output, Cloudflare-compatible `waku.config.ts`/Vite environments, a Worker `main`, and a `SIGNALING` service binding. The existing signaling Worker can remain separately deployed and owned by its current Wrangler config.

## Source register

- Waku official repository at the exact revision checked: [`151d3254`](https://github.com/wakujs/waku/tree/151d325428197fba10a93c7626b605756a8d880c).
- Cloudflare Workers documentation pages linked above are first-party platform documentation; their Markdown views expose the page update dates and canonical content.
- Repository-local constraints are cited only as local implementation evidence; they are not used as authority for Waku or Cloudflare platform support.
