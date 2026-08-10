# Lambda diagnostic capability through a Formula

- **Reader:** Canopy and Incr maintainers reviewing a typed diagnostics seam.
- **Decision:** Check parity for the production raw diagnostics closure when parser snapshot, projection, and source map are typed ports.
- **Keep until:** This evidence receives review or is superseded.
- **Disposition:** Keep as executable evidence; this spike authorizes no production migration.

## Verdict

**Pass with constraints.** On the finite workloads in the disabled white-box
suite, the Formula preserves the production raw `Option`/value boundary. A
`Some` projection reads parser snapshot, projection, and source map in that
order and returns `Some((snapshot.source, DiagnosticSet))`. A `None` projection
returns `None` after only the first two reads. The parser snapshot is the exact
`@loom.ParseSnapshot[@ast.Term]` type.

The value-local catch handles only the two existing
`SemanticDiagnosticError` constructors: invalid source ranges and invalid
UTF-16 boundaries. It does not enclose `ctx.read`. #465/#469 structural
failures remain the outer `FormulaReadError`; an unauthorized foreign
`DeclaredRead` remains the middle `ProgramError`. No domain failure is
invented.

The raw oracle is a same-package white-box evaluation of the production
closure's private parser/projection/source-map members. `compute_view_patches`
is also exercised as the final protocol oracle. Its parser rows stay
parser-first; candidate semantic rows are projected with the existing editor
API and compared by range, severity, code, order, and rendered-message
containment.

## Workloads and boundaries

The suite covers bound `(x) => x`, free `(x) => y` (including exact semantic
message, code, labels, and UTF-16 range), a valid module, incomplete `if x then
y`, recovery to `(x) => x`, synthetic `None` projection, three-port
observation order, invalid source range, invalid UTF-16 boundary, one
three-source transaction/revision, a three-entry manifest, local Formula/export
provenance, foreign declaration authorization, and closed-region structure.

A parser snapshot, projection, and source map are staged together in one
transaction. The production catch currently classifies semantic range validation failures
as absence (`None`); whether this UI policy should survive a production
redesign remains open. Parser diagnostics are not reclassified as semantic
absence; incomplete-source final patch parity is checked separately.

## Existing APIs and limits

The spike reuses `ParseSnapshot`, `SyncEditor::parser_snapshot`,
`SourceMap::set_token_span`, `build_semantic_diagnostics`,
`project_diagnostics_for_source`, `compute_view_patches`, and the exact typed
`Store`/`Region`/`Source`/`Program`/`Formula` APIs from #465/#469. `Array`,
`Map`, `Option`, `Result`, `String`, and `DiagnosticSet` cover the evidence;
no production helper, error type, registry, effect, or consumer package is
added. The oracle is sequential and white-box, not a production integration or
concurrency proof.

Run from the repository root:

```bash
bash examples/spikes/lambda_diagnostic_capability_program/run.sh
```
