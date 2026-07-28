# examples/web — Waku Worker

`examples/web` is a Waku 1.0.0-beta.8 application deployed as the `canopy-examples` Cloudflare Worker. Every push to `main` builds and deploys at 100% through Cloudflare Workers Builds.

## Canonical routes

| Route | Demo |
|-------|------|
| `/` | Demo Hub (non-redirecting) |
| `/ml` | Mini-ML (lambda calculus with AST visualization) |
| `/json` | JSON structural editor |
| `/markdown` | Markdown block/raw/preview editor |
| `/journey` | Journey proposals |
| `/posts` | Local posts with related-post retrieval |
| `/memo` | Memo typo correction (development/local-only) |
| `/resume` | Session inspection workbench |
| `/genui` | Generative UI JSX streaming |

Seven legacy `.html` aliases (`/json.html`, `/markdown.html`, `/memo.html`, `/posts.html`, `/resume.html`, `/genui.html`, `/genui-possibilities.html`) return 308 to their canonical route. `/index.html` remains a compatibility URL that renders the Hub without redirect.

## Current setup

The workspace contains:
- `src/pages/` — Waku filesystem routes (9 canonical route pages plus `_root.tsx`, `_layout.tsx`, `404.tsx`, `foundation.tsx`)
- `src/features/` — feature-owned browser, core, protocol, and route modules
- `src/shared/` — reusable types, adapters, route-lifecycle module, and shell
- `server/waku/` — Waku Worker request policy, signaling proxy, observability
- `server/vite/` — retained local development adapters (AST Grep, Resume chat, GenUI feasibility, MoonBit artifacts)
- `waku.config.ts` — Waku configuration with Cloudflare adapter
- `wrangler.jsonc` — canonical Cloudflare Worker configuration
- `wrangler.waku.jsonc` — compatibility symlink retained for external Build/Deploy settings
- `vite-plugin-moonbit.ts` — MoonBit virtual module plugin reused by Waku's Vite integration

`vite`, `@tailwindcss/vite`, and the MoonBit artifact plugin remain because Waku uses Vite internally; `waku.config.ts` imports the Tailwind and MoonBit plugins directly.

## Validation

```bash
cd examples/web
npm ci
npm run dev                              # Waku dev server (localhost:3000)
npm run build                            # Production build
npm run preview                          # Preview production build
npm run typecheck                        # TypeScript + Worker config types
npm run check:boundaries                 # Route/feature/shared ownership
npm run test:boundaries                  # Boundary checker tests
npm run test:foundation                  # Lifecycle reducer, provider, manifest tests
npm run check:waku-bundles               # Client/server bundle boundary assertions
npm run check:waku-types                 # Generated Cloudflare binding types
npm run test:waku:e2e                    # Playwright canonical route suites
npm run test:waku:preview                # Production preview suites
npm run test:waku:workerd                # Local workerd smoke (workerd + signaling)
```

## Cloudflare deployment

Cloudflare Workers Builds deploys every `main` push at 100% to `canopy-examples`:

| Setting | Value |
|---------|-------|
| Build command | `npm ci && npm run build:deploy:waku` |
| Deploy command | `npx wrangler deploy --config wrangler.waku.jsonc --env production` |

`build:deploy:waku` remains as a compatibility alias because Cloudflare Workers Builds external settings currently call it. It initializes pinned submodules, installs MoonBit, builds generated JavaScript, and builds Waku. The external deploy command continues to use `wrangler.waku.jsonc`, which is a symlink to the canonical `wrangler.jsonc`.

### Wrangler startup validation

The correct local validation sequence for a new Wrangler startup check is:

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

With pinned Wrangler 4.114, `check startup --config` can resolve the default project instead of the intended multipart Worker. Always pass the bundle produced by the matching dry-run through `--worker`.

### Rollback

Select the previous successful deployment in the Cloudflare dashboard or use:

```bash
npx wrangler rollback <previous-version-id> --config wrangler.waku.jsonc --env production
```

## Retained artifacts

- `spike-block-input.html` — inactive investigation surface (not a Waku route)

See [`MODULE_MAP.md`](./MODULE_MAP.md) for route→feature ownership, shared contracts, and test ownership. See [`CLOUDFLARE_DEPLOYMENT.md`](./CLOUDFLARE_DEPLOYMENT.md) for the full deployment runbook.
