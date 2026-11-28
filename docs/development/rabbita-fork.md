# Canopy Rabbita fork

Canopy uses a downstream fork of Rabbita for typed pointer-event, pointer-capture, coordinate hit-testing, and keyed accessible SVG boundaries.
The fork is an owned dependency line, not an upstream release dependency.

## Development Guidance

Before designing Rabbita changes (`@sub`, `@cmd`, `@html`, `@dom`, `@http`,
or bindings), read the repository's `.claude/skills/rabbita` skill. The vendored
docs in `deps/rabbita/doc/` and `deps/rabbita/rabbita/*/README.mbt.md` and
`design.md` are authoritative when they disagree with plans or pasted specs.

The RC1 upstream integration is published on `canopy/upstream-0.17.2-rc1` and
reviewed against `canopy/rebase-20261128`. Do not push the established downstream
branch or `main` directly, force-push, or move existing tags. Canopy pin updates
follow the normal Canopy PR and CI workflow.

## Ownership

- **Fork:** [`dowdiness/rabbita`](https://github.com/dowdiness/rabbita)
- **Upstream:** [`moonbit-community/rabbita`](https://github.com/moonbit-community/rabbita)
- **Downstream branch:** `canopy/upstream-0.17.2-rc1`, reviewed against the new `canopy/rebase-20261128` line seeded at upstream. The earlier RC1 branch, dated rebase branches and `main` remain unchanged so older pins stay reachable.
- **Upstream base:** `99d91eaf648eddaaa1ede5f94d90159cc77cd1d5` (upstream `main`, 2026-11-27)
- **Pinned commit:** `b2718a0d26188cc2eaadb9f06308219b62833f6a`
- **Pin tag:** `canopy-moonbit-rc1-b2718a0d2618`; `canopy-worker-20261004` identifies the earlier Worker binding pin.
- **History:** 27 previous downstream/compatibility commits replayed on the new upstream base, followed by the popup-focus and toast-test correction; no merge commits. Historical commits are not individually validated; the integration tip is the validation unit.
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

## 0.17.2 integration

The current pin integrates Rabbita 0.17.2, RUI 0.5.3 and Warren 0.4.6.
Canopy's dependency declarations and the Warren installer use this integration.
It retains the downstream changes above and adds upstream's synchronous
`Html::render_to_string`, Select keyboard fixes and inherited host-font default.
Set `--rui-font-sans` explicitly when an application requires a different font.

The fork also makes opening popups immediately focusable without animating
`visibility`; opacity/transform entry and the existing closing transitions remain.
The unmodified modal-Select regression failed on pristine upstream with the same
browser before this downstream correction. The retained-slot toast containment
test now selects visible notifications by accessible role rather than hidden
reserved slots. The standalone documentation module is checked and tested too;
it is no longer excluded from the RC1 migration.

See [Rabbita PR #10](https://github.com/dowdiness/rabbita/pull/10).

## 0.16.3 integration

The 0.16.3 integration placed the fork-specific commits on top of upstream
`main`, rather than merging upstream into the old downstream branch. It includes Rabbita
0.16.3, RUI 0.3.5, and Warren 0.4.5 with its embedded evol minifier.
Canopy's dependency declarations matched 0.16.3 at that integration.

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
