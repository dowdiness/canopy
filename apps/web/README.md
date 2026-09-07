# apps/web — Waku Worker

`apps/web` is a Waku 1.0.0-beta.8 application deployed as the
`canopy-examples` Cloudflare Worker. Cloudflare Workers Builds is configured to
build and deploy `main` directly at 100%. Native Cloudflare deployment is
configured and the Stage 12 production cutover was verified; see the
[archived migration plan](../../docs/archive/2026-07-25-waku-unified-web-migration.md)
for the acceptance evidence.

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

## Generated JavaScript

When MoonBit changes affect web consumers, build the FFI artifacts from the
repository root before running consumers that require them:

```bash
just build-js
```

Generated JavaScript is namespaced under
`_build/js/release/build/dowdiness/canopy/ffi/{lambda,json,markdown}/...`.
`waku.config.ts`, tsconfigs, `scripts/build-js.sh`, and
`scripts/package-release.sh` consume these paths. See
[CI/CD](../../docs/CI_CD.md#uploaded-artifacts-build-js) for CI artifact uploads.
The dev-server artifact watcher is owned by this app; a standalone build also
serves non-dev consumers.

## Validation

Prepare generated JavaScript before typechecks or browser suites that depend
on it. This app's commands are below; other frontends keep their commands in
their own READMEs. `.github/workflows/ci.yml` owns the complete frontend matrix
and pinned browser environments.

```bash
cd apps/web
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

`build:deploy:waku` remains as a compatibility alias because Cloudflare Workers Builds external settings currently call it. It initializes pinned submodules, installs MoonBit, bootstraps the registry once through `scripts/moon-update.sh`, builds generated JavaScript, and builds Waku. The external deploy command continues to use `wrangler.waku.jsonc`, which is a symlink to the canonical `wrangler.jsonc`.

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
