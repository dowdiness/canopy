# Plan 002: Retire the unreachable legacy WebRTC signaling stack

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before proceeding. Do
> not harden or replace the legacy Worker in place: current reachability shows
> it has no browser consumer. Stop if that assumption has changed. Record the
> result in [issue #1125](https://github.com/dowdiness/canopy/issues/1125).
>
> **Drift check (run first)**:
> `git diff --stat f6e3a0a5..HEAD -- examples/web/.env.example examples/web/signaling-server.js examples/web/signaling-worker.js examples/web/wrangler-signaling.toml examples/web/CLOUDFLARE_DEPLOYMENT.md examples/web/QUICKSTART_CLOUDFLARE.md examples/web/package.json examples/web/package-lock.json examples/web/src/vite-env.d.ts examples/web/MODULE_MAP.md examples/web/scripts/check-boundaries.mjs docs/plans/2026-07-25-waku-unified-web-migration.md docs/research/2026-07-25-waku-demo-behavior-contracts.md .github`
> If any listed file differs from the excerpts below, compare the live content
> before proceeding and stop on a semantic mismatch rather than overwriting it.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `001-reject-client-authored-server-frames.md`
- **Category**: security / tech-debt
- **Audit finding**: 2
- **Planned at**: commit `f6e3a0a5`, 2026-07-25
- **Reviewed**: 2026-07-25; revised after independent review

## Why this matters

`examples/web` contains a deployable Cloudflare Durable Object signaling server
with no authentication, one global room, client-selected identities, and
production deployment instructions. Repository-wide reachability finds no
browser code consuming `VITE_SIGNALING_URL`; references are confined to the
legacy implementation, docs, environment example, type declaration, inventory,
and a not-yet-executed Waku migration requirement. Canopy now has a separate
`examples/relay-server` integration around the MoonBit relay. Deleting the
unreachable legacy WebRTC stack removes the unsafe publication path without
inventing a second collaboration architecture, but the same change must also
remove the obsolete signaling service-binding work from the Waku migration plan
so that plan remains executable and internally consistent.

## Current state

- `examples/web/signaling-worker.js:52-85` trusts `data.agentId`, overwrites the
  map entry for duplicate IDs, broadcasts peer membership, and forwards offers,
  answers, and ICE candidates to arbitrary `data.to` values.
- `examples/web/signaling-worker.js:163` routes every request to:

  ```js
  const id = env.SIGNALING_ROOM.idFromName('global-room');
  ```

- `examples/web/wrangler-signaling.toml` makes the code directly deployable as
  `crdt-signaling-server` with a `SignalingRoom` Durable Object.
- `examples/web/CLOUDFLARE_DEPLOYMENT.md` and
  `examples/web/QUICKSTART_CLOUDFLARE.md` repeatedly instruct contributors to
  run `wrangler deploy --config wrangler-signaling.toml` and call the result a
  production path.
- `examples/web/signaling-server.js` is the matching local Node signaling
  server. It is reached only by the `"signaling"` package script.
- `examples/web/package.json` has a direct `ws` dependency and direct
  `@types/ws` development dependency used only by that local file.
- `examples/web/src/vite-env.d.ts` declares `VITE_SIGNALING_URL`, but no browser
  source reads it.
- Hidden file `examples/web/.env.example` contains only commented examples for
  `VITE_SIGNALING_URL` and the legacy Worker URL.
- `examples/web/MODULE_MAP.md` correctly describes these as shells outside all
  eight browser entry graphs.
- `examples/relay-server/src/index.ts` is the current collaboration server shell
  and delegates sync routing to the MoonBit `relay` package. It is not a WebRTC
  offer/answer signaling replacement and must not be edited in this plan.
- `docs/plans/2026-07-25-waku-unified-web-migration.md` currently depends on the
  legacy stack throughout its scope, target source shape, capability table,
  Stages 10–11, deployment/rollback contract, work package #979, acceptance
  criteria, validation, and risks. It requires a `SIGNALING` service binding,
  same-origin proxy, independently deployed Worker, and handshake. Deleting the
  Worker without removing all of that scope would make the Waku plan
  internally inconsistent.
- `docs/research/2026-07-25-waku-demo-behavior-contracts.md:82-99` correctly
  observes that no browser graph or test uses signaling, but says the legacy
  files remain as separate shells and frames a handshake as a gap. After
  retirement it must instead record that collaboration transport is absent from
  the current browser behavior contract and outside the Waku migration.

### Reachability decision

The retirement decision is valid only while all these are true:

1. No active browser entry imports or opens the legacy signaling endpoint.
2. `VITE_SIGNALING_URL` has no runtime read.
3. `signaling-server.js` is invoked only by its package script.
4. No CI or deployment workflow invokes `wrangler-signaling.toml`.
5. The Waku service-binding/handshake work is prospective plan scope, not
   implemented runtime behavior.
6. The current collaboration deployment is `examples/relay-server`, not
   `examples/web/signaling-worker.js`.

If any condition is false, stop. Do not improvise an authentication design or
point Waku at `examples/relay-server`: the modern binary CRDT relay is not a
protocol-compatible replacement for the old WebRTC offer/answer signaling
service. A live consumer requires a separate threat model and migration plan.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Reachability | `rg --hidden -n "signaling-worker|wrangler-signaling|VITE_SIGNALING_URL|SIGNALING_ROOM|WebSocketServer|SIGNALING service binding" examples/web docs .github README.md --glob '!**/node_modules/**' --glob '!docs/archive/**' --glob '!docs/plans/advisory/**' --glob '!.git/**'` | before: only listed legacy files/docs plus prospective Waku scope; after: no active legacy signaling references |
| Install | `cd examples/web && npm ci` | exits 0 |
| Generated artifacts | `NEW_MOON_MOD=0 ./scripts/build-js.sh` | exits 0 and produces the five web MoonBit modules |
| Typecheck | `cd examples/web && npm run typecheck` | exits 0, no TypeScript errors |
| Boundary tests | `cd examples/web && npm run test:boundaries` | 18 tests pass |
| Boundary check | `cd examples/web && npm run check:boundaries` | prints `Web dependency boundaries: OK` |
| Lock integrity | `cd examples/web && npm install --package-lock-only --ignore-scripts` | exits 0; lock root no longer declares direct `ws` or `@types/ws` |

## Suggested executor toolkit

- Use the `cloudflare`, `durable-objects`, and `wrangler` skills if available,
  but this task removes a stale Worker; it must not deploy, delete remotely, or
  call Cloudflare APIs.
- Use current Cloudflare docs only if live reachability forces a STOP and a
  separate hardening plan is requested.

## Scope

**Delete**:

- `examples/web/signaling-server.js`
- `examples/web/signaling-worker.js`
- `examples/web/wrangler-signaling.toml`
- `examples/web/CLOUDFLARE_DEPLOYMENT.md`
- `examples/web/QUICKSTART_CLOUDFLARE.md`
- `examples/web/.env.example` (it contains only legacy signaling examples at
  plan time; if unrelated variables have been added, keep the file and remove
  only the signaling block)

**Modify**:

- `examples/web/package.json`
- `examples/web/package-lock.json`
- `examples/web/src/vite-env.d.ts`
- `examples/web/MODULE_MAP.md`
- `examples/web/scripts/check-boundaries.mjs`
- `docs/plans/2026-07-25-waku-unified-web-migration.md` (required: remove the
  obsolete signaling service-binding scope throughout the plan)
- `docs/research/2026-07-25-waku-demo-behavior-contracts.md` (correct the Lambda
  behavior inventory after retiring the unreachable shells)
- `README.md` status row only

**Read-only references**:

- `examples/relay-server/**`
- `README.md`
- `examples/web/scripts/check-boundaries.test.mjs`
- `.github/workflows/**` (search for reachability; do not edit)

**Out of scope**:

- Do not deploy or remotely delete a Cloudflare Worker. Remote resource cleanup
  requires explicit operator authorization and account context.
- Do not modify, rename, secure, or add Waku integration for
  `examples/relay-server`. It uses a different binary CRDT relay protocol and is
  not a drop-in signaling replacement.
- Do not add auth, origin checks, room tokens, rate limiting, WebRTC, a new
  signaling service, `SIGNALING` service binding, or Waku WebSocket proxy.
- Do not remove the unrelated `examples/web/wrangler.jsonc` Waku configuration.
- Do not change browser application behavior or collaboration wire protocol.
- Preserve all pre-existing Waku prototype edits; use an isolated worktree or
  coordinate with their owner before touching currently modified files.

## Git workflow

- Branch: `advisor/002-retire-legacy-signaling`
- Suggested commit: `chore(web): retire legacy signaling stack`
- Do not push, open a PR, deploy, or delete remote resources without explicit
  operator instruction.

## Steps

### Step 1: Re-run reachability and prove the retirement assumption

Run from the repository root:

```bash
rg --hidden -n \
  "signaling-worker|wrangler-signaling|SIGNALING_ROOM|VITE_SIGNALING_URL|WebSocketServer|crdt-signaling-server|SIGNALING service binding" \
  examples/web docs .github README.md \
  --glob '!**/node_modules/**' --glob '!docs/archive/**' --glob '!docs/plans/advisory/**' \
  --glob '!.git/**'

rg --hidden -n "from ['\"]ws['\"]|require\(['\"]ws['\"]\)|WebSocketServer" \
  examples/web --glob '!**/node_modules/**' --glob '!package-lock.json' \
  --glob '!.git/**'
```

Expected:

- references are confined to the files listed in Current state, package/lock
  metadata, hidden `.env.example`, boundary classification, and the prospective
  Waku migration scope;
- no `.github` workflow invokes `wrangler-signaling.toml` or requires the
  legacy Worker;
- no `src/entries`, `src/features`, `src/shared`, HTML, or Vite/Waku page reads
  `VITE_SIGNALING_URL` or opens the endpoint;
- `ws` is imported only by `signaling-server.js`.

If another consumer appears, stop and report its path and call graph.

### Step 2: Delete the legacy implementation and deployment instructions

Delete the six legacy-only files in the Delete scope, including hidden
`examples/web/.env.example`. If `.env.example` has gained unrelated variables,
remove only its signaling section and retain the file. Do not replace deleted
files with redirects or new deployment instructions. The separate collaboration
shell remains visible at `examples/relay-server` through the root README, but it
is not wired into Waku by this plan.

**Verify**:

```bash
test ! -e examples/web/signaling-server.js
test ! -e examples/web/signaling-worker.js
test ! -e examples/web/wrangler-signaling.toml
test ! -e examples/web/CLOUDFLARE_DEPLOYMENT.md
test ! -e examples/web/QUICKSTART_CLOUDFLARE.md
# At plan time .env.example is signaling-only and should be deleted.
test ! -e examples/web/.env.example || ! rg -n 'VITE_SIGNALING_URL|crdt-signaling-server' examples/web/.env.example
```

Expected: all commands exit 0.

### Step 3: Remove dead package and environment surface

In `examples/web/package.json`:

- remove the `"signaling": "node signaling-server.js"` script;
- remove the direct `"ws"` dependency;
- remove the direct `"@types/ws"` development dependency;
- retain all other scripts and dependencies exactly.

In `examples/web/src/vite-env.d.ts`, remove only the
`VITE_SIGNALING_URL?: string` declaration.

Regenerate lock metadata without running package lifecycle scripts:

```bash
cd examples/web
npm install --package-lock-only --ignore-scripts
cd ../..
```

Inspect `examples/web/package-lock.json`. The root package entry must no longer
list `ws` or `@types/ws` directly. Transitive packages with either name may
remain if another dependency legitimately requires them; do not hand-delete
transitive entries.

**Verify**:

```bash
node - <<'NODE'
const p = require('./examples/web/package.json');
if (p.scripts.signaling !== undefined) process.exit(1);
if (p.dependencies.ws !== undefined || p.devDependencies?.ws !== undefined) process.exit(1);
if (p.devDependencies?.['@types/ws'] !== undefined) process.exit(1);
const lock = require('./examples/web/package-lock.json');
const root = lock.packages?.[''] ?? {};
if (root.dependencies?.ws !== undefined || root.devDependencies?.ws !== undefined) process.exit(1);
if (root.devDependencies?.['@types/ws'] !== undefined) process.exit(1);
NODE
! rg -n 'VITE_SIGNALING_URL' examples/web/src/vite-env.d.ts
```

Expected: both commands exit 0.

### Step 4: Remove stale inventory and boundary classifications

- In `examples/web/MODULE_MAP.md`, remove legacy signaling files from the
  deployment/integration-shell inventory. Keep `wrangler.jsonc` and unrelated
  Waku text intact.
- In `examples/web/scripts/check-boundaries.mjs`, remove
  `signaling-server.js` and `signaling-worker.js` from `ROOT_SERVER_FILES`.
  Do not change classification rules.
- In `docs/research/2026-07-25-waku-demo-behavior-contracts.md`, update only the
  Lambda `Development/production split` and `Known gaps` paragraphs. Record
  that the visible collaboration controls have no event binding, no transport
  implementation is part of the current browser behavior contract, the
  unreachable legacy shells are retired, and collaboration transport remains
  outside the Waku migration. Remove the stale links/claims that signaling
  files remain or that a Waku signaling handshake is an acceptance gap.

**Verify**:

```bash
! rg --hidden -n \
  "signaling-worker|wrangler-signaling|SIGNALING_ROOM|VITE_SIGNALING_URL|crdt-signaling-server" \
  examples/web --glob '!**/node_modules/**' --glob '!.git/**'
! rg -n 'Signaling files remain separate|signaling handshake' \
  docs/research/2026-07-25-waku-demo-behavior-contracts.md
rg -n 'collaboration transport.*outside|outside.*collaboration transport' \
  docs/research/2026-07-25-waku-demo-behavior-contracts.md
```

Expected: no legacy signaling implementation, configuration, environment, or
inventory reference remains under `examples/web`; the behavior contract records
the deliberate non-capability rather than a missing Waku handshake.

### Step 5: Remove the obsolete signaling seam from the Waku migration plan

Edit `docs/plans/2026-07-25-waku-unified-web-migration.md` as one coherent
scope correction. Do not merely replace the old Worker name with
`examples/relay-server`; the protocols differ and there is no active browser
consumer to preserve.

Make all of these changes:

1. **Scope and current state:** remove the promise to keep Waku and the
   Signaling Worker independently deployable through a service binding. Replace
   the signaling-redesign exclusion with a stable boundary: collaboration relay
   protocol/deployment remains outside the Waku web migration. Remove the old
   Worker/TOML current-state bullet.
2. **Target source shape:** remove `server/waku/signaling-proxy.ts`. Remove the
   empty `server/waku/` directory from the diagram if it has no other planned
   owner.
3. **Capability allocation:** remove both signaling rows—the separate
   `SignalingRoom` owner and same-origin ingress—and remove the paragraph about
   generated `SIGNALING` binding types. Add no replacement capability.
4. **Stages 10–11:** rename Stage 10 to `Cloudflare staging`; remove service
   binding, WebSocket forwarding, Worker dependency, and handshake steps/gates.
   Keep route, assets, RSC, 404, error, observability, startup, staging, cutover,
   and rollback validation. Remove signaling from Stage 11 smoke criteria.
5. **CI/deployment/rollback decision:** remove credentialed service-binding and
   handshake requirements, preview/production service-binding language, the
   prerequisite Signaling Worker, failed-proxy rollback trigger, and independent
   Signaling Worker rollback instructions. Keep protected staging and Waku
   Worker rollback requirements.
6. **Work package #979:** change the local link text/scope to deploy Waku, cut
   over, and retire Vite without signaling verification. Do not edit the GitHub
   issue remotely; publication changes require separate explicit approval.
7. **Acceptance and validation:** remove the Signaling Worker/service-binding
   acceptance item and WebSocket handshake from the workerd/staging harness.
8. **API/reuse and risks:** remove service bindings from the reused platform
   interface list unless another live binding exists, and delete the
   `Signaling coupling` risk. Keep unrelated deployment-race and Worker risks.
9. **Final consistency:** search the entire Waku plan case-insensitively for
   `signal`, `websocket`, `service binding`, and `SIGNALING`. Every remaining
   match must refer to a separate, live non-signaling capability; otherwise
   remove it.

The corrected Waku plan must explicitly state once that collaboration relay
protocol and deployment are not part of this migration, so future executors do
not reintroduce the removed seam.

**Verify**:

```bash
rg -n 'collaboration relay.*outside|outside.*collaboration relay' \
  docs/plans/2026-07-25-waku-unified-web-migration.md
! rg -ni 'signaling|SIGNALING|websocket handshake|service-bound WebSocket|signaling-proxy' \
  docs/plans/2026-07-25-waku-unified-web-migration.md
! rg -n 'SIGNALING' examples/web/wrangler.jsonc examples/web/worker-configuration.d.ts 2>/dev/null
rg -n 'Stage 10 — Cloudflare staging|protected.*staging|rollback' \
  docs/plans/2026-07-25-waku-unified-web-migration.md
```

Expected: the Waku plan contains one explicit out-of-scope collaboration-relay
boundary, no signaling implementation/binding/handshake requirement, and retains
its non-signaling staging and rollback gates.

### Step 6: Re-run repository-wide reachability and web validation

Run the repository-wide hidden-file search first:

```bash
! rg --hidden -n \
  "signaling-worker|wrangler-signaling|SIGNALING_ROOM|VITE_SIGNALING_URL|crdt-signaling-server|SIGNALING service binding" \
  examples/web docs .github README.md \
  --glob '!**/node_modules/**' --glob '!docs/archive/**' --glob '!docs/plans/advisory/**' \
  --glob '!.git/**'
```

Expected: no active legacy signaling reference remains in web code/docs or CI.
The generic word `signaling` may still appear in historical files excluded by
this command and must not be mass-edited.

Then build the generated modules and run web validation:

```bash
NEW_MOON_MOD=0 ./scripts/build-js.sh
cd examples/web
npm ci
npm run typecheck
npm run test:boundaries
npm run check:boundaries
cd ../..

git diff --check
git status --short
```

Expected:

- install and typecheck exit 0;
- all 18 boundary tests pass;
- boundary check prints `Web dependency boundaries: OK`;
- only files in Scope plus the plan status row changed for this task.

Do not run `wrangler deploy`, `wrangler delete`, or any command requiring
Cloudflare credentials.

## Test plan

No new runtime test is required because the retired implementation has no
runtime importer. Existing boundary tests and static reachability checks prove
that deletion does not break an entry graph. Validation consists of:

- a repository-wide `rg --hidden` scan across `examples/web`, `docs`, `.github`,
  and `README.md`;
- zero active references to deleted paths/config/binding/environment variable;
- the Waku behavior inventory records collaboration transport as absent and
  outside migration scope, not as an expected handshake;
- zero Waku migration requirements for a signaling proxy, service binding, or
  handshake;
- package and lockfile agreement after removing the direct `ws` and
  `@types/ws` dependencies;
- TypeScript typecheck;
- 18/18 boundary tests and the production boundary scan.

If active behavior is found, this deletion plan is invalid; stop instead of
adding tests around the legacy service.

## Done criteria

- [ ] All six legacy-only implementation/deployment/environment files are
  deleted, or `.env.example` is retained only if unrelated settings remain.
- [ ] `examples/web` has no `signaling` script, direct `ws`/`@types/ws`
  dependency, `VITE_SIGNALING_URL` declaration/example, or legacy Worker URL.
- [ ] No active docs or `.github` workflow references `wrangler-signaling.toml`.
- [ ] The Waku behavior contract no longer says signaling shells remain or
  treats a handshake as an inherited behavior gate.
- [ ] The Waku migration plan excludes collaboration relay deployment and has
  no `SIGNALING` binding, proxy, handshake, deployment, rollback, acceptance,
  validation, work-package, or risk requirement.
- [ ] Boundary inventory no longer classifies nonexistent files.
- [ ] `npm run typecheck`, `npm run test:boundaries`, and
  `npm run check:boundaries` pass.
- [ ] `examples/relay-server` and `examples/web/wrangler.jsonc` are unchanged.
- [ ] No Cloudflare deployment or remote deletion was performed.
- [ ] No out-of-scope file changed except the plan index status.

## STOP conditions

Stop and report if:

- any active browser or server entry consumes the legacy signaling protocol;
- `VITE_SIGNALING_URL` has a live runtime read;
- another source file imports `ws` directly;
- a `.github` or external deployment workflow invokes
  `wrangler-signaling.toml` or depends on the Worker;
- any `SIGNALING` service binding, Waku signaling proxy, or handshake described
  in the migration plan has already been implemented;
- removing signaling from the Waku plan would invalidate a separately accepted
  product requirement rather than only prospective scope;
- the operator wants to preserve WebRTC signaling—in that case a separate
  threat model and hardening/migration plan is required;
- lock regeneration changes unrelated dependency versions or package metadata;
- current Waku edits cannot be cleanly separated from this deletion;
- completing the task appears to require changing `examples/relay-server`.

## Maintenance notes

This plan removes repository deployment instructions and prospective Waku
coupling; it does not remove an already deployed Cloudflare resource. If such a
Worker exists, its owner should separately confirm traffic and explicitly
authorize remote deletion. The linked GitHub issue #979 may retain obsolete
signaling wording; changing that public issue requires separate explicit
approval and is not authorized by this plan. Future collaboration work must use
one named server architecture and document room, identity, authentication,
origin, abuse-control, and Waku integration policies before publication.