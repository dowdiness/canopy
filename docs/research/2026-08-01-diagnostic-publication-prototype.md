# Revision-bound diagnostic publication prototype (#1089)

## Behavioral boundary matrix

| Situation | Declared input / event | Expected publication decision | Published result |
| --- | --- | --- | --- |
| Current single-source completion | Active ticket, matching source revision, dependency identities, config, and producer generation | Accept | Atomically replace its channel only. |
| Source changes during work | Covered source revision differs | Reject | Preserve parser and every existing producer publication. |
| A0 -> A1 -> A0 | Original ticket has revision 0; current source is newer revision 2 even if text is equal | Reject original; a newly issued ticket may accept | Never revive an older request from text equality. |
| Out-of-order completions | A newer ticket supersedes the older ticket on one channel | Accept newer, reject older | Newer result remains authoritative. |
| Dependency/configuration change | A declared dependency or configuration identity differs | Reject | Preserve previous publication. |
| Unrelated source change | Changed source is outside declared coverage | Accept if every declared input matches | Precise invalidation only. |
| Two-source coverage | Either declared source changes | Reject | No mixed-current multi-source diagnostic set. |
| Cancellation / restart / duplicate | Ticket is inactive, generation differs, or ticket was consumed | Reject | No mutation. |
| Display assembly | Current parser channel plus producer channels | Deterministic | Parser first, then producer/channel lexical order. |
| Value preservation | Accepted neutral `DiagnosticSet` | Accept with copy | Messages, labels/styles/source/ranges and other Loom-owned values are retained; later producer mutation cannot escape. |

## Existing-API reuse check

* Reused: `@loom_core.DiagnosticSet::copy`, `items`, and `add_all` for
  defensive ownership and parser-first display assembly. The current
  `merge_current_diagnostics` in `editor/view_updater.mbt` is source-equality
  prior art only; it cannot distinguish a revived A0 request from its later
  identical text.
* Checked: `Map`/`Set` for host state keyed by distinct identities,
  `Array`/`Iter` for collection transformation/order, `Option`/`Result` for
  absence/error alternatives, `String`/`StringView` for host identities,
  `Buffer` for formatting, and `cmp`/`math` for ordering/numeric helpers.
  The core uses copied `Map`/`Set` values and `Array::sort_by`; it does not need
  `Buffer`, `Result`, or numeric helpers.
* Checked: `SyncEditor::parser_snapshot` exposes a coherent parser source,
  CST, AST, and diagnostics snapshot; `@analysis.SourceSnapshot` models a
  document/version/text-hash tuple; cognition's
  `ProviderSourceSnapshot`/request descriptors demonstrate explicit source and
  dependency provenance plus a deterministic fake-time driver.

## Coherent-snapshot verdict

**Negative prototype verdict.** `SyncEditor::parser_snapshot`
(`editor/sync_editor_parser.mbt:137-142`) is coherent for one parser's
source/CST/AST/diagnostics and the Loom diagnostic API copies its collections,
but it has no monotonic source revision suitable for a ticket. The current
`Coordinator::read_protected` (`workspace/coordinator/methods.mbt:156-190`)
validates and reads one `ProtectedCell[T]`; its registration owns an array of
independent protected reads (`workspace/coordinator/types.mbt:134-151`). Direct
current-host evidence therefore does not establish an atomic project-wide
capture of all declared source revisions, dependency identities, and
configuration identity.

Production integration therefore needs one highest-host, read-only
`DiagnosticPublicationInputSnapshot` seam that atomically returns: monotonic
revision for every declared source, dependency fingerprints, configuration
identity, and the relevant producer generation. It must be captured under one
coordinator protection boundary and detached from mutable host state. This
prototype deliberately does not add that production seam.

## Scope verdict

Tickets, revisions, dependency/configuration identities, cancellation, and
producer generations remain private editor orchestration state. The payload is
the existing neutral `@loom_core.DiagnosticSet`; no protocol, Loom diagnostic,
`AnalysisProjection`, FFI, or producer integration change is proposed.

## Validation and local mutation justification

The targeted native and JS editor release suites exercise the same deterministic
publication boundary. The core returns replacement state and command values;
its only local mutations copy a `Map`/`Set` before replacing that returned
state, build the returned command array, and sort a fresh array returned from
`Map::to_array`. The whitebox fake shell mutates only its test-local state and
recorded start/cancel arrays while executing those commands. Neither kind of
mutation escapes the core result or published `DiagnosticSet` boundary.
