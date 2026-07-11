# Egglog Relational Evaluator — Implementation Plan (Phase 1)

## Why

Phase 0 exposed `Database::scan` and `Database::row_count`. Phase 2 built a
direct tree-walking evaluator. Phase 1 validates the *relational* evaluation
model — Datalog rules + MoonBit bridge — which is the novel contribution
enabling partial evaluation of incomplete programs and composition with typing.

## Scope

In:
- `loom/egglog/examples/lambda/lambda.mbt` — rename `InEnv` → `TypeEnv`
- `loom/egglog/examples/lambda/lambda_test.mbt` — rename `InEnv` → `TypeEnv`
- `loom/egglog/examples/lambda-eval/` — new package (eval.mbt, eval_test.mbt)

Out:
- `Term` AST → egglog conversion (Phase 3)
- Module → nested Let desugaring (Phase 3, needs Term access). **Deviation from
  parent design doc:** the parent lists this in Phase 1 acceptance criteria, but
  this package has no `Term` dependency. Tests construct egglog facts directly.
  The desugaring belongs in Phase 3 where `Term` → egglog seeding is built.
- Bool/IsZero evaluation rules (forward-compatibility, deferred — parser doesn't
  produce booleans yet)
- Editor integration, incr wiring (Phase 3)
- EGraph optimizer (Phase 4)

## Current State

- **Typing example** (`examples/lambda/`): 672 lines. `lambda_db()` registers
  24 tables (expression constructors, type constructors, env constructors,
  typing relations). `LambdaEnv` builds type environments. `lambda_rules()`
  returns ~12 typing rules. Variable type lookup uses `InEnv(env, name) → type`.
- **Phase 0** (just merged): `Database::scan` and `Database::row_count` on the
  public API.
- **Phase 2** (done): Direct evaluator in `loom/examples/lambda/src/eval/`.
  31 tests, all Term variants, fuel-limited.
- **Design spec**: `docs/plans/2026-04-02-lambda-evaluator-design.md` — full
  schema, rules, bridge pseudocode, escalation protocol.

## Desired State

A standalone egglog example (`examples/lambda-eval/`) demonstrating relational
evaluation with the Datalog + Bridge hybrid architecture:

1. **17 Datalog rules** handle demand propagation (5), leaf resolution (4),
   trigger detection (5), and result propagation (3).
2. **`evaluation_bridge()`** handles arithmetic, branch selection, environment
   creation, and runtime type error detection.
3. **Partial evaluation** works: holes block their own `Eval` but siblings
   evaluate normally. If branches only demand the taken branch.
4. **Composition with typing**: same Database, separate `TypeEnv`/`ValEnv`
   tables, no cross-contamination.
5. **20+ tests** covering arithmetic, beta reduction, let-bindings, if-branching,
   partial evaluation, runtime type errors, and fact count limits.

## Naming

Standard compiler environment naming (Γ/ρ convention):

| Table | Purpose | Reads as |
|-------|---------|----------|
| `TypeEnv(env, name) → type` | Type environment (typing) | Γ(x) = τ |
| `ValEnv(env, name) → value` | Value environment (eval) | ρ(x) = v |

Rename existing `InEnv` → `TypeEnv` in the typing example as a prerequisite.

## Schema (20 new tables)

```
-- Evaluation
Demand(env, expr)              → IntVal(1)      // demand trigger
Eval(env, expr)                → value_id       // evaluation result
ValEnv(env, name)              → value_id       // value environment

-- Value constructors
Closure(env, x, body)          → id
ValInt(IntVal(n))              → id
ValUnit()                      → id

-- Trigger tables (Datalog → bridge)
AddReady(env, expr)            → IntVal(1)
MinusReady(env, expr)          → IntVal(1)
IfReady(env, expr)             → IntVal(1)
AppReady(env, expr)            → IntVal(1)
LetReady(env, expr)            → IntVal(1)

-- Bridge metadata (bridge → Datalog)
IfBranch(env, expr)            → branch_expr_id
AppBodyEnv(env, expr)          → ext_env_id
AppBody(env, expr)             → body_expr_id
LetBodyEnv(env, expr)          → ext_env_id
LetBody(env, expr)             → body_expr_id

-- Error + sentinel constructors
EvalError(env, expr)           → StrVal(msg)
HoleNode(IntVal(id))           → id
ErrorNode(StrVal(msg))         → id
UnboundNode(StrVal(name))      → id
```

## Rules (17 total)

**Demand propagation (5):** Push demand top-down through expression structure.
```
demand-app:      Demand(env, e), App(f, arg, e)         ⟹ Demand(env, f), Demand(env, arg)
demand-add:      Demand(env, e), Add(a, b, e)           ⟹ Demand(env, a), Demand(env, b)
demand-minus:    Demand(env, e), Minus(a, b, e)         ⟹ Demand(env, a), Demand(env, b)
demand-if-cond:  Demand(env, e), If(c, t, el, e)        ⟹ Demand(env, c)
demand-let-val:  Demand(env, e), Let(x, val, body, e)   ⟹ Demand(env, val)
```

Note: `demand-if-cond` only demands the condition. The bridge selects which
branch to demand after the condition evaluates.

**Leaf resolution (4):** Resolve values bottom-up for terminal expressions.
```
resolve-num:     Demand(env, e), Num(n, e)                       ⟹ Eval(env, e) = ValInt(n)
resolve-var:     Demand(env, e), Var(x, e), ValEnv(env, x, v)   ⟹ Eval(env, e) = v
resolve-lam:     Demand(env, e), Lam(x, body, e)                ⟹ Eval(env, e) = Closure(env, x, body)
resolve-unit:    Demand(env, e), Unit(e)                         ⟹ Eval(env, e) = ValUnit()
```

**Trigger detection (5):** Detect when operands are evaluated and bridge action
is needed. Written by Datalog, read by bridge.
```
trigger-add:     Demand(env, e), Add(a, b, e), Eval(env, a, va), Eval(env, b, vb)
                 ⟹ AddReady(env, e) = IntVal(1)
trigger-minus:   (same pattern for Minus)
trigger-if:      Demand(env, e), If(c, t, el, e), Eval(env, c, vc)
                 ⟹ IfReady(env, e) = IntVal(1)
trigger-app:     Demand(env, e), App(f, arg, e), Eval(env, f, clos), Eval(env, arg, v)
                 ⟹ AppReady(env, e) = IntVal(1)
trigger-let:     Demand(env, e), Let(x, val, body, e), Eval(env, val, v)
                 ⟹ LetReady(env, e) = IntVal(1)
```

**Result propagation (3):** Propagate results after bridge writes metadata.
```
resolve-if:      IfBranch(env, e, branch), Eval(env, branch, result)
                 ⟹ Eval(env, e) = result
resolve-app:     AppBodyEnv(env, e, ext), AppBody(env, e, body), Eval(ext, body, result)
                 ⟹ Eval(env, e) = result
resolve-let:     LetBodyEnv(env, e, ext), LetBody(env, e, body), Eval(ext, body, result)
                 ⟹ Eval(env, e) = result
```

## Bridge Function

```
fn evaluation_bridge(db, processed) -> Bool:
  check fact count limit (Eval > 10000 → stop)
  for each trigger table (AddReady, MinusReady, IfReady, AppReady, LetReady):
    scan trigger table, skip already-processed (env, expr) pairs
    handle trigger:
      Add/Minus: extract ints from Eval, compute, write Eval or EvalError
      If: extract int from Eval(condition), select branch, write IfBranch, seed Demand
      App: extract closure from Eval(func), create_eval_env, write AppBodyEnv/AppBody, seed Demand
      Let: get val from Eval, create_eval_env, write LetBodyEnv/LetBody, seed Demand
  db.rebuild()
  return whether any new facts were produced
```

**`ValueEnv`:** Host-side struct mirroring `LambdaEnv` from the typing
example. Holds a MoonBit-side `Map[String, Value]` of visible bindings so
environment extension avoids scanning the `ValEnv` table entirely.

**`create_eval_env(db, val_env, name, value)`:** Creates `ExtendEnv`, extends
`ValueEnv`, and seeds `ValEnv` for all visible bindings. The eval
counterpart of `LambdaEnv::extend()`. Uses the host-side binding map instead
of `db.scan("ValEnv")` to avoid O(n) scans and canonicalization issues with
stale `IdVal` representatives after `rebuild()`.

## Outer Loop

```
fn run_eval(db, env_id, expr_id, rules, max_iters=100) -> Value?:
  db.set("Demand", [env_id, expr_id], IntVal(1))
  let processed = HashSet::new()
  for _ in 0..<max_iters:
    db.run_schedule(Saturate(Run(rules), 10))
    if !evaluation_bridge(db, processed): break
  db.lookup("Eval", [env_id, expr_id])
```

## Partial Evaluation Semantics

Holes, errors, and unbound nodes are seeded as sentinel constructors but no
Demand/Eval rules match them. Evaluation naturally stops:

- **If with hole:** `If(Num(1), Num(42), HoleNode(0))` → condition evaluates,
  bridge selects then-branch, hole in else never demanded. Result: `ValInt(42)`.
- **Add with hole:** `Add(Num(2), HoleNode(0))` → both operands demanded,
  Num(2) evaluates, HoleNode has no Eval, AddReady never fires. Num(2) is
  partially evaluated but the Add itself has no result.
- **Let with hole value:** `Let(x, HoleNode(0), body)` → value demanded but
  never evaluates, LetReady never fires, body never demanded.

## File Structure

```
examples/lambda-eval/
├── moon.pkg           # imports @egglog and @lambda
├── eval.mbt           # lambda_eval_db(), eval_rules(), evaluation_bridge(),
│                      #   run_eval(), create_eval_env(), ValueEnv, helpers
└── eval_test.mbt      # 20+ blackbox tests
```

## Tasks

### Task 0: Rename InEnv → TypeEnv

Rename in `examples/lambda/lambda.mbt` and `examples/lambda/lambda_test.mbt`.
~22 occurrences (12 in lambda.mbt, 10 in lambda_test.mbt). Verify no other
packages depend on the `InEnv` table name (check `stlc` example). Run existing
tests to verify no breakage.

### Task 1: Schema + leaf evaluation

- Create package, `lambda_eval_db()`, all 17 rules, bridge stub, `run_eval()`
- Tests: Num→ValInt, Unit→ValUnit

### Task 2: Arithmetic (bridge: Add/Minus)

- Bridge handles AddReady, MinusReady
- Tests: 2+3=5, 10-3=7, (2+3)-1=4, add-non-integer error

### Task 3: If branches (bridge: If)

- Bridge handles IfReady
- Tests: if-truthy→then, if-falsy→else, non-integer-condition error

### Task 4: App + Let (bridge: App/Let + create_eval_env)

- Bridge handles AppReady, LetReady via `ValueEnv` + `create_eval_env`
- Tests: (λx.x+1)5=6, let x=2 in x+x=4, nested lets,
  curried (λx.λy.x+y)2 3=5, closure captures env

### Task 5: Partial evaluation + limits

- Tests: If-with-hole, Add-with-hole, fact count limit,
  apply-int-as-function error

### Task 6: Composition + polish

- Run typing + eval rules in same Database. Concrete test: type `(λx. x+1)`
  as `Int → Int` while evaluating `(λx. x+1) 5` to `6` in one Database.
  Verify TypeEnv/ValEnv separation (no cross-contamination).
- `moon info && moon fmt`, interface review

## Acceptance Criteria

- [ ] `examples/lambda-eval/` package exists and builds
- [ ] 17 Datalog rules + bridge implement full evaluation
- [ ] Arithmetic: `2+3 → 5`, `10-3 → 7`
- [ ] Beta reduction: `(λx. x+1) 5 → 6`, `(λx. λy. x+y) 2 3 → 5`
- [ ] Let bindings: `let x=2 in x+x → 4`, nested lets
- [ ] Conditionals: `if 1 then 2 else 3 → 2`, `if 0 then 2 else 3 → 3`
- [ ] Partial evaluation: If-with-hole evaluates taken branch only
- [ ] Sentinel nodes: Hole/Error/Unbound block evaluation cascade
- [ ] Runtime type errors: apply-int-as-function → EvalError
- [ ] Fact count limit stops evaluation
- [ ] Composition: typing + eval in same DB, separate TypeEnv/ValEnv
- [ ] Bridge processed-set prevents infinite re-processing
- [ ] `cd loom/egglog && moon test` passes (all packages)
- [ ] `moon check` passes

## Validation

```bash
cd loom/egglog && moon check
cd loom/egglog && moon test
cd loom/egglog && moon info && moon fmt
```

## Risks

- **4-way joins in trigger rules** (e.g., trigger-add has 4 Fact atoms).
  Semi-naive creates 4 variants per rule. Acceptable for Phase 1 example sizes.
- **`ValueEnv` must stay in sync with ValEnv facts.** The host-side binding
  map avoids scanning, but if bridge logic creates envs without going through
  `ValueEnv`, the two will diverge. All env creation must use the helper.
- **Bridge + Datalog interleaving** is a MoonBit loop, not a Schedule.
  Current Schedule API doesn't support interleaving callbacks.

## Notes

- Design spec: `docs/plans/2026-04-02-lambda-evaluator-design.md`
- Phase 0 (done): egglog PR #5 — `Database::scan`, `Database::row_count`
- Phase 2 (done): loom PR #69 — direct evaluator
- Related: egglog engine extensions (memory: `project_egglog_engine_extensions.md`)
