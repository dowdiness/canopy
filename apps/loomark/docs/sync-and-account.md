# Sync, Authentication, and Replica Storage

Loomark pairs local-first IndexedDB persistence with an optional cloud sync service powered by Cloudflare Workers, D1, and Google OAuth (via Better Auth).

This guide details how Loomark coordinates authentication, background replication, causal consistency, and divergence recovery without disrupting the active editor.

---

## 1. System Boundary and Responsibilities

Loomark splits authentication and storage across TypeScript and MoonBit:

- **Authentication & Worker Dispatch (TypeScript):** Better Auth handles Google OAuth handshakes and session cookies. Configuration and routing stay in TypeScript.
- **Server Domain Logic (MoonBit):** `server/documents/` handles HTTP request validation and wire serialization. `server/internal/document_store/` manages typed queries, revision checks, tombstones, and durable retry receipts. Neither package touches dynamic JavaScript objects directly.
- **Platform Bindings:** Typed HTTP, D1 database, and Web Crypto interfaces live in [`worker-platform`](../../../modules/worker-platform/README.md), built on the project's shared `js_ffi` bridge.
- **Data Isolation:** Client documents and authentication sessions share a single D1 database, strictly scoped by authenticated user ID.

The server compiles independently from the browser client.

---

## 2. Google Sign-In and Page Departure Lifecycle

The **Login with Google** button in More actions uses a white pill-shaped
surface, a fine border, and a locally served Google mark. Retry sign-in keeps
the same treatment; Cancel sign-in and sign-out remain neutral account controls.
Normally the menu shows account and document operations, not saving or sync
progress. Signed-out users see the login button; signed-in users see their name
and Sign out on both desktop and mobile. A local document keeps its explicit
Sync action when eligible. There is no Account heading or signed-out label.

The footer remains the home for routine local saving feedback. The menu shows
only saving failures, sync failures, conflicts, pending remote deletion, and
available recovery or update actions. A sync failure says **Saved on this device.
Sync failed.** only when the current text is locally stored; otherwise it says
**Sync failed.** Replica persistence failures retain **Retry saving** even after
logout or when account lookup is unavailable. Account lookup failures retain
**Check account connection** without presenting the user as signed out.

Sign-in preparation shows **Signing in…** with **Cancel sign-in** until
navigation begins. During account lookup the account control is disabled;
logout failures retain the account name and **Retry sign-out**.

When a user clicks **Login with Google**, Loomark guarantees that local work is safely committed before navigating away:

1. **Local Pre-Flight:** The root model asks the document store to flush pending edits to IndexedDB across both Source and Replica lanes. If saving fails, navigation aborts, the editor stays interactive, and a retry button appears. If the user continues typing while departure is pending, the new edits immediately cancel departure to avoid losing keystrokes.
2. **Cancellation:** Until browser navigation physically starts, clicking **Cancel sign-in** abandons the OAuth flow and returns focus to the editor (or preview tab). Any background save already in flight continues quietly.
3. **Dispatch:** Once the browser initiates the redirect to Google, subsequent edits or delayed account checks cannot cancel navigation.
4. **BFCache & Restoration:** If the user returns from Google via the browser's Back/Forward cache (`pageshow.persisted`), Loomark releases the departure lock and refreshes the user session without reloading or resetting the active editor.

`internal/sync.Session` is the single source of truth for user sessions, checked via `/api/account`. Logging out transitions through `Revoking` (or `LogoutUnconfirmed` on network uncertainty). A confirmed logout hides remote account documents immediately but preserves all local documents and keeps the active editor open.

---

## 3. Replica Persistence and State Machine

In addition to standard local `source/v1` records, the client repository manages account-scoped `replica/` records in IndexedDB:

- **Record Layout:** Replicas use a length-prefixed string format containing a compact JSON header (revision, IDs, state flags) followed by raw, unescaped text. This avoids the CPU and memory cost of JSON-encoding large documents on every autosave.
- **Causal State Machine:** Replicas follow an explicit lifecycle:
  $$\text{Live} \ (\text{Ready} \mid \text{Sending} \mid \text{Available} \mid \text{Diverged}) \longrightarrow \text{Deleting} \longrightarrow \text{Tombstone}$$
- **Atomic Promotion:** Starting sync converts a local-only `source/v1` document into a `replica/` record in a single IndexedDB transaction.
- **Save Admission:** Typing never triggers immediate serialization. Edits accumulate until Loomark's autosave heuristics (250 ms quiet time, a non-restarting 2,000 ms maximum-wait timer when it can be processed, or tab hide) declare the window eligible. At most one IndexedDB replica write runs at any time; newer edits coalesce behind it.

Returning text back to its acknowledged baseline cancels an obsolete failed save and restores the clean state without making unnecessary writes.

---

## 4. Conflict Handling and Divergence Recovery

When both the local device and the server receive independent edits, Loomark never silently overwrites either side. Instead, it branches:

1. **Divergence Detection:** If the server returns HTTP 409 (or returns a newer revision with different text), the replica enters `Diverged`.
2. **Atomic Fork:** The client generates a fresh UUID, forks the local edits into a new local-only recovery document, and advances the original identity to track the server's branch.
3. **Zero Interruption:** While the fork transaction runs in IndexedDB, the active editor enters a private `Forking` state. Selection, text composition, and native undo history stay fully mounted and uninterrupted. Subsequent edits flow into ordinary persistence once the fork commits.

### Synchronized Deletions

Deleting a synced document enters a durable `Deleting` state:
- The editor row is removed optimistically, but the active editor remains mounted until the deletion commits to local IndexedDB.
- The background sync engine delivers an HTTP `DELETE` to the server.
- Once acknowledged, the client replaces the record with a lightweight, text-free `Tombstone` to prevent stale peer devices from resurrecting the document.

---

## 5. Network Protocol and Invariants

- **Idempotent Operations:** Every mutation, delivery, and remote fetch carries an opaque typed attempt ID. Rabbita commands round-trip this ID unchanged, ensuring late or out-of-order HTTP responses cannot corrupt state.
- **Decoupled Catalog:** The remote catalog (document listing) is transient and stored in memory, not in IndexedDB. It stores a lightweight 80-character Markdown lead rather than full document bodies.
- **Lazy Remote Reads:** Clicking a remote-only document fetches its body on demand. The editor only activates the document after its initial replica successfully writes to IndexedDB.
- **Error Backoff:** Definitive client errors (HTTP 413 Payload Too Large, HTTP 422 Unprocessable Content) retire the rejected operation immediately and wait for user edits, preventing infinite retry loops. Transient network drops leave operations intact for automatic retry upon reconnection.

---

## 6. Testing the Sync Stack

From `apps/loomark`:

```bash
# Run server test suites with local D1 simulation
npm run test:server
npm run typecheck:server

# Run targeted MoonBit package tests
NEW_MOON_MOD=0 moon test --target js \
  -p dowdiness/loomark/server/documents \
  dowdiness/loomark/server/internal/document_store
```

Integration tests verify Worker lifecycle, request replay, conflict branching, and multi-account isolation against local D1 and Better Auth mock sessions without requiring live Google credentials.
