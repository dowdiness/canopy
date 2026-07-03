# Audit — CodeMirror–Rabbita binding (Phase 1)

Audit target: the binding between CodeMirror 6 and the Rabbita TEA loop inside
`examples/ideal`. Reference pattern: the six structural properties listed in the
spec for `moonbit-community/rabbita_xterm`.

Phase 1 deliverable — investigation only, no edits to binding code. The
remediation (Phase 2) is gated on reviewer approval of this report and on
answers to the open design questions at the end.

## Conformance summary

| # | Property                                                | Verdict        |
|---|---------------------------------------------------------|----------------|
| 1 | Three layers, three packages (`<root>/js`, `listen`, managed) | **Diverges** |
| 2 | FFI form (`extern "js" fn … = #\|`, newtype handles)     | **Partially conforms** |
| 3 | Async loading via `@js.load()` + `@js.Promise`           | **Diverges**   |
| 4 | `struct Disposable(() -> Unit)` wrapper                  | **Diverges**   |
| 5 | `@sub.custom_sub` + `priv suberror` + `update_tagger`    | **Diverges**   |
| 6 | Lifecycle Sub: load + `after_render` mount + dispose     | **Partially conforms** |

**Headline finding.** There is no discrete *CodeMirror–Rabbita binding package*.
The MoonBit side of the binding is `examples/ideal/main/bridge_ffi.mbt`
(`extern "js"` declarations) plus several `@rabbita.effect`/
`@rabbita_cmd.raw_effect` calls scattered throughout `main/main.mbt`. The
JS side of the binding is `examples/ideal/web/src/canopy-editor.ts` (a Web
Component that owns the CM6 `EditorView`) plus `bridge.ts`, `main.ts`, and a
handful of supporting modules. The two sides communicate through (a) the
generated MoonBit JS module's exported FFI functions and (b) DOM custom events
+ `globalThis.__canopy_*` global slots + `aria-hidden` "hidden trigger" buttons
clicked by JS to wake Rabbita.

Because the binding is not a package, the spec's three-layer prescription has
no place to land in its current shape: every property below describes how
*structure that does not exist yet* would have to be introduced. Several
properties (sub wiring, `Disposable`) cannot be implemented at all against the
currently-pinned dependency — see "Dependency blocker" under "Human decisions
needed".

## FFI surface

All 26 `extern "js"` declarations live in
`examples/ideal/main/bridge_ffi.mbt:1–230`. That file is part of the managed
TEA package (`dowdiness/ideal-editor/main`), not a `js/` sub-package, so it
violates property 1 by construction.

The functions divide into four behavioural categories. Names below are quoted
verbatim from the file.

### A. "Take-and-clear" pickups from global slots

These read a value JS wrote into `globalThis.__canopy_*` before clicking a
hidden trigger button, then clear the slot.

| FFI | Source global | Used at |
|---|---|---|
| `js_get_agent_id` (`bridge_ffi.mbt:3`) | `globalThis.__canopy_agent_id` | `main.mbt:28` (`init_model`) |
| `js_take_selected_node_id` (`:63`) | `__canopy_pending_node_selection` | `main.mbt:884` (`EditorNodeSelected`) |
| `js_take_structural_edit_op` (`:73`) | `__canopy_pending_structural_edit.op` | `main.mbt:512, 902` |
| `js_take_structural_edit_node_id` (`:82`) | `__canopy_pending_structural_edit.nodeId` | `main.mbt:514, 904` |
| `js_take_sync_status` (`:92`) | `__canopy_pending_sync_status` | `main.mbt:702` |
| `js_take_action_overlay_node` (`:111`) | `__canopy_pending_action_overlay_node` | `main.mbt:713` |
| `js_take_action_key` (`:120`) | `__canopy_pending_action_key` | `main.mbt:731` |

This is the anti-pattern called out in the spec: an `Action` variant carries
an empty-string sentinel and the real payload is recovered from a global slot.
See `Msg::EditorStructuralEdit(op~ : String, node_id~ : String)` in
`msg.mbt:45` and its consumer at `main.mbt:901–919`. Inside the consumer the
empty-string check fires the pickup FFI; with non-empty arguments the variant
is structurally redundant.

### B. Direct DOM mutation (escape into the host page)

| FFI | Effect |
|---|---|
| `js_reconcile_editor_with_text(new_text)` (`:12`) | Reads `canopy-editor`, calls its CRDT setter, then mutates `el.projNode = ''`. |
| `js_sync_and_broadcast(_new_text)` (`:32`) | Calls `syncAfterExternalChange()` + `notifyLocalChange()` on the Web Component. |
| `js_set_editor_mode(mode)` (`:46`) | `el.mode = mode`. |
| `js_set_editor_selected_node(node_id)` (`:55`) | `el.selectedNode = node_id` — comment explicitly notes "steals focus from outline panel". |
| `js_reconcile_after_tree_edit` (`:148`) | Calls `el._bridge.afterLocalEdit()` — reaches into the component's private bridge field. |
| `js_focus_element(id)` (`:103`) | DOM `focus()`. |
| `js_focus_overlay_panel` (`:157`) | Shadow-DOM `querySelector` + `focus`. |
| `js_focus_outline_overlay` (`:193`) | Page-DOM `querySelector` + `focus`. |
| `js_focus_tree_rows` (`:202`) | Focuses the outline tree's row container. |
| `js_scroll_outline_to_selected` (`:184`) | `scrollIntoView` on the selected outline row. |
| `js_set_overlay_open(open)` (`:129`) | Writes `globalThis.__canopy_overlay_open`. |

These run as bodies of `@rabbita.effect(...)` (single-fire commands), and a
few run inside `raw_effect(..., kind=@rabbita_cmd.after_render)`. The latter
*does* exist in `rabbita@0.11.5` (`@rabbita_cmd.after_render`), which is what
the reference pattern calls "lifecycle scheduling". They are scattered across
the `update` function rather than concentrated in a lifecycle Sub.

### C. JSON-marshalled DOM reads

| FFI | Returns |
|---|---|
| `js_get_selected_node_rect` (`:136`) | `'{}'` or `'{top,left,bottom,right}'` from `getBoundingClientRect`. |
| `js_get_viewport_size` (`:167`) | `'{width,height}'`. |
| `js_get_outline_selected_rect` (`:174`) | bounding rect of outline row. |

The MoonBit side parses these in `parse_anchor_rect` (`main.mbt:306–352`).
Each call is a hand-rolled JSON contract with no typed wrapper.

### D. Browser performance tracing

`js_perf_begin` (`:210`), `js_perf_end` (`:220`). Cross-cutting; not specific
to the binding. These would be fine in a dedicated `perf` helper module; they
are not violations of the layered-binding rule, but they currently live
alongside the binding FFIs.

### Cross-cutting FFI issues

- **No newtype wrappers.** Every JS handle the binding cares about is a
  numeric `Int` (the CRDT `handle`) or a magic `globalThis.__canopy_*` slot.
  No `struct CmView(@rabbita/js.Value)` or `struct CanopyEditorElement(...)`
  exists in MoonBit. Consequently, the MoonBit type system gives no
  protection against e.g. passing the CRDT handle where the element handle is
  expected.
- **String-typed enums.** `mode : 'text' | 'structure'` round-trips as
  `String` (`js_set_editor_mode`); sync status round-trips as
  `"connected" | "connecting" | "disconnected" | "error"` strings
  (`main.mbt:702–710`). Both are MoonBit-side enums on the *Rabbita* side
  (`EditorMode`, `SyncStatus`) but lose typing across the boundary.
- **No null/undefined safety.** `js_focus_element` silently no-ops on
  `getElementById` returning null (acceptable). `js_get_selected_node_rect`
  returns the string `'{}'` as a sentinel for "not found"; the MoonBit
  parser handles that via `parse_anchor_rect`'s fall-throughs. Fine, but
  not type-safe.
- **Side-channel commit between FFIs.** `OutlineNodeClicked` builds a single
  `@rabbita.effect` closure that calls *two* FFIs in sequence
  (`js_set_editor_selected_node` followed by `js_focus_tree_rows`,
  `main.mbt:578–581`), the second specifically to undo the focus theft caused
  by the first. This is a smell that "set the selected node" should not have
  the focus side-effect baked into it.

## State shape

`Model` is defined in `examples/ideal/main/model.mbt:62–83`. The CodeMirror-
relevant fields are:

```
editor          : @editor.SyncEditor[@ast.Term]   // CRDT + projection; MoonBit-owned
companion       : @lambda.LambdaCompanion         // typing/eval companion
outline_state   : @proj.TreeEditorState[...]      // outline (not CM6)
mode            : EditorMode                      // mirrored to CM6 via FFI
selected_node   : String?                         // node id; pushed to CM6 via FFI
sync_status     : SyncStatus                      // mirrored from JS sync client
overlay         : OverlayState                    // action panel state (not CM6)
scope_map       : Map[NodeId, ScopeAnnotation]
highlight_set   : @immut/hashset.HashSet[NodeId]
drag_source / drop_target_id / drop_position      // outline DnD (not CM6)
intent_log      : Array[String]
```

There is **no field at all that represents the CodeMirror EditorView or its
state**. The CM6 `EditorView` lives entirely in `CanopyEditor.cmView`
(TypeScript-side, `canopy-editor.ts:58`). The CRDT (`SyncEditor`) is the
authoritative document; CM6's `state.doc` is a derived cache, kept in sync by
`syncCmFromCrdt` (`canopy-editor.ts:303–329`) which computes a minimal diff.

The `mode` field in `Model` is what tells *Rabbita* which view mode to render
buttons for; the actual swap between CM6 and ProseMirror happens in JS via the
`attributeChangedCallback` ↔ `switchMode` path (`canopy-editor.ts:106–121,
396–406`), driven by `js_set_editor_mode`.

This implies an **implicit "Hybrid (c)" answer** to design question 1
(document ownership): CRDT is authoritative; CM6 owns the live view buffer;
MoonBit `State` carries neither the doc string nor a version counter. The
absence of a version counter in `Model` is notable — `next_timestamp`
(`:71`) is a Lamport clock for tree edits, not a doc-state version.

## Action / Event enums

Defined in `examples/ideal/main/msg.mbt:2–46`. Annotated by category:

| Variant | Category | Notes |
|---|---|---|
| `SetMode(EditorMode)` | command (non-transactional) | dispatches `js_set_editor_mode` |
| `TogglePanel(PanelId)` | layout (no JS) | pure Rabbita |
| `SelectBottomTab(BottomTab)` | layout + focus | issues focus cmd via `bottom_tab_focus_cmd` |
| `StructuralEditRequested(op~, node_id~)` | inbound event with pickup | empty-string sentinel + `js_take_structural_edit_*` |
| `Undo` / `Redo` | transactional command | `editor.undo()` / `.redo()` + reconcile FFI |
| `TreeEdited(@lambda_edits.TreeEditOp)` | outline event (no JS) | not from CodeMirror |
| `DismissPanels` | layout | pure |
| `LoadExample(String)` | command (transactional) | `editor.set_text` + reconcile FFI |
| `OutlineNodeClicked(String)` | outline event → editor command | sets `selectedNode` + steals/restores focus |
| `OutlineNavigate(String)` | outline event → editor command | same pattern |
| `OutlineStructuralEdit(...)` | outline event → CRDT command | full reconcile FFI |
| `OpenActionOverlayFromOutline` | overlay open | `after_render` focus cmd |
| `SyncStatusChanged(String)` | inbound event with pickup | empty-string sentinel + `js_take_sync_status` |
| `OpenActionOverlay`, `CloseActionOverlay` | overlay open/close | `js_take_action_overlay_node` pickup |
| `ActionKeyPressed(String)`, `ActionTapped(String)` | overlay event | pickup pattern |
| `NamePromptInput`, `NamePromptSubmit`, `NamePromptCancel` | overlay sub-state | pure |
| `LongPressTriggered` | overlay open | pickup |
| `OutlineDrag*`, `OutlineDrop` | outline DnD (no CM6) | pure / CRDT |
| `EditorTextChanged` | inbound CM6 event | no payload; FFI already wrote the text |
| `EditorNodeSelected(String)` | inbound CM6 event | empty-string sentinel + `js_take_selected_node_id` |
| `EditorStructuralEdit(op~, node_id~)` | inbound CM6 event | duplicate of `StructuralEditRequested` shape |

Observations:

- The "inbound CM6 event" category is the part the spec's property 5 wants to
  convert to `@sub.custom_sub`-driven subs. Currently the three relevant
  variants (`EditorTextChanged`, `EditorNodeSelected`, `EditorStructuralEdit`)
  are woken by JS clicking hidden trigger buttons — see `view_editor.mbt:32–51`
  and `main.ts:wireEditorEvents` (`main.ts:137–253`). The button click event
  reaches Rabbita through Rabbita's normal `on_click` handler; the variant is
  then re-populated from the global slot.
- `EditorStructuralEdit` and `StructuralEditRequested` are near-duplicates,
  surfaced as a Phase 4 protocol migration leftover (comments at
  `msg.mbt:41–45`). The former is dispatched from `wireEditorEvents`
  (`main.ts:166–201`) for "structural-edit-request" CustomEvents; the latter
  used to be the old global-state path.
- No variant currently carries a typed `TransactionSpec` or a typed
  `Insert/Replace/SetDoc/SetSelection` shape (design question 2). The
  CRDT-side text intent is dispatched directly by JS via `handle_text_intent`
  (`canopy-editor.ts:249`), bypassing the Rabbita Msg pipeline entirely.

## Subscription wiring

There is no subscription wiring in the binding.

```
$ grep -rn "@sub\.\|custom_sub\|priv suberror\|RunningSub\|update_tagger" \
    examples/ideal/main/*.mbt
(no matches)
```

All inbound JS events traverse:

1. CM6 / sync client / Web Component dispatches a `CustomEvent`.
2. `main.ts:wireEditorEvents` (`main.ts:137–253`) attaches an
   `addEventListener` per event, with `{ signal }` for an
   `AbortController`-based teardown.
3. The listener writes the payload to `globalThis.__canopy_*`, then calls
   `clickTrigger('canopy-editor-XXX')` (`main.ts:121–124`) which performs
   `(document.getElementById(...) as HTMLButtonElement).click()`.
4. That click is caught by an `aria-hidden tabindex="-1"` button in the Rabbita
   tree (`view_editor.mbt:7–19`), wired to dispatch the matching `Msg`.
5. The `update` handler for that `Msg` re-reads the global slot via a
   `js_take_*` pickup FFI (Section A above).

This roundabout path replaces the property-5 prescription. The relevant
disposal story is also split: listeners are torn down by
`editorEventsController?.abort()` (`main.ts:139–141`); the CM6 view is torn
down by `disconnectedCallback → destroyCm()` (`canopy-editor.ts:92–103,
289–294`); the `ephemeralCleanupTimer` `setInterval` is cleared in
`beforeunload` (`main.ts:283–286`). No `update_tagger` equivalent — when the
Rabbita app re-renders, the `aria-hidden` buttons are recreated and Rabbita's
vdom reattaches `on_click`. The TS listeners are *unchanged* across renders
(they target the `<canopy-editor>` element, not the buttons), so the staleness
risk the reference pattern's `update_tagger` solves is sidestepped — but only
because there is *no* tagger to update.

## Extension handling

The spec (property + design question 3) asks how CM6 extensions are passed
and reconfigured. Today:

- Extensions are constructed entirely in TypeScript inside `mountTextMode`
  (`canopy-editor.ts:171–287`):
  - `CmView.theme(...)` — fixed style block
  - `cmKeymap.of(...)` — custom undo/redo + `defaultKeymap`
  - `CmView.lineWrapping`
  - `lineNumbers()`
  - `lambda()` (the `@codemirror/language` package built from
    `web/src/lang/lambda-language.ts`)
  - `syntaxHighlighting(lambdaHighlightStyle)`
  - `peerCursors()` (`web/src/cm6-peer-cursors.ts`)
  - Two `CmView.updateListener.of(...)`: one for `docChanged`, one for
    `selectionSet`
- There is no `Compartment`-based reconfiguration.
- `readonly` is "implemented" by *remounting* the entire `EditorView`
  (`canopy-editor.ts:114–120`). No MoonBit-side handle on extensions.
- No typed MoonBit wrapper exists for any extension. The lambda language is a
  TS module, not a MoonBit binding.

## Examples

The whole `examples/ideal/` *is* the example. There is no minimal "hello-world"
example exercising just the CodeMirror binding in isolation. The verification
checklist's item ("renders an editor, dispatches at least one programmatic
transaction, receives at least one outgoing event, disposes cleanly") is
covered end-to-end by `examples/ideal/web/e2e/` (Playwright) at the application
level, not at the binding level.

Indirectly, `view_editor.mbt:22–53` is the smallest snippet showing how the
binding integrates with Rabbita: it renders `<canopy-editor>` and seven hidden
trigger buttons.

## Gap list (prioritized)

Each item is annotated with `[blocker]` if it cannot be addressed without
first answering a question or upgrading a dependency, and with the property
number(s) it touches.

1. **[blocker — dep] Subscription API missing in rabbita 0.11.5.** Properties
   4 and 5 require `@sub.Sub`, `@sub.custom_sub`, `RunningSub`, and
   `priv suberror` payloads. None of those names appear in
   `examples/ideal/.mooncakes/moonbit-community/rabbita/**/pkg.generated.mbti`.
   Property 4's `Disposable(() -> Unit)` newtype can be hand-defined, but
   without `@sub.custom_sub` it has no home.

2. **[blocker — question 0] Package boundary.** The spec's property 1 expects
   a binding *package*. Today the binding is fused into
   `dowdiness/ideal-editor/main`. Before any other refactor we must decide
   whether to extract `lib/rabbita_codemirror/{js,_}` as a new local package
   (and at what path: `lib/`, top-level `rabbita_codemirror/`, or under
   `examples/ideal/`). This is not one of the spec's listed open design
   questions but it precedes all of them.

3. **[property 1, 2] FFI mis-located.** All 26 `extern "js"` calls live in
   the managed layer (`main/bridge_ffi.mbt`). They must move into a `js/`
   sub-package; the managed layer should call into them without naming
   `extern "js"`.

4. **[property 5] Hidden-trigger-button pattern must go.** Five inbound
   event paths (text-changed, node-selected, structural-edit, action-overlay-
   open, action-key, long-press, sync-status) currently traverse "JS writes
   global → JS clicks button → MoonBit reads global". Each becomes a
   `@sub.custom_sub`-driven `Sub` whose tagger constructs the typed `Msg`
   directly, eliminating the global slots and `js_take_*` FFIs.

5. **[property 2] No newtype wrappers for JS handles.** The CRDT handle is a
   raw `Int`; the editor element is anonymous (`document.querySelector` each
   time). Introduce `struct CanopyEditorEl(@rabbita/js.Value)` and probably
   `struct CmView(@rabbita/js.Value)` so the managed layer can hold typed
   handles in `Model` rather than relying on side-effecting queries.

6. **[property 6] Lifecycle is split between MoonBit `main()` and JS
   `bootstrap()`.** `examples/ideal/main/main.mbt:999–1002` calls
   `@rabbita.cell(...).mount("app")`; `examples/ideal/web/src/main.ts:308–356`
   then waits for `<canopy-editor>` to appear in the DOM via a
   `MutationObserver`, fetches `handle = 1`, and calls `el.mount(handle, crdt)`.
   The reference pattern owns this in a single `lifecycle` Sub. Even without
   the Sub API, the *async load* + *mount via `after_render`* halves of
   property 6 are reachable today (the latter via `@rabbita_cmd.raw_effect(..,
   kind=@rabbita_cmd.after_render)`, which the codebase already uses).

7. **[property 2] String-typed enums across the boundary.** `mode` and
   `sync_status` round-trip as strings. Introduce small MoonBit-side enum
   serializers (or, if going further, a tagged-union FFI) instead of relying
   on the string contract.

8. **[property 3] No `@js.load()` for CM6.** CodeMirror is loaded as a
   bundler-time `import` in `canopy-editor.ts:1–10`. The reference pattern
   would dynamic-`import` an ESM URL inside an `extern "js"` returning a
   `@rabbita/js.Promise`, with a `source~ : String` default. This may not be
   desirable for this app (see question 6 — module pinning policy), so it
   is the lowest-priority item in this list.

9. **[hygiene] `EditorStructuralEdit` and `StructuralEditRequested` duplicate
   each other.** Resolve into a single variant during property-5 work.

10. **[hygiene] `js_set_overlay_open` writes a global flag for JS code to
    read.** It is purely a coordination signal from MoonBit to JS; replace
    with a property on the `<canopy-editor>` element, or fold into the
    overlay-state subscription.

## Human decisions needed

The spec's six open design questions, plus dependency questions surfaced by
the audit. Phase 2 cannot start until these are answered.

### Audit-surfaced (must answer before any of the spec's questions are useful)

A. **Rabbita upgrade.** Properties 4 (`Disposable`) and 5
   (`@sub.custom_sub`) require a `rabbita` version exposing the `Sub` API.
   `examples/ideal/moon.mod.json` currently pins
   `moonbit-community/rabbita 0.11.5`, which exports no `Sub`. Decide:
   - (i) Upgrade `rabbita` to a version that ships `Sub`, and pin which version.
   - (ii) Land the structural reorganization (properties 1, 2, 6) now using
     `@rabbita.effect` + `@rabbita_cmd.raw_effect`, and defer 4/5 until the
     upstream API exists.
   - (iii) Vendor `rabbita_xterm` for read-only reference *and* contribute the
     `Sub` API upstream in `rabbita` itself before starting Phase 2 here.

B. **Binding package location.** Where does the extracted binding live?
   - (i) `lib/rabbita_codemirror/` as a new workspace member (matches `lib/`
     convention for the four current workspace members).
   - (ii) `rabbita_codemirror/` at the repo root, mirroring `rabbita_xterm`'s
     standalone-repo shape.
   - (iii) Keep it under `examples/ideal/` but split into
     `examples/ideal/rabbita_codemirror/{,js}` packages.

### Spec's open design questions (copied verbatim from the spec, in spec order)

1. **Document ownership.** Where does the authoritative document live?
   - (a) CodeMirror owns it; MoonBit `State` only stores a cached value
     updated by `Event::DocChanged(String)`.
   - (b) MoonBit `State` owns it; every external mutation re-dispatches a
     transaction.
   - (c) Hybrid: CodeMirror owns the live editor; MoonBit stores both a
     cached snapshot and an explicit version counter.

   *Audit observation*: today the **CRDT** (`SyncEditor`, MoonBit-owned)
   is authoritative, CM6 is a derived view (`syncCmFromCrdt`), and there is
   *no* version counter in `Model`. So today is closer to a "(b) without
   the version counter" hybrid where the canonical doc is a CRDT rather than
   a `String`. The decision should explicitly accommodate the CRDT.

2. **Action granularity.** Three plausible options, possibly combined:
   - (a) Low-level only: `Dispatch(TransactionSpec)` carrying an opaque JS
     spec.
   - (b) Semantic: `Insert(pos, text)`, `Replace(from, to, text)`,
     `SetDoc(text)`, `SetSelection(range)` — translated to transactions
     inside `update`.
   - (c) Both, with (a) as an escape hatch.

   *Audit observation*: today there is *no* outgoing-transaction `Action`
   at all. CM6 → CRDT goes through `handle_text_intent` (an exported MoonBit
   FFI called directly by `canopy-editor.ts:249`), and CRDT → CM6 is
   `js_reconcile_editor_with_text` followed by CM6's own
   `syncCmFromCrdt`. Programmatic dispatch from Rabbita to CM6 is currently
   limited to `selectedNode` and `mode` setters.

3. **Extension model.** Decide before writing wrappers:
   - (a) Single opaque `Extension(@rabbita/js.Value)` array passed at init;
     no reconfiguration.
   - (b) Typed wrappers per extension family (`lineNumbers()`, `keymap()`,
     `theme()`, language packages), each in its own subpackage like
     `addon/fit`.
   - (c) `Compartment`-based reconfiguration supported from day one, with
     `Action::Reconfigure(name, Extension)`.

   *Audit observation*: today (a)-ish, but constructed in TS, not MoonBit;
   `readonly` is implemented by remounting the whole view.

4. **Event surface.** The CM6 `updateListener` fires for many reasons.
   Should the binding emit:
   - (a) A single `Event::Updated(ViewUpdate)` carrying a structured MoonBit
     record (`doc_changed : Bool`, `selection_changed : Bool`,
     `focus_changed : Bool`, `new_doc : String?`, etc.).
   - (b) Multiple narrow events (`DocChanged`, `SelectionChanged`,
     `FocusChanged`) emitted from one underlying listener.
   - (c) Both, with narrow events as the default and `Updated` as an opt-in
     raw form.

   *Audit observation*: today the binding splits into two `updateListener`
   instances (one for doc, one for selection;
   `canopy-editor.ts:239–281`), but only `docChanged` actually reaches
   Rabbita as a `Msg` (`EditorTextChanged`). Selection changes are
   consumed for peer-cursor broadcast (`broadcastCursorDebounced`) and
   never reach the Rabbita loop.

5. **Language packages.** Are they in scope for this iteration? If yes,
   which ones, and do they live in this repo (`addon/lang_markdown`,
   `addon/lang_javascript`) or in separate repos?

   *Audit observation*: only Lambda is supported, and only in TS
   (`web/src/lang/lambda-language.ts` + `.grammar`). JSON and Markdown
   editors exist in `examples/web` but are out of scope of `examples/ideal`.

6. **Module pinning policy.** `rabbita_xterm` defaults to
   `https://esm.sh/@xterm/xterm@5.5.0`. Should the CodeMirror binding pin
   to a specific version of `@codemirror/*` packages, and to which? This
   affects API stability guarantees.

   *Audit observation*: today CodeMirror is bundled, not pinned to esm.sh.
   The current `package.json` of `examples/ideal/web/` is the source of
   truth for version pins; if Phase 2 introduces `@js.load()`, the URL
   needs an explicit version.

---

*End of Phase 1 report. No code changes have been made.*
