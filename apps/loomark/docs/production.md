# Production Release and Validation Runbook

Loomark deploys directly through Cloudflare Workers Builds rather than the shared GitHub Actions matrix used by other applications in this repository.

This runbook covers build configuration, database migrations, release verification gates, and browser validation.

---

## 1. Cloudflare Workers Builds Configuration

Set up the `loomark` Worker in **Settings > Build** with the following parameters:

| Setting | Value |
| --- | --- |
| **Production branch** | `main` |
| **Root directory** | `apps/loomark` |
| **Build command** | *(leave empty — upload triggers Wrangler custom build)* |
| **Deploy command** | `npm run release:production` |

### Required Permissions & Secrets

- **API Token Permissions:** The build token must have both `Workers Scripts: Edit` and `D1: Edit` on the target Cloudflare account.
- **Runtime Secrets:** Store `BETTER_AUTH_SECRET` and Google OAuth credentials (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`) as Worker environment secrets. Never commit them to the repository or inline them in build scripts.
- **Origins:** Set `BETTER_AUTH_URL` to your production domain, and register `<origin>/api/auth/callback/google` in the Google Cloud Console.

Database settings in [`wrangler.jsonc`](../wrangler.jsonc) bind production `AUTH_DB` explicitly, leaving local development databases untouched. The release script enforces the `production` environment and rejects any branch other than `main`.

---

## 2. Release Pipeline and Safety Gates

Loomark uses a custom deployment script ([`release-loomark.mjs`](../../../scripts/release-loomark.mjs)) that promotes new code only after migrations and health checks succeed:

```
Upload Inactive Version ──> Apply D1 Migrations ──> Promote to 100% Traffic ──> Health Check Verification
```

1. **Staged Upload:** Uploads a new Worker build with static assets as an **inactive** version. Traffic remains on the previous release.
2. **Database Migration:** Executes pending migrations against production `AUTH_DB` and verifies that the migration log matches repository history. If migrations fail, the release aborts immediately without promoting code.
3. **Traffic Promotion:** Switches 100% of production traffic to the new version.
4. **Smoke Verification:** Issues automated HTTP checks:
   - `GET /api/auth/ok` must return `200 {"ok":true}`.
   - `GET /api/account` must return `401 {"error":"sign_in_required"}` without following redirects.
   - Confirms the active deployment ID matches the uploaded build.

> [!WARNING]
> Rolling back Worker code does **not** roll back applied D1 database migrations. Always author backward-compatible migrations (expand-contract pattern): add columns or tables in one release, migrate consumers in the next, and drop obsolete schemas only after verification.

### Running a Manual Release

To deploy an authorized release manually from a clean repository checkout:

```bash
cd apps/loomark
npm ci
npm run release:production
```

Direct `wrangler deploy` bypasses migration checks and health verifications and should never be used for production deployments.

### Release Pre-flight Checks

To run dry-run health checks and release harness tests locally without touching production:

```bash
cd apps/loomark
npm run check:production   # Read-only health check against production origin
npm run test:release       # Mock control-plane tests for upload/migration edge cases
```

---

## 3. End-to-End Browser Validation

Run Playwright test suites against fresh production builds locally:

```bash
# Standalone local-first editor tests
./scripts/test-loomark-standalone-e2e.sh

# Cloud sync integration suite (disposable local D1, mock auth)
CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV=false ./scripts/test-loomark-sync-e2e.sh
```

Keep your local dev Worker stopped when running these tests to avoid file conflicts in `dist/`.

### Demand-Driven Projection Verification

Run recent document projection tests from `examples/vanilla`:

```bash
cd apps/loomark/examples/vanilla
npm run test:demand
```

This verifies that `DocumentLead` extraction occurs lazily and that collapsed sidebar DOM elements are cleanly disposed without lingering subscriptions or memory leaks.
