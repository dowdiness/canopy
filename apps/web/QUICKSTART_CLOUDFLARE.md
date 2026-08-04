# Cloudflare local quick start

This quick start validates the Waku Worker and its existing Signaling Worker
binding without changing Cloudflare. Production release and rollback policy is
in [CLOUDFLARE_DEPLOYMENT.md](CLOUDFLARE_DEPLOYMENT.md).

## Prerequisites

- Node.js 24
- the repository's npm lockfile
- generated MoonBit JavaScript artifacts (normally produced by the root build)

Use the pinned local Wrangler dependency; do not install it globally.

```bash
cd apps/web
npm ci
npm run typecheck
npm run test:foundation
npm run build:waku
npm run check:waku-bundles
npm run check:waku-types
```

Run both Workers under one local Wrangler process and exercise the service
binding:

```bash
npm run test:waku:workerd
```

That command verifies documents, canonical and compatibility RSC routes,
hashed assets, 404 and production-unavailable states, plus a same-origin
WebSocket join/`peer_list` exchange through `/signaling`.

Optional non-deploying Cloudflare bundle checks:

```bash
npx wrangler deploy --config wrangler.waku.jsonc --dry-run --env preview \
  --outfile "${TMPDIR:-/tmp}/canopy-waku-preview.bundle"
npx wrangler check startup \
  --worker "${TMPDIR:-/tmp}/canopy-waku-preview.bundle"
npx wrangler deploy --config wrangler.waku.jsonc --dry-run --env production \
  --outfile "${TMPDIR:-/tmp}/canopy-waku-production.bundle"
npx wrangler check startup \
  --worker "${TMPDIR:-/tmp}/canopy-waku-production.bundle"
```

Do not run a live deploy from this guide. Production deployment is owned by the
Cloudflare Workers Builds GitHub integration described in the deployment
runbook; pushes to `main` deploy the Waku application to `canopy-examples`.
