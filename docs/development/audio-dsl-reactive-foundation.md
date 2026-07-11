# Audio DSL and Reactive Foundation Requirements

Date: 2026-05-31

This note records the implementation and performance requirements for a
Canopy-hosted audio DSL prototype that lowers into MoonDsp graphs and uses
`incr` for authoring-time recomputation. It is a development report, not an
API commitment.

## Scope

The target system must support this pipeline:

```text
text edit / structural edit / control change
  -> parse and projection
  -> semantic graph and diagnostics
  -> normalized audio graph
  -> MoonDsp DspNode[]
  -> CompiledTemplate
  -> block-boundary runtime commit
```

The key constraint is that authoring work may allocate and use incremental
graphs, while the audio callback must only consume prepared runtime data.

## Repository and API map

| Area | Reusable surface | Responsibility for the audio DSL |
| --- | --- | --- |
| Canopy projection | `core/projection_memo.mbt`, `lang/markdown/proj/`, `lang/json/proj/` | Build `ProjNode`, registry, and `SourceMap` from syntax in a shared 3-memo pipeline. Markdown is the best reference for a CST-shaped language. |
| Canopy edits | `lang/markdown/edits/`, `lang/json/edits/`, `core/source_map.mbt` | Lower projection actions into field-local `SpanEdit` values using token roles. Use this for numeric parameters, identifiers, labels, and node constructor fields. |
| Canopy presentation | `loom/pretty/traits.mbt`, `protocol/formatted_view.mbt` | Keep source, pretty layout, and view rendering separate. Use the `Printable` trait family for stable source/pretty contracts, then render layout into view nodes. |
| Canopy semantics | `lang/lambda/semantic/semantic_projection.mbt` | Keep diagnostics, annotations, and decorations as side tables keyed by node IDs and source ranges. Do not bake transient semantic state into projection nodes. |
| Canopy lambda eval | `lang/lambda/eval/eval_memo.mbt` | Reference for layered incremental caches and previous-result reuse. Useful later, but too complex for the first audio DSL slice. |
| incr target facade | `Input`, `Derived`, `ReachableDerived`, `EagerDerived`, `Watch`, `Scope` | Own authoring state, derive parsed/semantic/lowered/template outputs, and anchor terminal reads with watches. |
| incr maps and reachability | `DerivedMap`, `ReachableDerived` | Add per-node caches only after whole-graph lowering is measured as a bottleneck. Sparse subscribed branches already benchmark well. |
| MoonDsp graph authoring | `graph/graph_node.mbt`, `graph/graph_builder.mbt` | Lower normalized DSL nodes either directly to flat `DspNode` arrays or through the tagless `GraphBuilder` interpreter. |
| MoonDsp runtime boundary | `graph/compiled_template.mbt`, `graph/graph_compile.mbt` | Treat `CompiledTemplate::analyze(Array[DspNode])` as the authoring/runtime exchange boundary. Runtime compile and hotswap must not receive raw ad hoc graph arrays. |
| MoonDsp controls | `graph/control_binding.mbt`, `graph/graph_runtime_control.mbt`, `pattern/control.mbt` | Route continuous parameter changes through validated control bindings and `GraphControl`, not through graph recompilation. |
| MoonDsp scheduler | `scheduler/scheduler.mbt` | Pattern snapshots and graph swaps are staged and committed at block boundaries. This is the model for Canopy-to-audio handoff. |
| MoonDsp Mini | `mini/incr_authoring.mbt`, `mini/doc_parser.mbt`, `specs/loom-mini-cst/src/projection.mbt` | Existing authoring reference: whole-document parse wrapped by incr, last-good document retention, persistent lowering cache, stable IDs, and a spec-local Loom projection. |

## Reusable implementation patterns

- Start with the Markdown/JSON 3-memo projection shape: parse syntax once,
  derive projection, derive registry, derive source map. This keeps renderer,
  edit routing, and semantic passes from depending on parser internals.
- Use `SourceMap` token roles for every editable DSL field: node name,
  constructor name, input reference, numeric literal, unit suffix, and output
  marker. Field-local edits should become `SpanEdit[]` before structural patch
  work is introduced.
- Keep semantic facts outside the projection tree. Diagnostics such as
  "unknown node", "missing output", "mono/stereo mismatch", and "invalid
  parameter range" should live in a semantic projection side table.
- Use the `Printable` split as the representation contract:
  `Source` for round-trippable source text, `Pretty` for annotated layout, and
  renderer code for view-specific concerns.
- Use MoonDsp's `CompiledTemplate` as the boundary. A Canopy DSL should produce
  a normalized authoring graph and then an `Array[DspNode]`; MoonDsp owns
  analysis, liveness, optimization, and runtime compile.
- Reuse the Mini authoring rule: parse errors do not replace the last valid
  document/template. The UI may show diagnostics, but the audio engine should
  keep playing the last valid compiled snapshot.
- Keep MoonDsp Mini as the pattern/control DSL. The graph DSL should not embed
  or replace Mini notation; it should expose named controls that Mini can drive.
- Prefer coarse incremental stages first. Add `DerivedMap` per-node lowering
  only after a benchmark shows that whole-graph lowering is a real bottleneck.

## Existing Mini DSL boundary

MoonDsp already has Mini as a pattern and control language. The graph DSL
proposed here is a topology language, so the two DSLs should remain separate
and meet through validated controls.

| Layer | Owner | Responsibility |
| --- | --- | --- |
| Mini DSL | MoonDsp | Pattern notation, note events, control automation, scheduler input, `ControlMap`. |
| Graph DSL | Canopy / external authoring | DSP topology, named controls, node parameters, graph diagnostics, source/projection editing. |
| MoonDsp graph runtime | MoonDsp | `DspNode[]`, `CompiledTemplate`, compile/hotswap, audio-safe processing. |

Canonical data flow:

```text
Mini PatternDoc / PatternSnapshot
  -> scheduler events + ControlMap
  -> ControlBindingMap resolves named controls
  -> GraphControl batch
  -> prepared CompiledDsp/Stereo runtime at block boundary

Graph DSL document
  -> normalized topology + declared controls
  -> DspNode[]
  -> CompiledTemplate
  -> compile/hotswap on control side
```

Design consequences:

- Mini owns pattern timing and event controls such as `sound`, `note`, `cutoff`,
  `gain`, and `pan`.
- The graph DSL may declare required or optional controls and defaults, but it
  should not duplicate Mini's pattern syntax.
- Parameter-only changes should flow through `ControlMap`, `GraphControl`, and
  control bindings.
- Topology changes should flow through graph lowering and
  `CompiledTemplate::analyze` on the control side.
- Parsing Mini, parsing the graph DSL, lowering graphs, and compiling templates
  must not happen in the audio callback.

Tracking issue: [dowdiness/moondsp#120](https://github.com/dowdiness/moondsp/issues/120).

## Minimal DSL draft

The first DSL should be graph-first, small, and close to the MoonDsp graph
model. It should describe topology, named controls, and outputs without
committing to a full music-pattern language.

Example:

```text
graph bass {
  freq = control("note", default=60).midi_hz()
  osc  = oscillator(saw, freq=freq)
  amp  = adsr(attack=5ms, decay=20ms, sustain=0.6, release=80ms)
  sig  = mul(osc, amp)
  filt = biquad(sig, mode=lowpass, cutoff=control("cutoff", default=1200), q=0.707)
  out(gain(filt, 0.8))
}
```

MVP grammar:

```text
program   = item*
item      = graph_def
graph_def = "graph" ident "{" stmt* "}"
stmt      = binding | output
binding   = ident "=" expr
output    = "out" "(" expr ")"
expr      = ident | number | string | call | chain
call      = ident "(" args? ")"
args      = arg ("," arg)*
arg       = ident "=" expr | expr
chain     = expr "|>" call
```

MVP constructors should map to the current MoonDsp node set: constants,
oscillators, noise, ADSR, biquad, delay, gain, multiplication, mix, clip,
output, pan, and stereo variants. Pattern syntax should remain out of scope for
the first graph DSL; Mini already owns pattern authoring and scheduler-facing
control events.

## AST and normalized graph requirements

The parser-facing AST should not mirror `DspNode`'s flat storage fields. Keep a
typed authoring model and lower it later.

Required authoring data:

- Stable IDs for graph, node definition, expression, field, and edge identity.
- Source span plus role spans for every editable token.
- Constructor name and unresolved argument list exactly as authored.
- Optional resolved node kind and type information after semantic analysis.
- Error placeholders for holes, invalid fields, dangling references, and
  unsupported constructors.
- Metadata extension point for UI-only state such as collapsed state, display
  label, color, and documentation comments.

Required normalized graph data:

- Topologically ordered node records with stable authoring IDs.
- Explicit input edges rather than implicit identifier strings.
- Explicit parameter records with value, unit, control binding, and validation
  status.
- Signal shape classification: at least `Mono`, `Stereo`, and `Control`.
- One or more declared outputs, with diagnostics if the graph has no output or
  ambiguous outputs.
- A mapping from authoring IDs to MoonDsp authoring indices so control bindings
  and diagnostics can refer back to source nodes after optimization.

Fields that should be left open for later:

- Version field for serialized DSL documents.
- Optional node metadata block for UI and collaboration data.
- Optional units beyond raw doubles (`Hz`, `ms`, normalized gain/pan).
- Optional channel layout beyond mono/stereo.
- Optional scheduling or pattern references, but not embedded pattern syntax in
  the first graph grammar.

## AST to DspNode lowering requirements

The lowering pipeline should be explicit and testable:

1. Parse text into CST/AST and recover token ranges.
2. Build projection and source map.
3. Resolve names and control references.
4. Type-check signal shapes, constructor arity, parameter ranges, finite
   numbers, and output existence.
5. Normalize topology and assign authoring indices.
6. Lower normalized records to `Array[DspNode]`.
7. Build and validate control bindings.
8. Analyze with `CompiledTemplate::analyze`.
9. Compile or hotswap on the control side, then stage the result for the next
   audio block.

Design rules:

- Parameter-only edits should use `GraphControl` where possible. They should
  not force topology lowering or template analysis.
- Topology edits may re-lower and re-analyze the graph, but this must happen
  outside the audio callback.
- Lowering errors should return typed diagnostics and keep the previous valid
  template alive.
- Non-finite numbers, negative delay sizes, invalid ADSR values, and unsupported
  control slots must be rejected before runtime compile.
- The authoring index map must remain available after optimization, because
  MoonDsp controls are validated against authoring indices.

## incr design

Use the target facade names for new Canopy-facing code:

```text
Input[String] source_text
  -> Derived[ParseResult]
  -> Derived[ProjectionBundle]
  -> Derived[SemanticGraph]
  -> Derived[NormalizedDslGraph]
  -> Derived[LoweredGraph]
  -> Derived[CompiledTemplate]
  -> Watch[CompiledTemplate or diagnostics]
```

Recommended stage ownership:

- `Input` owns source text and future structural patch streams.
- `Derived` owns parse, projection, semantic analysis, normalized graph,
  lowering, and template analysis.
- `ReachableDerived` is appropriate when a UI panel subscribes to only a
  reachable slice, such as one node's diagnostics or inspector data.
- `DerivedMap` can cache per-node semantic or lowering results after measured
  graph sizes justify it.
- `EagerDerived` or `Effect` should be restricted to UI/control-side effects,
  never audio-thread work.
- `Watch` anchors terminal reads. Do not rely on ad hoc reads to keep derived
  branches alive.
- `Scope` owns the pipeline lifetime and must be disposed when an editor tab or
  graph document is closed.

Recalculation units:

| Change | Recompute | Avoid |
| --- | --- | --- |
| Character edit in source | Parse/projection/semantic/lower/template, initially coarse-grained | Audio-thread parse or compile |
| Field-local edit through projection | Span edit, then same source-driven pipeline | Directly mutating `DspNode` without source/source-map update |
| Numeric slider or MIDI control | Control binding lookup and `GraphControl::set_param` | Rebuilding topology |
| Node add/remove/reconnect | Normalize, lower, analyze template, control-side compile/hotswap | Applying topology mutation inside sample loop |
| Pattern edit | Mini authoring snapshot, scheduler block-boundary queue | Mixing pattern parse with DSP graph compile |

## Audio safety requirements

The audio callback must follow the MoonDsp hot-path rules:

- No heap allocation in sample-rate or block-rate inner loops.
- No `Array::push`, dynamic resize, string building, interpolation, maps,
  closures that capture fresh state, `println`, parser work, or incr graph work.
- Use preallocated `FixedArray` buffers and mutable runtime state.
- Convert string-keyed `ControlMap` data into validated `GraphControl` batches
  before entering the audio block path.
- Commit new templates or pattern snapshots at block boundaries only.
- Treat `DspNode[]`, parser results, diagnostics, and UI metadata as authoring
  data, not audio-hot data.

The practical rule is simple: Canopy and incr prepare snapshots; MoonDsp's
runtime consumes snapshots.

## Performance budget

At 48kHz with 128-sample blocks:

```text
128 / 48000 = 2.6667 ms = 2666.7 us
```

Recommended budgets:

| Path | Budget | Rationale |
| --- | ---: | --- |
| Audio block processing | < 10% of block budget, roughly < 267us for common graphs | Leaves room for browser/host jitter, other voices, and scheduling overhead. |
| Block-boundary commit | O(1) pointer/snapshot swap where possible | The commit must be predictable even if authoring compile is expensive. |
| Control-side parse + lower + analyze | < 2-5ms for common edits | Keeps 60fps authoring responsive without tying the requirement to audio deadline. |
| Control changes | Prefer microsecond-scale binding + set-param batches | Continuous controls may update frequently and should not compile graphs. |

Measured on 2026-05-31:

| Suite | Case | Result | Interpretation |
| --- | --- | ---: | --- |
| incr UI shape bench | flat 1000 reactives | 271.03us | Fine for UI/control-side recomputation; do not run in audio callback. |
| incr UI shape bench | layered 1000 via 1 memo | 266.64us | Similar to flat; coarse stages are acceptable initially. |
| incr UI shape bench | sparse 1000, 10 subscribed | 1.95us | Strong evidence for reachable/sparse UI panels. |
| incr UI shape bench | tree 1023 memos + 512 leaves | 788.94us | Still below a UI frame, but about 30% of an audio block; keep off audio thread. |
| MoonDsp graph bench | `fm_voice/128` process | 11.39us | About 0.43% of a 128-sample block. |
| MoonDsp graph bench | `stereo_chain/128` process | 12.12us | About 0.45% of a block. |
| MoonDsp graph bench | `stereo_chain` compile | 14.13us | Compile is cheap now, but still belongs on the control side. |
| MoonDsp graph bench | `insert_delete_roundtrip/128` | 57.03us | Topology edit is about 2.14% of a block; acceptable as staged control-side work. |

Commands used:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/incr
rtk moon bench --release -p dowdiness/incr/tests -f ui_shape_bench_test.mbt

cd /home/antisatori/ghq/github.com/dowdiness/moondsp
rtk moon bench --release -p graph -f graph_benchmark.mbt
```

## Benchmark requirements for the DSL prototype

The first implementation should add benchmark coverage before optimizing:

- Parse/project/lower/template for small, medium, and large graph documents.
- Field-local numeric edit using projection spans.
- Identifier rename that invalidates name resolution but preserves topology
  shape.
- Parameter slider path through control binding without template rebuild.
- Topology edit: add/remove/reconnect one node and re-analyze template.
- Last-good-template path: introduce a parse/type error and verify the previous
  compiled template remains active.
- UI inspector path using reachable/per-node derived data.

Benchmark style:

- Follow Canopy's `lang/json/companion/json_benchmark.mbt` for edit-loop
  projection benches.
- Follow MoonDsp's `graph/graph_benchmark.mbt` for graph compile, hotswap, and
  topology benches.
- Record parse, semantic, lowering, analyze, compile, and commit phases
  separately. A single total number will hide the actionable bottleneck.

## Design risks and decisions

| Topic | Recommendation |
| --- | --- |
| Text-first vs structure-first | Start text-first using Canopy parser/projection patterns. Preserve stable structural IDs so a structure-first editor can be added without replacing the document model. |
| Stable ID alignment | Keep Canopy projection IDs, DSL semantic IDs, and MoonDsp authoring indices distinct but mapped. Do not expose optimized runtime indices as authoring identity. |
| Error handling | Use typed `Result`/diagnostic values for user-authored errors. Keep aborts for impossible internal invariants only. |
| `DspNode` equality and NaN | Do not depend on `DspNode` equality for incr backdating until the MoonDsp NaN/equality policy is explicit. Use coarser revision or no-backdate stages if needed. |
| Mini integration | Treat Mini as the pattern/control DSL and the graph DSL as topology authoring. Resolve shared controls through `ControlMap` and control bindings, not through duplicated syntax. |
| Units and types | MVP may store doubles, but parsing should preserve unit spans and semantic validation should know unit kinds. This leaves room for type-safe wrappers later. |
| Persistence and collaboration | Persist source text first. Structural patches and CRDT-aware graph edits need a separate patch model with stable IDs and conflict states. |
| Loom adoption for audio DSL | Use Loom/Canopy projection for the new DSL if structured spans and recovery are needed. Do not migrate MoonDsp Mini production parsing until the existing promotion criteria are met. |
| Trait extension | Add renderers before adding new traits. Extend `Printable` only if the new operation is representation-level and shared across languages. |

## Issue roadmap

The implementation should start by hardening integration seams, then add the
smallest user-visible graph DSL slice.

| Order | Issue | Why first |
| ---: | --- | --- |
| 1 | [loom#202](https://github.com/dowdiness/loom/issues/202) | Turns the last-good semantic attachment policy into a tested example before Canopy depends on it. |
| 2 | [loom#203](https://github.com/dowdiness/loom/issues/203) | Measures the actual unified `Parser` plus downstream projection shape. |
| 3 | [moondsp#120](https://github.com/dowdiness/moondsp/issues/120) | Prevents Mini pattern/control semantics from being duplicated in the graph DSL. |
| 4 | [moondsp#117](https://github.com/dowdiness/moondsp/issues/117) | Defines the external `DspNode[]` -> `CompiledTemplate` contract. |
| 5 | [moondsp#119](https://github.com/dowdiness/moondsp/issues/119) | Decides equality, NaN, and typed compile-error policy before incr backdating depends on graph/template values. |
| 6 | [canopy#422](https://github.com/dowdiness/canopy/issues/422) | Adds the minimal graph DSL parser/projection/source-map package. |
| 7 | [canopy#423](https://github.com/dowdiness/canopy/issues/423) | Adds normalized graph and MoonDsp lowering after parser/projection shape is proven. |
| 8 | [incr#140](https://github.com/dowdiness/incr/issues/140) | Documents target-facade patterns for long-lived authoring pipelines. |
| 9 | [incr#139](https://github.com/dowdiness/incr/issues/139) | Measures coarse vs per-node recomputation for the DSL-shaped pipeline. |
| 10 | [canopy#424](https://github.com/dowdiness/canopy/issues/424) | Adds Canopy authoring benchmarks and last-good-template guards. |
| 11 | [moondsp#118](https://github.com/dowdiness/moondsp/issues/118) | Adds external-authoring graph/control/template benchmarks once the boundary is explicit. |

First PR recommendation: implement or copy-test the Loom last-good semantic
attachment pattern before starting the Canopy graph DSL package. That makes the
malformed-input and previous-valid-template behavior testable from the start.

## Next implementation sequence

1. Land a tested Loom last-good semantic attachment example.
2. Document the Mini pattern DSL vs graph DSL integration boundary in MoonDsp.
3. Define the external MoonDsp lowering contract and error/equality policy.
4. Define the minimal graph DSL grammar, AST, semantic graph, and diagnostic
   shape in a Canopy language package.
5. Implement parse -> projection -> source map using the Markdown/JSON 3-memo
   pattern.
6. Implement semantic resolution and normalized graph lowering with stable ID
   maps.
7. Lower to MoonDsp `Array[DspNode]` and validate through
   `CompiledTemplate::analyze`.
8. Add control binding generation and a parameter-only update path.
9. Add benchmarks for parse/projection/lowering/template/control paths.
10. Only after benchmarks, split coarse derived stages into per-node
   `DerivedMap` caches where the numbers justify it.
