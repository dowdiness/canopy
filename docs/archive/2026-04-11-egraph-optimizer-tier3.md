# Tier 3: EGraph Optimizer for Lambda Calculus

**Status:** Complete (egraph#10, loom#78, canopy#158, 2026-04-11)

## Context

The lambda evaluator has Tiers 1-2 working (PR #150, #151). Tier 3 adds on-demand algebraic simplification via equality saturation. A comprehensive PoC exists in `loom/egraph/lambda_eval_wbtest.mbt` (562 lines) and `lambda_opt_wbtest.mbt` (655 lines) — beta reduction, constant folding, arithmetic identities, capture-avoiding substitution — all passing.

The PoC code lives as whitebox tests because the core egraph APIs (`EGraph`, `Runner`, `extract`, `AnalyzedEGraph`, `CostFn`) are all private. Promoting to production requires exposing them.

## Approach

**Phase 1** (loom): Expose egraph APIs + create `lambda-opt` example package.
**Phase 2** (canopy): Wire into editor with `optimize(Term) -> Term` public API.

## Phase 1: Egraph API Promotion + Lambda Optimizer Package

### Step 1: Expose core egraph APIs

**File:** `loom/egraph/egraph.mbt`

Make the following types and functions public:

| Current | Change to | Reason |
|---------|-----------|--------|
| `priv struct EGraph[L]` | `pub struct EGraph[L]` | Core data structure |
| `priv struct AnalyzedEGraph[L, D]` | `pub struct AnalyzedEGraph[L, D]` | Analysis-driven optimization |
| `priv struct RecExpr[L]` | `pub struct RecExpr[L]` | Extraction result |
| `priv struct CostFn[L]` | `pub struct CostFn[L]` | Cost function for extraction |
| `fn ast_size()` | `pub fn ast_size()` | Default cost function |
| `priv struct Analysis[L, D]` | `pub struct Analysis[L, D]` | Analysis callbacks |
| `priv struct Runner` | `pub struct Runner` | Saturation loop |
| `fn rewrite(name, lhs, rhs)` | `pub fn rewrite(...)` | Rule construction |

Also expose key methods: `EGraph::new`, `add`, `union`, `find`, `rebuild`, `size`, `extract`, `search`, `ematch`, `apply_rewrite`, `instantiate`; `AnalyzedEGraph::new`, `add`, `union`, `find`, `rebuild`, `data`, `extract`; `Runner::new`, `run`, `stop_reason`; `RecExpr::root`, `nodes`.

**Compilation checkpoint:** `cd loom/egraph && moon check`. Existing tests must still pass.

### Step 2: Create `loom/egraph/examples/lambda-opt/` package

**New files:**
- `moon.pkg` — imports `dowdiness/egraph`, `dowdiness/lambda/ast`
- `lang.mbt` — `LambdaLang` enum (11 variants) + `ENode`/`ENodeRepr` impls
- `convert.mbt` — `term_to_egraph()`, `term_add()`, `rec_expr_to_term()`
- `rules.mbt` — `arith_rules()`, `full_rules()` (6 identity + 3 structural)
- `analysis.mbt` — `EvalState`, `ValLit`, `subst_and_eval_analysis()`, `apply_subst()`
- `optimize.mbt` — `pub fn optimize(term: @ast.Term) -> @ast.Term`

The `optimize` function:
```
pub fn optimize(term : @ast.Term) -> @ast.Term {
  let (eg, root) = term_to_egraph(term)
  let analyzed = AnalyzedEGraph::new(eg, subst_and_eval_analysis())
  let rules = arith_rules()
  let runner = Runner::new(analyzed.egraph, roots=[root], node_limit=5000)
  runner.run(rules)
  analyzed.rebuild()
  let (_, rec) = analyzed.extract(root, ast_size())
  rec_expr_to_term(rec)
}
```

The `rec_expr_to_term` function converts `RecExpr[LambdaLang]` back to `@ast.Term`:
- `LNum(n)` → `Int(n)`
- `LVar(x)` → `Var(x)`
- `LAdd(a, b)` → `Bop(Plus, a', b')`
- `LLam(x, body)` → `Lam(x, body')`
- `LApp(f, a)` → `App(f', a')`
- `LLet(x, v, body)` → wraps as `Module([(x, v')], body')` for single let, nested for multiple
- `LSubst(_, _, _)` → should not appear after extraction (abort if it does)
- `LBool(true)` → `Int(1)`, `LBool(false)` → `Int(0)` (no Bool in Term)
- `LIsZero(e)` → `If(e', Int(0), Int(1))` (desugar back)
- `LMul(a, b)` → not in Term; abort (PoC-only node)

**Compilation checkpoint:** `cd loom/egraph && moon check`.

### Step 3: Tests

**File:** `loom/egraph/examples/lambda-opt/optimize_test.mbt`

- `optimize(Int(42)) == Int(42)` — identity
- `optimize(Bop(Plus, Int(2), Int(3))) == Int(5)` — constant fold
- `optimize(Bop(Plus, Var("x"), Int(0))) == Var("x")` — identity rule
- `optimize(App(Lam("x", Bop(Plus, Var("x"), Int(1))), Int(5))) == Int(6)` — beta + fold
- `optimize(Module([("x", Int(2))], Bop(Plus, Var("x"), Var("x")))) == Int(4)` — let + fold
- Hole/Error pass through unchanged (mapped to LNum(0), extracted back)

**Checkpoint:** `cd loom/egraph && moon test`.

### Step 4: Clean up egraph test files

Move PoC code out of `lambda_eval_wbtest.mbt` and `lambda_opt_wbtest.mbt`:
- Delete `LambdaLang`, `term_to_egraph`, `EvalState`, etc. from whitebox tests
- Rewrite tests as blackbox tests that call `@lambda_opt.optimize()` or import from the new package
- Keep egraph-level tests (identity rules, analysis callbacks) that don't need lambda types

**Checkpoint:** `cd loom/egraph && moon test` — all tests pass with new structure.

## Phase 2: Editor Integration (canopy)

### Step 5: Add dependency + public API

**File:** `canopy/lang/lambda/eval/moon.pkg` — add `dowdiness/egraph/examples/lambda-opt` dependency.

**File:** `canopy/lang/lambda/eval/optimize.mbt` — thin wrapper:
```
pub fn optimize_term(term : @ast.Term) -> @ast.Term {
  @lambda_opt.optimize(term)
}
```

Or integrate into the existing eval annotation system: when a definition has a `Value`, also show the optimized form if it differs from the original.

### Step 6: Incr wiring (optional, deferred)

Create `build_optimize_memo()` that recomputes optimized forms reactively. This is optional — we can start with on-demand calls and add reactive caching later.

## Verification

```bash
# Phase 1
cd loom/egraph && moon check && moon test
cd loom/egraph && moon info && moon fmt
git diff *.mbti  # review API changes

# Phase 2
moon check && moon test  # from canopy root
```

## Risks

- **API surface expansion** in egraph: making ~15 types/functions public is a significant API commitment. Review `.mbti` diff carefully before merging.
- **Node limit tuning**: commutativity rules cause blowup without `node_limit`. Default 5000 is a starting point — may need benchmarking.
- **LMul/LBool/LIsZero gap**: The `LambdaLang` PoC has nodes (`LMul`, `LBool`, `LIsZero`) that don't exist in `@ast.Term`. Either drop them from production `LambdaLang` or add `Mul`/`Bool`/`IsZero` to `@ast.Term`. Simpler: drop from `LambdaLang`, add later when the grammar supports them.
- **LSubst in extraction**: If `LSubst` nodes appear in the extracted result, the conversion back to `Term` fails. The analysis's `modify` hook should resolve all substitutions, but add an assertion.

## Scope

Phase 1: ~200 lines new code + ~150 lines moved from tests (loom, 1 PR)
Phase 2: ~30 lines (canopy, 1 PR)
