# Waku Worker cutover and rollback runbook

This is the canonical deployment runbook for `examples/web`. The Waku Worker is
not yet the production target: local workerd readiness is implemented, but the
repository and Cloudflare prerequisites below must be completed before any
staging or production traffic change.

## Runtime boundary

```text
browser
  └─ same-origin /signaling
       └─ canopy-web-waku-{preview|production}
            └─ SIGNALING service binding
                 └─ crdt-signaling-server
                      └─ SignalingRoom Durable Object
```

The Waku Worker owns documents, RSC, static assets, compatibility redirects,
safe error responses, and the same-origin ingress. The existing Signaling
Worker continues to own its protocol, room state, and Durable Object migration.
Both Workers must be in the same Cloudflare account. Never deploy or roll back
the Signaling Worker as a side effect of a Waku release.

`wrangler.waku.jsonc` defines distinct `preview` and `production` Worker names.
It contains no provider secret and binds the existing `crdt-signaling-server`
service in both environments.

## Mandatory prerequisites

Do not add or enable a privileged deployment workflow until all of these are
true:

1. `main` is protected and cannot bypass the repository-owned CI gate.
2. GitHub `staging` and `production` environments exist, require reviewers, and
   cannot be created implicitly by a workflow.
3. Cloudflare credentials are environment-scoped, least-privilege secrets. The
   token scope and account containing both Workers have been verified.
4. The preview URL and the production hostname/route are recorded as
   environment variables. No hostname is inferred from the legacy Pages site.
5. The target Signaling Worker exists in that account and its independent
   handshake is healthy.
6. An owner has approved the observability policy. Structured logs are enabled;
   automatic traces remain disabled because Cloudflare traces persist URL query
   strings. Full trace acceptance is blocked until an approved redaction policy
   exists.

At the time this runbook was written, these repository prerequisites were not
configured. A push must therefore remain incapable of deploying Waku.

## Pinned local readiness

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

## Exact release candidate contract

Only a completed `CI` workflow caused by a push to `main` may become a release
candidate. Before entering a protected environment, a deployment controller
must run the pure checks in `scripts/waku-release-gate-core.mjs` and reject the
candidate unless all of the following are exact:

- workflow conclusion is `success`;
- repository is exactly `dowdiness/canopy` and workflow path is exactly
  `.github/workflows/ci.yml`; the mutable display name alone is insufficient;
- `All Checks Passed`, `Build Waku Web Foundation`, `Waku Web Foundation E2E`,
  and `Waku Worker Foundation Smoke` each occur exactly once and are
  `completed/success`; each job must carry the selected run ID, attempt, and
  head SHA, and `skipped` is not accepted;
- triggering `head_sha`, checked-out SHA, artifact manifest SHA, and current
  `main` tip are identical;
- artifacts are selected by explicit run ID and attempt, never “latest by
  name”; their names are `waku-web-build-<attempt>` and
  `waku-web-release-manifest-<attempt>`;
- the manifest's config digest and every extracted `dist` file size/SHA-256
  recompute exactly;
- the candidate is no older than the shared 30-day artifact retention window;
- the target GitHub environment is protected.

Recheck the current `main` tip immediately before upload and immediately before
traffic changes. Deployment consumes the verified CI artifact; it never
rebuilds source in a privileged workflow.

## Staging sequence

After the prerequisites are present and an authorized owner enables staging:

1. Download both artifacts for the selected run ID and attempt and verify the
   manifest before any Cloudflare command.
2. Upload a non-production version with pinned Wrangler and capture its JSONL
   record through `WRANGLER_OUTPUT_FILE_PATH`. Require exactly one successful
   `version-upload` result and retain its version ID.
3. Deploy that version only to the configured preview target.
4. Record `npx wrangler deployments status --config wrangler.waku.jsonc
   --env preview --json`.
5. Run the same route and WebSocket smoke contract against the real preview URL.
6. Stop on any deterministic failure. Do not promote a merely retried result.

Do not encode a Wrangler output parser from guessed fixtures. Capture output
from the pinned version in authorized staging first, then add strict fixtures
and a fail-closed parser.

## Production sequence

Production requires a separate protected approval after staging passes.

1. Record the current production deployment and every active version/traffic
   weight with `npx wrangler deployments status --config wrangler.waku.jsonc
   --env production --json`.
2. Upload the already verified artifact with `npx wrangler versions upload
   --config wrangler.waku.jsonc --env production`; record the previous stable
   and new version IDs, CI run ID/attempt, commit SHA, config digest, and
   artifact digest.
3. Shift a bounded percentage with `npx wrangler versions deploy
   <version-specs> --config wrangler.waku.jsonc --env production`; use
   versioned Worker assets from the same upload and do not mix artifacts across
   commits.
4. On the configured production hostname, verify canonical routes, aliases,
   RSC navigation, assets, 404/error behavior, availability states,
   state/focus/history, and same-origin signaling.
5. Observe structured logs for the agreed window. The only application record
   fields are `event`, `deploymentVersion`, `routeClass`, `capability`, `status`,
   and `errorCategory`. Never log URLs, query strings, headers, payloads,
   imported sessions, API keys, chat text, error messages, or stacks.
6. Increase traffic only after each smoke and observation gate passes. Record
   `npx wrangler deployments status --config wrangler.waku.jsonc --env
   production --json` after every change.

Stage 12 (Vite and legacy-entry retirement) starts only after the production
acceptance window succeeds. It is not part of a staging deployment.

## Rollback

Roll back immediately for a release-attributable uncaught Worker error,
canonical-route 5xx, asset/RSC version mismatch, deterministic route smoke
failure, or failed signaling proxy handshake.

1. Stop further traffic changes.
2. Restore the recorded previous Waku version with `npx wrangler rollback
   <previous-version-id> --config wrangler.waku.jsonc --env production`, then
   verify the authoritative status with `npx wrangler deployments status
   --config wrangler.waku.jsonc --env production --json`.
3. Rerun canonical, asset/RSC, error, and same-origin signaling smoke.
4. If Worker rollback or hostname routing fails, point the production hostname
   back to the retained Pages deployment.
5. Do not roll back the Signaling Worker and do not clear Posts browser storage.

Retained Pages fallback evidence at the start of #979:

- stable URL: `https://canopy-lambda-editor.pages.dev`
- immutable preview: `https://f48c4fe0.canopy-lambda-editor.pages.dev`
- source commit: `54a6118dd8dc98af23580f24784bf480f4e4841a`
- GitHub Actions run/job: `30228528405` / `89862955038`

Verify that evidence and hostname ownership again immediately before cutover.
Keep the Pages deployment available throughout the Waku acceptance window.
