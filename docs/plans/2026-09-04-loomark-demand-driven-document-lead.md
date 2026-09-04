# Loomark demand-driven Document lead implementation plan

**Status:** Draft

**Tracking:** [#1411 — Implement feature-owned Document leads and Recent documents in Loomark](https://github.com/dowdiness/canopy/issues/1411)

**Decision:** [Demand-driven Document lead](../decisions/2026-09-04-loomark-demand-driven-document-lead.md)

## Goal

Give Recent documents, Delete confirmation, and Export one content-derived way
to identify a Loomark document. Keep feature code discoverable, prevent Recent
documents from reading repository or Documents policy directly, and evaluate
Document leads only when a consumer demands them.

The implementation keeps the current app-level state machine and uses Rabbita as
the only incremental graph. The Recent documents feature owns that graph rather
than acting as a renderer leaf. It does not claim an elapsed-time performance
improvement; the prototype established callback suppression, keyed reuse,
orthogonal-input suppression, and scope disposal.

## Non-goals

- Moving `Model`, `Msg`, `Documents`, or their reducer protocol out of `app`.
- Adding a Catalog, stored title, persisted Document lead, or manual lead cache.
- Adding another `incr` runtime, an eager hidden observer, a generic storage
  trait, or a generic feature framework.
- Passing MarkdownIR, parser state, repository snapshots, commands, or DOM
  handles through a Document lead.
- Caching a parser per document, loading image thumbnails, syntax-highlighting
  code, or recognizing frontmatter unsupported by the current parser.
- Settling the provisional pane width or responsive breakpoint in code review;
  those values require browser comparison.

## Invariants

1. Document text in the app state remains the single editable authority.
2. Browser saving, lead extraction, and Preview preparation never become text
   authorities.
3. `Documents::reduce` remains the deterministic owner of selection, saving,
   deletion, and quiet-event acceptance.
4. Recent documents receives resolved presentation capabilities and emits
   intents. It cannot import `RepositorySnapshot`, Catalog state, composition
   state, save lanes, or deletion policy because the repository is below
   `app/internal`.
5. A Document lead contains only equality-relevant information that a consumer
   can present.
6. Lead extraction is total: non-empty text never becomes Empty solely because
   parsing or lowering fails.
7. A lead-specific transition consumes the shared `QuietElapsed` message by
   current change order, independently of Autosave lane eligibility.
   Maximum-delay, visibility-flush, and Save feedback do not replace the source.
   Quiet elapsed during IME is retained until composition ends or a newer change
   invalidates it.
8. Orthogonal selection, saving, and deletion changes do not change lead-source
   identity and therefore do not rerun extraction.
9. The outer keyed projection contains values only. HTML, commands, local UI
   state, timers, subscriptions, parser instances, and DOM handles belong
   outside it.
10. Hiding Recent documents disposes its rendered branch while preserving the
    feature-scoped pure lead graph.
11. Desktop and mobile use one page-lifetime visibility value. Viewport mode
    chooses presentation and effects.

## Package and API boundaries

The signatures below define responsibility and information flow. Exact MoonBit
spelling may change during the first compiling commit without widening a
boundary.

### `internal/document_lead`

Owns parsing, normalization, source fallback, and the content-derived-name
analysis moved from the Source repository.

```moonbit nocheck
pub enum DocumentLeadForm {
  Heading
  Task(Bool)
  Quote
  Code
  List(String)
  Plain
  Empty
} derive(Eq)

pub struct DocumentLead { ... } derive(Eq)

pub fn extract(source : String) -> DocumentLead
pub fn DocumentLead::form(Self) -> DocumentLeadForm
pub fn DocumentLead::primary(Self) -> String
pub fn DocumentLead::description(Self) -> String
pub fn derive_name(source : String) -> Result[String?, Unit]
pub fn derived_name_survives_edit(
  previous_source : String,
  source : String,
  expected_name : String?,
) -> Bool
```

`DocumentLead` fields stay private. `description` is structured plain text: it
may preserve meaningful newlines, indentation, list markers, and code spacing,
but it is not a Markdown block tree. The form stores only distinctions that
produce different presentation. Heading level is intentionally absent.

The package imports the Markdown interpretation needed to extract a lead and
enables `MarkdownExtensions::task_list()`. `derive_name` preserves the current
fail-closed Catalog semantics; `extract` is the separate total product
projection. `derived_name_survives_edit` encapsulates the current certified
prefix optimization without exposing offsets or parser nodes. The package
imports no app, repository, Rabbita, RUI, DOM, storage, timer, or command
package.

### `app/internal/source_repository`

Move the existing `internal/source_repository` package under `app/internal`
without changing persistence behavior. MoonBit then permits `app` to import it
but rejects an import from sibling `internal/recent_documents`.

The repository imports `document_lead` for `derive_name` and certified reuse.
Remove `derive_name` from the repository's generated public interface. Update
module/package documentation and every import path in the same mechanical
stage. Do not move `Model`, `Msg`, or Documents state with it.

### `internal/recent_documents`

Owns capability-resolved input types, lead derivation, keyed graph topology,
presentation, Delete confirmation, and intent emission. Its input is prepared
by `app`.

```moonbit nocheck
pub enum RecentSelection {
  Current
  Loading
  Other
} derive(Eq)

pub enum RecentSaveState {
  Saved
  NotSaved
} derive(Eq)

pub enum RecentDeleteState {
  Available
  Confirming
  Pending
  Failed
  Unknown
} derive(Eq)

pub struct RecentDocumentSeed { ... } derive(Eq)
pub struct RecentDocumentsFeature { ... }

pub fn RecentDocumentSeed::new(
  document_id : String,
  lead_source : String,
  selection : RecentSelection,
  save_state : RecentSaveState,
  delete_state : RecentDeleteState,
) -> Self
pub fn build(
  input : @rabbita.Val[Vector[RecentDocumentSeed]],
  sidebar : @sidebar.SidebarProvider,
  emit : @cmd.Emit[Intent],
) -> RecentDocumentsFeature
pub fn RecentDocumentsFeature::navigation(Self) -> @rabbita.Val[@html.Html]
pub fn RecentDocumentsFeature::dialog(Self) -> @rabbita.Val[@html.Html]

pub enum Intent {
  Create
  Select(String)
  RequestDelete(String)
  CancelDelete
  ConfirmDelete(String)
  Retry(String)
  Dismiss(String)
}
```

The exact handle shape may change if one output can be composed without a
second selector, but graph-building ownership must not move back to `app`.
`RecentDocumentSeed` contains lead-source text and already resolved row state.
Inside each outer keyed branch, project the lead-source value before combining
it with selection, saving, or deletion state.

Only include retry or dismiss intents when the existing Documents transition
actually exposes that capability. Do not create presentation actions that have
no reducer decision behind them. The package may import `document_lead`,
`sidebar`, Rabbita HTML/command APIs, and RUI primitives. It must not import
`app`; MoonBit package visibility must make importing
`app/internal/source_repository` fail.

### `internal/sidebar`

Replace the state-and-command `SidebarScope` boundary with an opaque provider
created once during app graph construction.

```moonbit nocheck
pub struct SidebarProvider { ... }

pub fn sidebar_provider(initial_visible : Bool) -> SidebarProvider
pub fn SidebarProvider::visible(Self) -> @rabbita.Val[Bool]
pub fn SidebarProvider::open(Self) -> @cmd.Cmd
pub fn SidebarProvider::close(Self) -> @cmd.Cmd
pub fn SidebarProvider::toggle(Self) -> @cmd.Cmd
```

The provider's layout method may still supply presentation helpers to its render
callback, but state values and `Emit`/`Cmd` capabilities must not be combined in
a `Val[SidebarScope]`. Viewport changes select fixed-pane, collapsed-rail,
fullscreen-overlay, or editor-only presentation while preserving the provider's
single visibility value.

### `app`

`app` continues to own:

- root and Documents transitions;
- lead-source revision and pending-quiet selection, independent of save-lane
  eligibility;
- conversion from Documents state to capability-resolved Recent-document input;
- mapping Recent-document intents back to app messages;
- Sidebar provider creation, capability projection, intent mapping, and layout
  composition;
- storage, timer, focus, and responsive effects.

No `internal/documents` package is introduced.

## Graph topology

Construct the graph in this ownership order:

```text
Document text
  -> accepted quiet LeadSource values
  -> app projects capability-resolved RecentDocumentSeed values
  -> recent_documents.build
       -> feature-scoped assoc_by(DocumentId)
            -> project lead-source identity
            -> document_lead.extract
            -> combine lead + orthogonal presentation state
       -> SidebarProvider.visible().switch_by
            Hidden  -> no Recent-documents consumer
            Visible -> assoc_by(DocumentId)
                         -> row Html, commands, and row-local state
```

The feature must create the outer `assoc_by` in its caller-owned construction
scope before `switch_by`. Moving it inside the Visible callback makes its keyed
branches children of the disposable visibility scope and destroys lead-cache
reuse on every reopen. `app` invokes this topology through `build`; it does not
assemble the combinators itself.

The inner `assoc_by` belongs inside the Visible branch. This ensures that Hide
disposes row HTML, commands, subscriptions, and row-local state. A key removed
while Hidden may retain an unobserved pure branch until the next pull or provider
disposal; the next Visible demand reconciles keys before rendering.

## Behavioral boundary matrix

| Context or event | App/Documents decision | Lead-source effect | Expected demand behavior |
|---|---|---|---|
| Initial load with valid Sources | Reconcile and select by existing rules | Seed each loaded document from its accepted text and change order | Hidden does no extraction; Visible extracts each demanded key once |
| Initial load with no Sources | Open a New document | No Recent-document key or lead source | No row and no extraction |
| Import accepted | Create a fresh identity and enter existing New/save path | Seed current imported text when it enters Recent documents | Extract immediately only when Visible |
| Empty New document | Remain outside Recent documents | No lead source | No keyed branch |
| First New-document text change | Create the document and reorder immediately | Seed first lead source from current text without waiting for save | Visible extracts once; Hidden defers |
| Later ordinary text edit | Update text, order, and unsaved presentation immediately | Preserve previous accepted lead source | Row status/order may update; lead extraction does not run yet |
| Selection/save/delete presentation changes only | Apply existing domain transition | Preserve identical lead-source value | Only affected rows rerender; extraction count is unchanged |
| Matching `QuietElapsed(id, order)`, not composing | Check current Document change order independently of save-lane state | Replace that document's lead source even if maximum/flush saving already ran | Visible recomputes that key; Hidden marks it dirty until demand |
| Matching `MaximumElapsed` or visibility flush before quiet | Apply existing Autosave checkpoint rules | Preserve the previous lead source without consuming future lead acceptance | A later matching quiet message still updates the lead |
| Save completes before matching quiet | Apply existing save feedback | Preserve the previous lead source | A later matching quiet message still updates the lead |
| Stale `QuietElapsed` | Reject by current Document change order | Clear no newer pending fact and preserve source | No extraction |
| `QuietElapsed` during IME composition | Preserve existing Autosave rules and record a pending lead-quiet order | Do not expose intermediate composed text | Previous lead remains visible |
| Composition ends with matching pending lead quiet | Apply existing composition transition, then validate the retained order | Replace lead source unless a newer text change invalidated it | Same as matching quiet event |
| Text changes after a pending lead quiet | Apply normal text transition | Clear the obsolete pending lead-quiet order | No extraction until the new revision becomes quiet |
| Save succeeds | Advance Saved text/order and clear unsaved presentation as already defined | No lead-source decision | Lead remains unchanged |
| Save fails | Retain memory text and expose retry capability | No lead-source rollback | Lead remains based on latest accepted quiet source |
| Select warm target | Apply existing switch decision | No lead-source change | Selection presentation updates; Wide stays visible, Narrow closes |
| Select cold target | Keep Editing Document until preparation succeeds | No lead-source change | Target row shows Loading; current content remains visible |
| Older read completes | Reject by existing latest-target rule | No change | No row becomes selected from stale feedback |
| Delete requested or cancelled | Open or close confirmation | Retain target lead | Confirmation uses the same lead presentation |
| Delete confirmed and Pending | Apply existing edit/switch restrictions | Retain target source while the document remains present | Pending presentation replaces available actions |
| Delete succeeds while Visible | Remove target | Remove key on current pull | Pure and row branches for that key dispose |
| Delete succeeds while Hidden | Remove target | Outer keyed graph may stay unreconciled | No immediate pure disposal is required; next Show removes it before render |
| Delete fails | Restore the existing failure/retry state | Retain source | Lead stays available with resolved actions |
| Delete outcome becomes Unknown | Isolate target according to deletion contract | Retain source until reconciliation decides otherwise | UI receives Unknown presentation, not policy inputs |
| Text changes while Hidden | Apply normal app transitions | Matching quiet event updates source | No extraction until another consumer demands the lead |
| Reopen unchanged | No domain transition | Source equality is unchanged | Rebuild visible rows and reuse pure leads |
| Wide startup | Create provider Visible | No source change | Demand Recent documents |
| Narrow startup | Create provider Hidden | No source change | Do not demand leads |
| Cross responsive breakpoint | Preserve one visibility value | No source change | Change presentation only; no visibility-driven recomputation |
| Narrow Back or successful selection | Close provider | No source change | Dispose visible rows and restore focus by shell effect |
| Wide selection | Keep provider visibility | No source change | Update selection presentation only |
| Provider/app disposal | End page lifetime | Release all remaining nodes | Dispose pure and visible scopes |

## Document-lead fixture matrix

Each fixture asserts form, primary readable text, structured description, and
that irrelevant parser metadata does not affect equality.

| Source class | Expected form | Required assertion |
|---|---|---|
| ATX Heading | Heading | Strip marker; omit heading level |
| Setext Heading | Heading | Same form as ATX |
| Checked and unchecked Task | Task | Preserve checked state; checkbox remains read-only |
| Block Quote | Quote | Preserve readable text without exposing MarkdownIR |
| Fenced Code | Code | Preserve code spacing; no syntax highlighting contract |
| Indented Code | Code | Same form as fenced code |
| Unordered List | List | Preserve bullet semantics |
| Ordered List | List | Preserve numbering semantics |
| Paragraph or other readable block | Plain | Preserve readable inline text |
| Empty or whitespace-only text | Empty | Primary and description contain no visible placeholder |
| Image with alt text | Plain | Use alt text without loading the image |
| Image without alt text | Continue/Empty | Skip unreadable structure and find later readable content |
| Inline emphasis, code, and link | Owning block form | Flatten readable text; link destination does not affect presentation |
| Multiline blocks | Owning block form | Preserve meaningful line boundaries in description |
| Nested indentation and lists | Owning primary plus plain description | Preserve indentation and markers without retaining a block tree |
| Parser Raw node with readable source | Plain fallback | Preserve non-empty readable source |
| Recovered parse with readable content | Recognized form or Plain | Never lose readable text because recovery metadata changed |
| Unsupported construct | Plain fallback | Produce a total value |
| Parser/lowering hard failure | Plain or Empty source fallback | Use non-empty source lines; only empty text becomes Empty |
| YAML-like leading text | Plain under the current parser | Do not invent frontmatter recognition |
| CRLF, CR, LF, and EOF termination | Same semantic form | Terminator differences do not erase readable content |

Add focused fixtures for top-level and container ownership wherever the current
Markdown API exposes both. Explicitly document and test any container form that
remains unsupported rather than silently treating it as Empty.

## Existing API First

Before introducing a definition, rerun `moon ide` discovery from the owning
module and record the result in the implementation PR.

| Candidate | Defined in | Intended use |
|---|---|---|
| `Val::map`, `map2`, and `view` | Rabbita | Derive equality-bearing inputs and HTML without imperative observers |
| `Val::assoc_by` | Rabbita | Own stable per-Document pure and rendered branches |
| `Val::switch_by` | Rabbita | Dispose the Visible branch while preserving the feature-scoped pure graph |
| `create_state` | Rabbita | Own Sidebar visibility behind an opaque provider |
| Existing `Documents::reduce` and decisions | Loomark `app` | Reuse selection, save, quiet, and deletion policy |
| Existing `derive_name_with_certificate` traversal | Current Loomark Source repository | Move and deepen rather than duplicating content recognition |
| `MarkdownExtensions::task_list`, parser/IR accessors | Loom Markdown example packages | Recognize tasks and readable structure before source fallback |
| `Vector` map/filter/from-iterator operations | MoonBit core | Prepare immutable ordered inputs without new manual loops |
| `Map`/`Set` | MoonBit core | Check keyed lookup needs; do not add one when `assoc_by` owns identity |
| `String`/`StringView` | MoonBit core | Slice and normalize fallback source without unnecessary copying |
| `Buffer`/`StringBuilder` | MoonBit core | Build structured descriptions only if existing Markdown text accessors cannot |
| `Option`/`Result` and pattern matching | MoonBit core | Make parser and fallback cases explicit and total |
| `cmp`/`math` helpers | MoonBit core | Clamp presentation-independent limits only if extraction requires them |
| `Array`/`Iter` | MoonBit core | Traverse parser children declaratively when no owning accessor exists |

Likely rejected candidates are a new cache map, an app-wide observer, a parser
per document, and a second incremental runtime. Any new helper must state one
narrow responsibility, such as converting one parser block into a normalized
lead fragment.

## Implementation stages

Each stage is a reviewable commit or smaller series. Start from a dedicated
worktree whose HEAD contains current `origin/main`; do not continue from the
prototype branch.

### 1. Enforce the repository boundary

- Move `internal/source_repository` to `app/internal/source_repository` as a
  behavior-preserving package and import migration.
- Update package maps, docs, tests, benchmarks, and generated interfaces.
- Add a small compiler probe or boundary check demonstrating that
  `internal/recent_documents` cannot import the relocated package.
- Run Source repository tests before any semantic extraction change.

### 2. Deepen `document_lead`

- Create the package by moving the existing derived-name traversal and tests
  from the Source repository; preserve fail-closed Catalog behavior first.
- Replace the repository's public `derive_name` with imports of
  `document_lead.derive_name` and `derived_name_survives_edit`.
- Add the opaque Document lead and the fixture matrix above, using task-list
  parsing, structured plain description, and total source fallback.
- Review both generated `.mbti` files: parser details and reusable-prefix offsets
  remain private, and the Source repository interface shrinks.

### 3. Sidebar visibility boundary

- Add the opaque provider and one visibility value.
- Adapt the current layout without changing Recent-document contents.
- Remove collapse/mobile state mirroring made obsolete by the provider.
- Prove Wide/Narrow startup, toggle, selection-close, resize preservation, focus
  restoration, and textarea identity in the browser.

### 4. Accepted LeadSource lifecycle

- Write the Documents transition matrix as failing reducer tests.
- Add the minimum per-document accepted source and revision state.
- Seed load, Import, and first New input.
- Add a lead-specific current-order check for the shared `QuietElapsed` message;
  do not call Autosave's lane-dependent `eligible_quiet` to decide the lead.
- Retain a matching lead-quiet order across IME composition, accept it on
  composition end, and clear it on a newer text change.
- Prove maximum-before-quiet, visibility-flush-before-quiet,
  save-completes-before-quiet, quiet-during-IME, and newer-change invalidation.
- Keep deletion feedback independent from lead-source acceptance.

### 5. Capability-resolved feature inputs

- Define `RecentDocumentSeed::new` and intent constructors in
  `internal/recent_documents`; keep seed fields private across the package
  boundary.
- Derive immutable seeds in `app` from current Documents state.
- Encode only the capabilities and presentation states the feature needs.
- Compile a forbidden-import probe after the real package exists.

### 6. Feature-owned incremental graph and UI

- Implement `recent_documents.build` and its opaque output handle.
- Construct the outer `assoc_by(DocumentId)` before visibility branching.
- Project lead-source identity before combining selection, save, and deletion
  presentation, so status-only updates do not rerun extraction.
- Construct the inner keyed row projection inside the Visible branch.
- Move navigation, Delete confirmation, and intent emission behind the feature.
- Preserve New, selection, loading, save warning, deletion, empty-state, and
  accessibility behavior from the product contract.
- Add callback-count probes only in tests; production nodes remain pure.

### 7. Remaining shared consumer

- Derive Export's suggested filename through `document_lead` at download time
  without storing a name or reaching into the Recent-documents cache.
- Keep Export-specific sanitization and formatting outside the semantic core.

### 8. Integration and independent review

- Exercise responsive behavior, focus restoration, textarea identity, Preview
  lifecycle, IME, concurrent save/delete feedback, hidden changes, and reopen.
- Compare actual callback counts with both prototype commits.
- Re-run the existing JS release benchmarks as regression evidence; add a
  Document-lead benchmark only if making a numerical performance claim.
- Run MoonBit-specific independent review before final validation.
- Fetch `origin/main` again and repeat affected checks after any sync.

## Validation

Use the affected package loop during implementation:

```bash
cd apps/loomark
NEW_MOON_MOD=0 moon check app --target js
NEW_MOON_MOD=0 moon test app --target js --release
NEW_MOON_MOD=0 moon check app/internal/source_repository --target js
NEW_MOON_MOD=0 moon test app/internal/source_repository --target js --release
NEW_MOON_MOD=0 moon bench app/internal/source_repository --target js --release
NEW_MOON_MOD=0 moon check internal/document_lead --target js
NEW_MOON_MOD=0 moon test internal/document_lead --target js --release
NEW_MOON_MOD=0 moon bench internal/document_lead --target js --release
NEW_MOON_MOD=0 moon check internal/recent_documents --target js
NEW_MOON_MOD=0 moon test internal/recent_documents --target js --release
NEW_MOON_MOD=0 moon check internal/sidebar --target js
NEW_MOON_MOD=0 moon test internal/sidebar --target js --release
NEW_MOON_MOD=0 moon info
NEW_MOON_MOD=0 moon fmt
```

Review every generated `.mbti` diff, especially trait bounds and mutable values.
Build the browser artifacts and validate the Loomark route after targeted tests:

```bash
moon build --target js
npm --prefix apps/web run typecheck
npm --prefix apps/web run check:boundaries
```

Use the repository's current browser-development command to exercise Wide and
Narrow workflows manually. Run broader workspace and CI-matching checks only
after the affected loop is green and the candidate commit is current with
`origin/main`.

## Risks and rollback

- **Outer keyed graph placed in the wrong scope:** Reopen re-extracts every lead.
  Keep its construction inside the feature but before `switch_by`, and retain
  callback-count coverage.
- **Orthogonal input broadens extraction identity:** Save or selection changes
  rerun Markdown work. Project lead-source text before extraction and test
  status-only changes.
- **Repository move changes behavior:** Treat it as a mechanical first stage and
  require unchanged repository tests and benchmark shape before deepening name
  analysis.
- **LeadSource becomes another text authority:** Limit it to an accepted source
  snapshot for projection; editing, saving, and switching continue to read
  Document text.
- **Presentation input leaks policy:** Remove raw repository/Documents state and
  replace it with the smallest resolved enum or intent.
- **Parser metadata destabilizes equality:** Normalize to visible form and text
  before constructing `DocumentLead`.
- **Sidebar refactor disrupts editor lifecycle:** Preserve textarea and Preview
  ownership and validate identity across every visibility and breakpoint action.
- **Scope retention grows while permanently hidden:** Accept demand-time cleanup
  initially. Add eager eviction only after a demonstrated product or memory
  requirement.
- **Feature handle becomes a framework:** Keep it specific to Recent documents
  and expose only the layout outputs that Loomark actually composes.

Rollback by stage. The repository move can be reverted before semantic work;
Sidebar can temporarily retain its old renderer while the provider API is
proven; lead extraction can remain unused until app inputs are ready; Recent
documents can switch to the feature-owned renderer only after behavioral parity.
Remove a failed stage instead of preserving adapters, duplicate caches, or dual
state paths. The throwaway prototype remains on its prototype branch and never
becomes a production fallback.
