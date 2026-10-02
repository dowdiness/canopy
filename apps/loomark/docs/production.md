# Loomark Production Release and Validation

This document describes the deployment pipeline, Cloudflare Workers configuration, release verification, and production validation tests for Loomark.

---

## 1. Production Releases

Loomark releases through Cloudflare Workers Builds, not the other applications' GitHub Actions deployment matrix. After merging the release tooling, configure the `loomark` Worker's **Settings > Build** once:

| Setting | Value |
| --- | --- |
| Production branch | `main` |
| Root directory | `apps/loomark` |
| Build command | Leave empty; the upload runs the Wrangler custom build |
| Deploy command | `npm run release:production` |

The build token needs **Workers Scripts: Edit** and **D1: Edit** on the configured account. The automatically generated Workers Builds token may need D1 permission added. Keep Google credentials and the Better Auth secret in the Worker's runtime secrets, not in the repository or build command. `BETTER_AUTH_URL` must be the production origin, and the Google client must allow its `/api/auth/callback/google` redirect URI.

The production environment in [`wrangler.jsonc`](../wrangler.jsonc) pins the existing account and `AUTH_DB` database ID without changing local development's D1 identity. The release command explicitly selects this environment; inherited `CLOUDFLARE_ENV` cannot redirect it elsewhere. Do not use the release command for preview builds: it rejects Workers Builds branches other than `main`.

### Release Workflow

The [release command](../../../scripts/release-loomark.mjs):

1. Builds and uploads one **inactive** Worker version, including its assets.
2. Applies pending migrations to production `AUTH_DB` and checks that every repository migration appears in its migration history.
3. Promotes that exact version to 100% of production traffic.
4. Requires JSON `200 {"ok":true}` from `/api/auth/ok` and anonymous `401 {"error":"sign_in_required"}` from `/api/account`, without following redirects, then confirms the uploaded version is still the sole deployment.

A failed build/upload cannot start migrations. Failed or incomplete migrations cannot promote the new Worker. Failure after promotion marks the release failed but does **not** automatically roll back code or D1. Earlier successful migrations may remain applied after a later migration fails. Use backward-compatible schema changes: add, switch consumers, then remove in a later reviewed release. Destructive changes require a separate recovery plan; rolling back Worker code does not undo database changes.

Use Workers Builds as the production release owner. Do not overlap manual releases with it: the final version check detects a superseding deployment but is not a cross-machine lock. Changes to routes, triggers, or Durable Object migrations need a separately reviewed deployment procedure; version promotion does not apply all non-versioned Worker settings.

For an explicitly authorized manual release, run `npm ci` and `npm run release:production` from `apps/loomark` in a clean checkout, including submodules. The build bootstraps pinned dependencies; do not release from a development checkout with uncommitted work. Direct `wrangler deploy` bypasses the migration and verification gates and is not the normal release path.

### Production Checks and Release Regression Tests

Read-only production checks and isolated release regression tests:

```bash
cd apps/loomark
npm run check:production
npm run test:release
```

The production check does not sign in, create documents, or write to D1. The release tests use a disposable control-plane simulator and local HTTP server; they do not deploy. They cover preparation/migration failures, incomplete schema history, unhealthy responses, and superseded deployments. They do not replace Google login and document-sync acceptance checks.

Wrangler is pinned in `package.json`. The upload ID is read from its documented [NDJSON output](https://developers.cloudflare.com/workers/wrangler/system-environment-variables/), not parsed from terminal prose. Workers Builds supports an npm [deploy command](https://developers.cloudflare.com/workers/ci-cd/builds/configuration/).

---

## 2. Production Validation

```bash
./scripts/test-loomark-standalone-e2e.sh
CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV=false ./scripts/test-loomark-sync-e2e.sh
```

This performs a clean Warren production build, rejects removed Worker and private-control artifacts, and runs Playwright against the release output. The sync suite uses a separate test-only Worker configuration and disposable local D1; production authentication configuration is unchanged. Disable `.env` loading so local Google OAuth settings cannot override the test Worker's origin. Keep the development Worker stopped while testing: its custom rebuild replaces the same `dist` directory served by the standalone suite.

### Demand-Driven Projection Tests

Demand tests use `npm run test:demand` from `examples/vanilla`. Its [artifact builder](../../../scripts/build-loomark-demand-artifact.sh) copies the workspace to a temporary directory and adds a test-only JS FFI extraction counter plus a small query-selected static public-feature [fixture](../examples/vanilla/fixtures/recent-dialog-demand.mbt) only there; no production source or `dist` is instrumented. The [fixture check](../examples/vanilla/tests/demand.spec.ts) exercises hidden navigation with a dialog-only consumer: its cold dialog needs all three leads to disambiguate duplicate labels, but it is not reachable from the current modal user path.

The same app tests cover hiding during pending deletion and reopening without resurrecting the row, as well as replacing row DOM while retaining leads. That DOM check is not direct reactive-scope or memory proof; the feature's visible [`switch_by`](../internal/recent_documents/recent_documents.mbt) source establishes its ownership boundary, and Rabbita's [`assoc`/`switch_by` cleanup tests](../../../deps/rabbita/rabbita/internal/duplix/duplix_test.mbt) cover the framework disposal behavior.
