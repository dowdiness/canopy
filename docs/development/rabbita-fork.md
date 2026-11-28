# Canopy Rabbita fork

Canopy uses a downstream fork of Rabbita for typed pointer-event, pointer-capture, coordinate hit-testing, and keyed accessible SVG boundaries.
The fork is an owned dependency line, not an upstream release dependency.

## Development Guidance

Before designing Rabbita changes (`@sub`, `@cmd`, `@html`, `@dom`, `@http`,
or bindings), read the repository's `.claude/skills/rabbita` skill. The vendored
docs in `deps/rabbita/doc/` and `deps/rabbita/rabbita/*/README.mbt.md` and
`design.md` are authoritative when they disagree with plans or pasted specs.

The RC1 compiler migration is published on `chore/moonbit-rc1` and reviewed
against `canopy/rebase-20261119`. Do not push either the established downstream
branch or `main` directly, force-push, or move existing tags. Canopy pin updates
follow the normal Canopy PR and CI workflow.

## Ownership

- **Fork:** [`dowdiness/rabbita`](https://github.com/dowdiness/rabbita)
- **Upstream:** [`moonbit-community/rabbita`](https://github.com/moonbit-community/rabbita)
- **Downstream branch:** `chore/moonbit-rc1`, based on `canopy/rebase-20261119`. Rebase branches and `main` remain unchanged so earlier pins stay reachable.
- **Upstream base:** `316bab8d9012540b7af44690da72bdb98c98a256` (upstream `main`, 2026-11-18)
- **Pinned commit:** `020485b00fee93711b5aa6d8d777616a29f2b491`
- **Pin tag:** `canopy-moonbit-rc1-020485b00fee`; `canopy-worker-20261004` identifies the earlier Worker binding pin.
- **History:** the 25 rebased fork commits, one MoonBit 0.10.21 formatting commit, then the RC1 compatibility commit; no merge commits. The earlier stack has 15 commits that do not type-check individually, so that stack is for reading, not for `git bisect`.
- **Canopy submodule:** `deps/rabbita`

The Canopy `.gitmodules` entry intentionally points at the fork. The
superproject pins the exact downstream commit; it must not depend on a moving
branch reference at checkout time.

## Downstream changes

The pinned fork contains:

- a composable RUI Sonner host with stable notification slots that preserve native
  editor Undo, and isolated timer, hover, and swipe lifecycles;
- typed `DOMExceptionError` effects for `set_pointer_capture` and
  `release_pointer_capture`;
- preservation of standard DOM exception `name` and `message`, with safe
  normalization of non-standard JavaScript throws;
- `Attrs::on_lostpointercapture` with a `PointerEvent` callback;
- `Attrs::on_pointerdown`, `on_pointermove`, `on_pointerup`, and
  `on_pointercancel` with `PointerEvent` callbacks;
- migration of Rabbita/RUI pointer-capture consumers to the new effect;
- typed text-area selection, file-selection, and `InputEvent` data bindings;
- `svg.Attrs::role` and `svg.Attrs::aria_label` for typed edge-path
  accessibility attributes;
- `svg.keyed_node`, which exposes keyed SVG children to Rabbita's keyed VDOM
  reconciliation so edge-path DOM identity survives reorder; and
- managed IndexedDB String Store interface (`get`, `contains`, `entries`, `set`,
  `delete`, atomic `apply`) with typed errors, blocked/stale lifecycle
  recovery, and redacted debug values; and
- a [dedicated module Worker binding](../../deps/rabbita/rabbita/worker/README.mbt.md)
  with Sub-owned lifetime, opaque incarnation-bound connections, correlated
  request commands, explicit failures, inactivity deadlines and cleanup.

Canopy needs a MoonBit-typed pointer-capture boundary for its Canvas hosts. This
patch is intentionally maintained downstream rather than proposed as an
upstream Rabbita change.

## 0.16.3 integration

The 0.16.3 integration placed the fork-specific commits on top of upstream
`main`, rather than merging upstream into the old downstream branch. It includes Rabbita
0.16.3, RUI 0.3.5, and Warren 0.4.5 with its embedded evol minifier.
Canopy's Rabbita dependency declarations match 0.16.3.

- Loomark imports `moonbit-community/rui` instead of `Yoorkin/rui`. Its delete
  confirmation uses the native alert dialog, `@dialog.show`, and the dialog
  form's close value. Only `confirm` deletes; Cancel and Escape preserve the
  document.
- CodeMirror loading uses `Promise[Value]` and `Promise::from_async`, retaining
  the existing module cache and error callbacks.
- The managed IndexedDB command bridge uses a private callback-to-promise
  adapter and `Promise[Cmd].wait()`. Transaction scheduling, completion
  acknowledgements, and redacted errors remain owned by the existing provider.
- The fork retains nullable `InputEvent.get_data()`; upstream's non-null
  `InputEvent.data()` is not substituted.

The 0.16.3 integration itself did not add Worker bindings. The subsequent
`8fcdacd` pin adds the JS-only Worker package; it does not migrate Loomark's
controller/dispatcher or change its persistence and recovery policy. Native/Wasm
SSR cannot import this package. See the
[implementation and validation record](../archive/2026-10-04-rabbita-worker-binding.md).

## Upgrade procedure

1. Fetch the upstream and downstream repositories. Keep a working clone outside `/tmp` and enable `git config rerere.enabled true`; its cache is local to the clone.
2. Create `canopy/rebase-<date>` from the current downstream branch and rebase it onto upstream `main`, keeping the history linear. Resolve generated `.mbti` files by taking the upstream side and running `moon info`, never by hand. Check that no commit contains conflict markers (`git grep '^<<<<<<< ' <commit>` for every commit).
3. Adapt the fork to upstream API changes that merged without a textual conflict (`git range-diff` against the previous stack shows which commits changed), then run `moon check`.
4. Run the full Rabbita test suite.
5. Run the full Canopy test suite, `scripts/check-strict.sh` on the default and `--target js` targets after `moon clean`, and the affected Ideal E2E tests. Canopy needs adapting to upstream breaking changes (`!` commits).
6. Build the JavaScript artifacts.
7. Push the verified branch (and a new pin tag, without moving existing tags) to `dowdiness/rabbita` only. Never push to, open a pull request against, or comment on `moonbit-community/rabbita`: disable the upstream remote's push URL in the working clone (`git remote set-url --push upstream DISABLED`), and give API calls an explicit `dowdiness/rabbita` repository.
8. Update the `deps/rabbita` submodule and
   `scripts/install-local-warren.sh` to the same published downstream commit.
9. Record the new commit and tag here, then verify the superproject is clean.

A downstream commit must be pushed to `dowdiness/rabbita` before its gitlink is
updated in Canopy so fresh recursive checkouts can resolve it.
