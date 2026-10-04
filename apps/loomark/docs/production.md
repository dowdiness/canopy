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

Database settings in [`wrangler.jsonc`](../wrangler.jsonc) bind production `AUTH_DB` explicitly, leaving local development databases untouched. The release script enforces the `production` environment and permits only `main` when running in Workers Builds.

---

## 2. Release Pipeline and Safety Gates

Loomark uses a custom deployment script ([`release-loomark.mjs`](../../../scripts/release-loomark.mjs)) that promotes new code after migrations and before health checks:

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
> A failed health check may leave production changed; the script performs no automatic Worker-code or D1 rollback. Rolling back Worker code does **not** roll back applied D1 database migrations. Always author backward-compatible migrations (expand-contract pattern): add columns or tables in one release, migrate consumers in the next, and drop obsolete schemas only after verification.

### Running a Manual Release

Outside Workers Builds, the script requires a clean checkout, including submodules, but does not check the branch. Verify the intended release commit before running an authorized manual release:

```bash
cd apps/loomark
npm ci
npm run release:production
```

Direct `wrangler deploy` bypasses migration checks and health verifications and should never be used for production deployments.

### Release Pre-flight Checks

To run production health checks and isolated release harness tests locally:

```bash
cd apps/loomark
npm run check:production   # Sends read-only health-check requests to production
npm run test:release       # Uses isolated mocks for upload/migration edge cases
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

### Mobile keyboard validation

The standalone viewport regressions simulate a visual-only resize and pan,
including Text and Split, selection, Undo, keyboard dismissal, and pinch zoom.
They also check that the bottom bar disappears without reserving space, returns
on dismissal, and leaves save-failure notices visible at the new bottom edge.
Desktop device emulation does not open a real software keyboard.

Before releasing keyboard-layout changes, check iOS Safari and Android Chrome
on devices: focus near the end of a long document, open and dismiss the keyboard,
type Japanese through IME, move the caret within wrapped lines, and rotate the
device in Text and Split. The current line must remain above the keyboard,
without the bottom bar or its reserved gap consuming the visible area. Closing
the keyboard must restore the bar without losing text, selection, or Undo.
Confirm that pinch zoom still works, save-failure notices remain readable, and
a hardware keyboard or small window alone does not hide the bottom bar.

Also keep the height fixed while narrowing the window and resize the Split
divider without changing the window size. With the caret near the end of a
wrapped document, its line must remain visible. Repeat after switching documents
and crossing the compact/wide breakpoint to check that observation follows the
replacement textarea. Element lookup belongs to the after-render shell; the
caret visibility calculation must remain independent of DOM access.

### Demand-Driven Projection Verification

Run recent document projection tests from `examples/vanilla`:

```bash
cd apps/loomark/examples/vanilla
npm run test:demand
```

This verifies that `DocumentLead` extraction occurs lazily and that collapsed sidebar DOM elements are cleanly disposed without lingering subscriptions or memory leaks.
