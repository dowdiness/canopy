# Production Release and Validation Runbook

Loomark deploys directly through Cloudflare Workers Builds rather than the shared GitHub Actions matrix used by other applications in this repository.

- For a high-level product introduction and philosophy, see the [Loomark README](../README.md).
- For client-side UI and DOM architecture, see [architecture.md](architecture.md).
- For remote sync and replica storage, see [sync-and-account.md](sync-and-account.md).
- For the full document map, see [Documentation Index](README.md).

This runbook covers build configuration, database migrations, release verification gates, and browser validation.

---

## Table of Contents

1. [Cloudflare Workers Builds Configuration](#1-cloudflare-workers-builds-configuration)
2. [Release Pipeline and Safety Gates](#2-release-pipeline-and-safety-gates)
3. [End-to-End Browser Validation](#3-end-to-end-browser-validation)

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

### Test contracts

Name each standalone test after the user-visible invariant and the state
transition that could break it. Observe the application, not its fixture helpers.

| Boundary | What the test must protect |
| --- | --- |
| Native editing | Exact text, selection, composition, Undo, and continued editing after navigation or Sync. |
| Layout and accessibility | Reachable controls, visible focus and graphics, non-overlapping content, and actual pane resizing. |
| Asynchronous work | Only committed content appears in Preview and document names; late work cannot overwrite newer state. |
| Persistence | Durable acknowledgements, recovery after failure, no lost text or redundant writes, and correct reload/export results. |

Do not pin CSS defaults, icon classes, DOM identity, timer counts, or textarea
getter counts. For example, assert that keyboard resizing changes the pane, not
that a library slider moves from 50 to 51. Check icon-only controls' rendered
interiors rather than a particular mask implementation or a golden screenshot.
Wait for the required interaction to become possible, not for a particular
opacity or animation duration. Reduced-motion checks are different: the absence
of motion is itself the requested behavior.

Keep numeric fixtures that distinguish real boundaries: compact/wide layouts,
zoom factors, viewport clipping, keyboard estimates, and explicit latency limits.
Keep controlled delays and storage failures where they make races reproducible;
assert the resulting visible or persisted state rather than scheduler mechanics.
Direct IndexedDB helper timings are not Loomark E2E coverage.

Cloud-sync assertions must identify the intended Document ID and verify its exact
remote text under the signed-in account. Matching text in another document is not
evidence that the Editing Document synchronized; document text is not unique.

### Mobile Keyboard & Viewport Validation

Virtual keyboard behavior and viewport resizing are critical user experience contracts on mobile devices.

#### 1. Automated Viewport Regressions

- **Synthetic Resizing:** Regressions simulate visual-only resize and pan across Text and Split modes, checking selection, Undo, keyboard dismissal, and pinch zoom.
- **Bar Visibility & Edge Margins:** Verifies that the bottom bar disappears without reserving space, remains hidden when panning to the bottom of the layout, returns on dismissal, and keeps save-failure notices visible at the new bottom edge.
- **Caret Boundaries:** Caret checks must cover the whole line (not just its center) outside visible bars. Desktop device emulation does not open real software keyboards or simulate mobile compositing.
- **Chromium Native Scaling Test:** Tests viewport recovery without overriding viewport getters: start at 380px, zoom to 2×, then grow to 844px. The layout must recover to 844px rather than freezing in a 380px frame.
- **Visual Diffing:** Compare scrolled Text, Split, and Preview screenshots at compact and wide widths. `pointer-events: none` overlays are skipped by `elementFromPoint` but can still obscure text.

#### 2. Real-Device Verification Checklist (iOS Safari & Android Chrome)

Before releasing layout or viewport changes, test on actual iOS Safari and Android Chrome devices:

- [ ] **Native Content Resizing:** Test with an actual Android keyboard and the browser address bar at the bottom. Record `outerHeight` alongside `innerHeight` (window resizing changes both; keyboard resizing can leave outer height unchanged).
- [ ] **Caret Visibility:** Focus near the end of a long document and open the keyboard. The current writing line must remain clearly visible above the keyboard.
- [ ] **IME & Composition:** Type Japanese (or other IME languages), move the caret within wrapped lines, and rotate the device between portrait and landscape in Text and Split modes.
- [ ] **Bottom-Bar Auto-Hide:** When the keyboard opens, neither the bottom bar nor its reserved gap should consume visible space. Its edge fade and blur must disappear completely.
- [ ] **Keyboard Dismissal & State Retention:** Closing the keyboard must restore the bar without losing text, selection, focus, or native Undo history.
- [ ] **Open-Keyboard Reload:** Reload the page while the virtual keyboard is open. Confirm the layout does not freeze or leave obsolete offsets.
- [ ] **Pinch Zoom Interaction:** Repeat opening and dismissing the keyboard while zoomed. The layout must continue responding to height changes without retaining an obsolete top offset after recovery. Confirm that hardware keyboards or small browser windows alone do not hide the bottom bar.
- [ ] **Split Divider Adjustment & Replacement Textarea:** Keep the height fixed while narrowing the window, then resize the Split divider. The caret line near the end of a wrapped document must remain visible. Repeat after switching documents and crossing the compact/wide breakpoint to verify that observation follows the replacement textarea.

#### 3. Diagnosing Device-Only White Bands or Artifacts

If an unexplained white band appears on a physical device:

1. **Capture Diagnostic State:** Capture full screenshots (including the keyboard, browser chrome, and URL).
2. **Inspect Viewport Geometry:** Record:
   - `visualViewport`: `height`, `offsetTop`, `pageTop`, and `scale`.
   - `window`: `innerHeight`, `outerHeight`, and `scrollY`.
   - `document`: `clientHeight` and `scrollHeight`.
   - Bounding client rects of the viewport shell, textarea, and footer.
3. **Inspect Element Ownership:** Use `document.elementFromPoint` inside the band together with computed backgrounds and pseudo-element styles to distinguish an app element from an exposed document background or non-interactive overlay.
4. **Distinction:** A passing simulated viewport test does not resolve a device-only physical report.

### Demand-Driven Projection Verification

Run recent document projection tests from `examples/vanilla`:

```bash
cd apps/loomark/examples/vanilla
npm run test:demand
```

This verifies that `DocumentLead` extraction occurs lazily and that collapsed sidebar DOM elements are cleanly disposed without lingering subscriptions or memory leaks.
