# Deploy All Examples to Cloudflare

## Why

Only `web` has CI deployment (to GitHub Pages). The other 7 examples (`rabbita`,
`ideal`, `prosemirror`, `demo-react`, `block-editor`, `canvas`, `relay-server`)
have no automated deployment. We want all examples deployed to Cloudflare with a
single unified workflow.

## Scope

In:
- `.github/workflows/deploy-cloudflare.yml` (new)
- `.github/workflows/deploy.yml` (delete)
- `examples/prosemirror/wrangler.jsonc` (new)
- `examples/demo-react/wrangler.jsonc` (new)
- `examples/block-editor/web/wrangler.jsonc` (new)
- `examples/canvas/web/wrangler.jsonc` (new)
- `examples/web/wrangler.jsonc` (rename project to `canopy-lambda-editor`)
- `examples/ideal/web/wrangler.jsonc` (rename project to `canopy-ideal`)
- `examples/rabbita/wrangler.jsonc` (rename project to `canopy-rabbita`)
- `examples/rabbita/scripts/build.sh` (replace bun with npm)
- `examples/rabbita/package.json` (remove `packageManager` field)
- `examples/rabbita/bun.lock` (delete)
- `examples/ideal/web/package.json` (fix `prebuild:moonbit` path)

Out:
- `.github/workflows/ci.yml` (unchanged)
- Signaling/relay Workers deployment config (existing `wrangler-signaling.toml`,
  `wrangler-relay.toml` — out of scope)

## Current State

- `deploy.yml` deploys `examples/web` to GitHub Pages on push to main
- `examples/web`, `rabbita`, `ideal` have `wrangler.jsonc` but no CI deploy
- `examples/relay-server` has `wrangler.toml` but no CI deploy
- `prosemirror`, `demo-react`, `block-editor`, `canvas` have no Cloudflare config
- `rabbita` uses bun locally; has both `bun.lock` and `package-lock.json`;
  `package.json` declares `packageManager: "bun@1.2.15"`
- `rabbita/wrangler.jsonc` uses old name `rabbita-projectional-editor`
- `ideal/web/package.json` `prebuild:moonbit` script has wrong path (`cd ../..`
  resolves to `examples/`, not `examples/ideal/`)
- `relay-server/src/index.ts` imports root MoonBit build output
  (`../../../_build/js/release/build/canopy.js`) — requires root `moon build`

## Desired State

- All 8 examples deploy to Cloudflare on push to main via a single matrix workflow
- 7 static examples use Cloudflare Pages (`wrangler pages deploy`)
- 1 Workers example uses `wrangler deploy`
- All examples use npm (no bun dependency)
- GitHub Pages deployment removed entirely

## Cloudflare Project Names

| Example | Type | Project Name |
|---------|------|-------------|
| `web` | Pages | `canopy-lambda-editor` |
| `rabbita` | Pages | `canopy-rabbita` |
| `ideal` | Pages | `canopy-ideal` |
| `prosemirror` | Pages | `canopy-prosemirror` |
| `demo-react` | Pages | `canopy-demo-react` |
| `block-editor` | Pages | `canopy-block-editor` |
| `canvas` | Pages | `canopy-canvas` |
| `relay-server` | Workers | `canopy-relay` |

## Build Commands Per Example

| Example | moon update dirs | moon build dir | npm/vite dir | Deploy dir |
|---------|-----------------|---------------|-------------|-----------|
| web | root, `graphviz/` | root, `graphviz/` | `examples/web/` | `examples/web/dist` |
| rabbita | root, `examples/rabbita/` | root | `examples/rabbita/` | `examples/rabbita/dist` |
| ideal | `examples/ideal/` | `examples/ideal/` | `examples/ideal/web/` | `examples/ideal/web/dist` |
| prosemirror | root | root | `examples/prosemirror/` | `examples/prosemirror/dist` |
| demo-react | root | root | `examples/demo-react/` | `examples/demo-react/dist` |
| block-editor | `examples/block-editor/` | `examples/block-editor/` | `examples/block-editor/web/` | `examples/block-editor/web/dist` |
| canvas | `examples/canvas/` | `examples/canvas/` | `examples/canvas/web/` | `examples/canvas/web/dist` |
| relay-server | root | root | `examples/relay-server/` | N/A (`wrangler deploy`) |

All MoonBit builds use `--target js --release`.

**Wrangler usage:** All examples use `npx wrangler` after `npm ci`, which
installs wrangler from each example's `devDependencies`. Examples that don't
yet list wrangler in `devDependencies` will have it added.

## Steps

1. Create `wrangler.jsonc` for prosemirror, demo-react, block-editor, canvas.
2. Update `examples/web/wrangler.jsonc` name to `canopy-lambda-editor`.
3. Update `examples/ideal/web/wrangler.jsonc` name to `canopy-ideal`.
4. Update `examples/rabbita/wrangler.jsonc` name to `canopy-rabbita`.
5. Remove `packageManager` field from `examples/rabbita/package.json`.
6. Update `examples/rabbita/scripts/build.sh` to use npm instead of bun.
7. Delete `examples/rabbita/bun.lock`.
8. Fix `examples/ideal/web/package.json` `prebuild:moonbit` script path
   (`cd ../..` → `cd ..` so it resolves to `examples/ideal/`, which has its
   own `moon.mod.json`).
9. Add `wrangler` to `devDependencies` for examples that need it for deploy.
10. Create `.github/workflows/deploy-cloudflare.yml` with matrix strategy.
11. Delete `.github/workflows/deploy.yml`.

## Acceptance Criteria

- [ ] All 8 examples have correct `wrangler.jsonc` or `wrangler.toml`
- [ ] Matrix workflow triggers on push to main and workflow_dispatch
- [ ] Each matrix job: checkout, install MoonBit, setup Node, `npm ci`, build, deploy
- [ ] Pages examples use `npx wrangler pages deploy <dir> --project-name <name>`
- [ ] Workers example uses `npx wrangler deploy`
- [ ] `deploy.yml` (GitHub Pages) removed
- [ ] `rabbita` uses npm everywhere (no bun.lock, no `packageManager` field)
- [ ] `ideal/web/package.json` `prebuild:moonbit` resolves to repo root
- [ ] `relay-server` job runs root `moon update` + `moon build` before deploy
- [ ] Workflow uses `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` secrets

## Validation

```bash
# Verify all wrangler configs exist
for d in examples/web examples/rabbita examples/ideal/web examples/prosemirror \
         examples/demo-react examples/block-editor/web examples/canvas/web; do
  test -f "$d/wrangler.jsonc" && echo "OK: $d/wrangler.jsonc" || echo "MISSING: $d/wrangler.jsonc"
done
test -f examples/relay-server/wrangler.toml && echo "OK: relay-server/wrangler.toml"

# Verify bun.lock removed
test ! -f examples/rabbita/bun.lock && echo "OK: bun.lock removed"

# Verify deploy.yml removed
test ! -f .github/workflows/deploy.yml && echo "OK: deploy.yml removed"

# Verify rabbita package.json has no packageManager field
! grep -q '"packageManager"' examples/rabbita/package.json && echo "OK: no packageManager"

# Verify ideal prebuild resolves to ideal module root
grep '"prebuild:moonbit": "cd \.\.' examples/ideal/web/package.json && echo "OK: ideal prebuild path"
```

## Known Limitations

- **Collaborative features won't work in production** for `ideal`, `demo-react`,
  and `prosemirror`. These examples hardcode `ws://localhost:8787` for WebSocket
  connections. Deploying them gives a working UI but without real-time
  collaboration. Fixing this requires adding `VITE_RELAY_URL` env var support to
  each app and configuring it in the workflow — tracked as a separate follow-up
  task.

## Risks

- **First deploy auto-creates Pages projects:** `wrangler pages deploy` with
  `--project-name` auto-creates the project if it doesn't exist. If the account
  doesn't have enough project slots (free tier: 100), some deploys may fail.
- **Secrets not set:** Workflow will fail if `CLOUDFLARE_API_TOKEN` or
  `CLOUDFLARE_ACCOUNT_ID` aren't configured as GitHub repo secrets.
- **rabbita npm ci:** Switching from bun to npm — verify `package-lock.json` is
  up to date and `npm ci` succeeds locally before merging.
- **relay-server Wrangler version:** `relay-server` pins wrangler `^3.72.0`.
  Other examples may install a newer version. Verify compatibility.

## Notes

- User must set `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` as GitHub
  repo secrets before the workflow will succeed.
- The signaling worker (`wrangler-signaling.toml`) and relay worker
  (`wrangler-relay.toml` in ideal) are separate deploy targets not covered here.
- The collaborative WebSocket endpoint migration is a follow-up task.
