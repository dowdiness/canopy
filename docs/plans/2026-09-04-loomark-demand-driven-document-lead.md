# Loomark demand-driven Document lead implementation plan

**Status:** Draft

**Tracking:** No GitHub issue has been filed. File and link one before treating
this document as an active implementation commitment.

**Decision:** [Demand-driven Document lead](../decisions/2026-09-04-loomark-demand-driven-document-lead.md)

## Goal

Give Recent documents, Delete confirmation, and Export one content-derived way
to identify a Loomark document. Keep feature code discoverable, prevent Recent
documents from reading repository or Documents policy directly, and evaluate
Document leads only when a consumer demands them.

The implementation keeps the current app-level state machine and uses Rabbita as
the only incremental graph. It does not claim an elapsed-time performance
improvement; the prototype established callback suppression, keyed reuse, and
scope disposal.

## Non-goals

- Moving `Model`, `Msg`, `Documents`, or their reducer protocol out of `app`.
- Adding a Catalog, stored title, persisted Document lead, or manual lead cache.
- Adding another `incr` runtime, an eager hidden observer, or a generic storage
  trait.
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
   intents. It never reads `RepositorySnapshot`, Catalog state, composition
   state, save lanes, or deletion policy.
5. A Document lead contains only equality-relevant information that a consumer
   can present.
6. Lead extraction is total: non-empty text never becomes Empty solely because
   parsing or lowering fails.
7. A later lead source replaces an earlier one only after the matching quiet
   event is accepted. Save success is irrelevant to this replacement.
8. The outer keyed projection contains values only. HTML, commands, local UI
   state, timers, subscriptions, parser instances, and DOM handles belong
   outside it.
9. Hiding Recent documents disposes its rendered branch while preserving the
   app-scoped pure lead graph.
10. Desktop and mobile use one page-lifetime visibility value. Viewport mode
    chooses presentation and effects.

## Package and API boundaries

The signatures below define responsibility and information flow. Exact MoonBit
spelling may change during the first compiling commit without widening a
boundary.

### `internal/document_lead`

Owns parsing, normalization, and source fallback.

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
```

`DocumentLead` fields stay private. `description` is structured plain text: it
may preserve meaningful newlines, indentation, list markers, and code spacing,
but it is not a Markdown block tree. The form stores only distinctions that
produce different presentation. Heading level is intentionally absent.

The package imports the Markdown interpretation needed to extract a lead. It
imports no app, repository, Rabbita, RUI, DOM, storage, timer, or command
package.

### `internal/recent_documents`

Owns presentation and intent emission. Its input is prepared by `app`.

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

pub struct RecentDocumentInput { ... } derive(Eq)

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

Only include retry or dismiss intents when the existing Documents transition
actually exposes that capability. Do not create presentation actions that have
no reducer decision behind them. The package may import `document_lead`,
Rabbita HTML/command APIs, and RUI primitives. It must not import `app` or
`source_repository`.

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
- accepted lead-source revision selection;
- conversion from Documents state to capability-resolved Recent-document input;
- mapping Recent-document intents back to app messages;
- Sidebar provider creation and graph composition;
- storage, timer, focus, and responsive effects.

No `internal/documents` package is introduced.

## Graph topology

Construct the graph in this ownership order:

```text
Document text
  -> accepted quiet LeadSource values
  -> app-scoped assoc_by(DocumentId)
       -> document_lead.extract
       -> pure RecentDocumentInput values
  -> SidebarProvider.visible().switch_by
       Hidden  -> no Recent-documents consumer
       Visible -> assoc_by(DocumentId)
                    -> recent_documents row Html and row-local state
```

The outer `assoc_by` must be created in app scope before `switch_by`. Moving it
inside the Visible callback makes its keyed branches children of the disposable
visibility scope and destroys lead-cache reuse on every reopen.

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
| Matching `QuietElapsed(id, order)` | Accept only when it names the current eligible revision and composition permits it | Replace that document's lead source | Visible recomputes that key; Hidden marks it dirty until demand |
| Stale `QuietElapsed` | Ignore by existing change-order guard | No change | No extraction |
| IME composition active | Preserve existing composition and Autosave rules | Do not accept a premature lead source | Previous lead remains visible |
| Composition ends | Resume the existing quiet lifecycle | Matching later quiet event may replace source | Same as matching quiet event |
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
| `Val::switch_by` | Rabbita | Dispose the Visible branch while preserving the app-scoped graph |
| `create_state` | Rabbita | Own Sidebar visibility behind an opaque provider |
| Existing `Documents::reduce` and decisions | Loomark `app` | Reuse selection, save, quiet, and deletion policy |
| Existing Markdown parser/IR accessors | Loom Markdown example packages | Reuse recognized structure before source fallback |
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

### 1. Sidebar visibility boundary

- Add the opaque provider and one visibility value.
- Adapt the current layout without changing Recent-document contents.
- Remove collapse/mobile state mirroring made obsolete by the provider.
- Prove Wide/Narrow startup, toggle, selection-close, resize preservation, focus
  restoration, and textarea identity in the browser.

### 2. Accepted LeadSource lifecycle

- Write the Documents transition matrix as failing reducer tests.
- Add the minimum per-document accepted source and revision state.
- Seed load, Import, and first New input.
- Reuse matching `QuietElapsed` acceptance and reject stale events.
- Keep save and deletion feedback independent from lead-source acceptance.

### 3. Pure `document_lead` package

- Add the package with private representation and the fixture matrix above.
- Reuse Markdown and core text APIs before adding traversal helpers.
- Implement recognized forms, structured plain description, and total source
  fallback.
- Review the generated `.mbti` for accidental parser or mutable-container leaks.

### 4. Capability-resolved Recent-document inputs

- Derive immutable inputs in `app` from current Documents state.
- Encode only the capabilities and presentation states the renderer needs.
- Add compile-time package boundaries that prevent repository and app imports.

### 5. Pure app-scoped keyed graph

- Construct the outer `assoc_by(DocumentId)` before visibility branching.
- Derive and cache `DocumentLead` plus resolved row input.
- Add callback-count probes only in tests; production nodes remain pure.

### 6. Visible Recent-documents package

- Move row rendering and intent emission behind `internal/recent_documents`.
- Construct the inner keyed row projection inside the Visible branch.
- Preserve New, selection, loading, save warning, deletion, empty-state, and
  accessibility behavior from the product contract.

### 7. Shared consumers

- Use the same Document lead for Delete confirmation.
- Derive Export's suggested filename at download time without storing a name.
- Keep consumer-specific formatting outside `document_lead`.

### 8. Integration and independent review

- Exercise responsive behavior, focus restoration, textarea identity, Preview
  lifecycle, IME, concurrent save/delete feedback, hidden changes, and reopen.
- Compare actual callback counts with the accepted prototype behavior.
- Run MoonBit-specific independent review before final validation.
- Fetch `origin/main` again and repeat affected checks after any sync.

## Validation

Use the affected package loop during implementation:

```bash
cd apps/loomark
NEW_MOON_MOD=0 moon check app --target js
NEW_MOON_MOD=0 moon test app --target js --release
NEW_MOON_MOD=0 moon check internal/document_lead --target js
NEW_MOON_MOD=0 moon test internal/document_lead --target js --release
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
  Keep its construction before `switch_by` and retain callback-count coverage.
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

Rollback by stage. Sidebar can temporarily retain its old renderer while the
provider API is proven; lead extraction can remain unused until app inputs are
ready; Recent documents can switch to the new renderer only after behavioral
parity. Remove a failed stage instead of preserving adapters, duplicate caches,
or dual state paths. The throwaway prototype remains on its prototype branch and
never becomes a production fallback.
