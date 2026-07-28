# Waku Worker deployment and rollback

This is the canonical deployment runbook for `examples/web`. Cloudflare
Workers Builds owns the production build and deployment through its native
GitHub integration. Every push to `main` builds the selected commit and deploys
it at 100% to the `canopy-examples` Worker. GitHub Actions does not deploy this
application.

## Runtime boundary

```text
browser
  └─ same-origin /signaling
       └─ canopy-examples
            └─ SIGNALING service binding
                 └─ crdt-signaling-server
                      └─ SignalingRoom Durable Object
```

The Waku Worker owns documents, RSC, static assets, compatibility redirects,
safe error responses, and the same-origin ingress. The existing Signaling
Worker continues to own its protocol, room state, and Durable Object migration.
Both Workers must be in the same Cloudflare account. Never deploy or roll back
the Signaling Worker as a side effect of a Waku release.

`wrangler.waku.jsonc` keeps preview and production bindings separate. It
contains no provider secret and binds the existing `crdt-signaling-server`
service in both environments. Structured logs remain enabled and automatic
traces remain disabled.

## Cloudflare Workers Builds settings

Configure the connected `dowdiness/canopy` repository with these values:

| Setting | Value |
|---|---|
| Production Worker | `canopy-examples` |
| Production branch | `main` |
| Root directory | `examples/web` |
| Build command | `npm ci && npm run build:deploy:waku` |
| Deploy command | `npx wrangler deploy --config wrangler.waku.jsonc --env production` |
| Build watch paths | All repository paths; no exclusions |
| Non-production branch builds | Disabled |
| Build variable | `NODE_VERSION=24` |
| Build variable | `SKIP_DEPENDENCY_INSTALL=1` |

The explicit `npm ci` owns dependency installation. `build:deploy:waku`
initializes the pinned public Git submodules, installs the MoonBit toolchain and
package dependencies, builds the generated JavaScript, and builds Waku. The
deploy command uses the lockfile-pinned Wrangler and publishes the new version
directly; it does not create a gradual traffic split.

## Local validation

Use Node 24 and the repository lockfile. Do not install Wrangler globally.

```bash
cd examples/web
npm ci
npm run typecheck
npm run test:foundation
npm run build:waku
npm run check:waku-bundles
npm run check:waku-types
npx wrangler deploy --config wrangler.waku.jsonc --dry-run --env preview
npx wrangler check startup --config wrangler.waku.jsonc --env preview
npx wrangler deploy --config wrangler.waku.jsonc --dry-run --env production
npx wrangler check startup --config wrangler.waku.jsonc --env production
npm run test:waku:workerd
```

The workerd command starts Waku and the Signaling Worker together with Wrangler
multi-worker development. It verifies canonical documents and RSC, all seven
document/RSC aliases, assets, 404s, production capability absence, signaling
OPTIONS/non-upgrade behavior, and a real join/`peer_list` WebSocket exchange.
It intentionally omits `--env preview`: pinned Wrangler applies one `--env` to
every auxiliary config, while `wrangler-signaling.toml` has no named preview
environment.

## Automatic production sequence

1. A push to `main` triggers Cloudflare Workers Builds for the connected
   repository.
2. Cloudflare runs the configured build command from `examples/web`.
3. Cloudflare runs the configured `wrangler deploy` command only after the
   build succeeds.
4. Wrangler publishes the new deployment at 100% to `canopy-examples`.
5. Confirm the commit and successful deployment in the Cloudflare build log,
   then verify the production hostname.

The repository CI remains an independent check; it is not the deployment
controller and its Waku artifacts are not downloaded by Workers Builds.

## Rollback

For a bad production deployment, select the previous successful deployment in
the Cloudflare dashboard and roll it back. The equivalent pinned CLI command is:

```bash
npx wrangler rollback <previous-version-id> \
  --config wrangler.waku.jsonc --env production
npx wrangler deployments status \
  --config wrangler.waku.jsonc --env production --json
```

Rerun the canonical route, asset/RSC, error, and same-origin signaling checks.
Then revert the bad source commit on `main` and push the revert so the automatic
build path and repository state converge again. Do not roll back the Signaling
Worker or clear Posts browser storage as a side effect.
