# Lambda Evaluator Design

## Why

Canopy has a lambda calculus language with incremental parsing, projection, and
structural editing — but no way to evaluate programs. Two proof-of-concept
evaluators exist in isolation:

- **egraph** (`loom/egraph/lambda_eval_wbtest.mbt`): beta reduction + constant
  folding via equality saturation, 14 tests, not integrated with `Term` AST
- **egglog** (`loom/egglog/examples/lambda/`): type inference via Datalog rules,
  not evaluation

Neither is usable from the editor. This design combines traditional evaluation,
egglog relational evaluation, and egraph optimization into a unified three-tier
architecture that fits Canopy's incremental/reactive/CRDT foundations.

## Scope

In:
- `loom/egglog/src/` — small API additions: `scan`, `row_count` (Phase 0)
- `loom/egglog/examples/lambda-eval/` — new egglog evaluation example (Phase 1)
- `loom/examples/lambda/src/eval/` — direct evaluator package (Phase 2)
- `lang/lambda/eval/` — editor integration, escalation wiring (Phase 3)
- `loom/egraph/` — optimizer promotion (Phase 4, future)

Out:
- Editor UI for displaying evaluation results (deferred)
- Step-by-step reduction visualization (deferred)
- Live inline evaluation annotations (deferred)
- Changes to the `Term` AST or parser grammar

## Current State

### Lambda Language (`Term` enum)
`loom/examples/lambda/src/ast/ast.mbt`:
```
Int(Int) | Var(VarName) | Lam(VarName, Term) | App(Term, Term)
| Bop(Bop, Term, Term) | If(Term, Term, Term)
| Module(Array[(VarName, Term)], Term) | Unit
| Unbound(VarName) | Error(String) | Hole(Int)
```
Binary operators: `Plus`, `Minus`.

### Existing EGraph PoC (`loom/egraph/lambda_eval_wbtest.mbt`)
- Separate `LambdaLang` enum (not `Term`) with extended nodes: `LBool`,
  `LIsZero`, `LMul`, `LSubst`
- `AnalyzedEGraph` with free-variable tracking + constant folding analyses
- Reduction via `modify` hook during `rebuild()`
- Capture-safe substitution
- 14 passing tests

### Existing Egglog Typing (`loom/egglog/examples/lambda/`)
- `HasType(env, expr, type)` relation with bidirectional checking
- Reified environments: `EmptyEnv()`, `ExtendEnv(parent, name, type)`
- `InEnv(env, name, type)` for variable lookup
- `Typing(env, expr)` propagation facts for top-down flow
- `LambdaEnv` helper struct for transitive scope seeding

### Reactive Infrastructure (`loom/incr/`)
- `Signal[T]` (input cells) + `Memo[T]` (derived cells) with backdating
- `Runtime` with pull (Memo), push (Reactive), and datalog (Relations) in one
  system
- Semi-naive `FunctionalRelation` for Datalog delta processing
- `Database` trait pattern for abstracting Runtime access

## Desired State

A three-tier evaluator where:

1. Simple expressions evaluate instantly via direct recursion (Tier 1)
2. Complex/partial programs evaluate via egglog relational rules (Tier 2)
3. Algebraic optimization is available on-demand via egraph saturation (Tier 3)

All tiers share the `incr` Runtime substrate, support incremental re-evaluation,
and are CRDT-compatible (deterministic or monotonic/confluent).

## Architecture

### Tier 1: Direct Evaluator

Fast-path recursive evaluation on `Term`:

```
eval(env, Int(n))           → VInt(n)
eval(env, Var(x))           → env.lookup(x) ?? Stuck(Unbound(x))
eval(env, Lam(x, body))     → VClosure(env, x, body)
eval(env, App(f, arg))      → apply(eval(env, f), eval(env, arg))
eval(env, Bop(op, a, b))    → eval_bop(op, eval(env, a), eval(env, b))
eval(env, If(c, t, e))      → if eval(env, c) != VInt(0) then eval(env, t)
                               else eval(env, e)
eval(env, Module(defs, body))→ eval(extend_all(env, defs), body)
eval(env, Hole(_))           → Stuck(Incomplete)
eval(env, Error(_))          → Stuck(ParseError)
eval(env, Unbound(x))        → Stuck(Unbound(x))
eval(env, Unit)              → VUnit
```

Value domain (matching what `Term` can express today):

```moonbit
enum Value {
  VInt(Int)
  VClosure(Env, VarName, Term)
  VUnit
}

type! StuckReason {
  Unbound(VarName)
  TypeMismatch(String)     // e.g., applying a non-function
  Incomplete               // hole encountered
  ParseError               // error node encountered
  Divergence               // fuel exhausted
}

// Use Result[Value, StuckReason] directly — idiomatic MoonBit, no custom enum
fn eval(env : Env, term : Term, fuel~ : Int) -> Value!StuckReason
```

Fuel limit (~1000 steps) prevents divergence. No `Bool` type — `If` tests
against zero/non-zero (C-style: `0` is falsy, any other `Int` is truthy),
matching the current parser grammar which has no boolean literals.

### Tier 2: Egglog Knowledge Base (Datalog + Bridge)

Tier 2 uses a **hybrid architecture**: pure Datalog rules handle demand
propagation, leaf resolution, and trigger detection; a **MoonBit bridge
function** handles arithmetic computation, branch selection, dynamic
environment creation, and `InValEnv` seeding.

This split follows a first principle: **use each system for what it's good at.**
Datalog excels at monotonic fact derivation and joins. MoonBit excels at
conditional logic and imperative environment manipulation. The current egglog
engine lacks inequality constraints (`NotEqual`) and can't call MoonBit
functions from rule actions, making pure-Datalog evaluation infeasible today.
A future engine extension plan (see Notes) would enable fully declarative rules.

#### Execution Model

A MoonBit loop alternating between Datalog saturation and the bridge:

```
seed Demand(root_env, root_expr)
loop (max 100 iterations):
  ① db.run_schedule(Saturate(Run(eval_rules), 10))  -- Datalog
  ② let changed = evaluation_bridge(db)              -- MoonBit
  if !changed: break
query db.lookup("Eval", [root_env, root_expr])
```

This is a MoonBit loop, not a `Schedule` — the current Schedule API doesn't
support interleaving MoonBit callbacks. Each iteration: Datalog derives what it
can, bridge handles what Datalog can't, repeat until fixpoint.

#### Schema

```
-- Evaluation tables (new)
Demand(env, expr)            → IntVal(1)      // demand trigger (like Typing)
Eval(env, expr)              → value_id       // evaluation result
InValEnv(env, name)          → value_id       // value environment (separate from InEnv)
Closure(env, x, body)        → id             // closure value constructor
ValInt(IntVal(n))            → id             // integer value
ValUnit()                    → id             // unit value

-- Trigger tables (written by Datalog, read by bridge)
AddReady(env, expr)          → IntVal(1)      // both operands evaluated, compute needed
MinusReady(env, expr)        → IntVal(1)      // both operands evaluated, compute needed
IfReady(env, expr)           → IntVal(1)      // condition evaluated, branch needed
AppReady(env, expr)          → IntVal(1)      // function + arg evaluated, env needed
LetReady(env, expr)          → IntVal(1)      // binding evaluated, env needed
EvalError(env, expr)         → StrVal(msg)    // runtime type error (written by bridge)

-- Bridge metadata tables (written by bridge, read by Datalog)
IfBranch(env, expr)          → branch_expr_id // which branch was selected
AppBodyEnv(env, expr)        → ext_env_id     // extended env for closure body
AppBody(env, expr)           → body_expr_id   // closure body expression
LetBodyEnv(env, expr)        → ext_env_id     // extended env for let body
LetBody(env, expr)           → body_expr_id   // let body expression

-- Sentinel constructors (seeded, but no Eval rules match them)
HoleNode(IntVal(id))         → id             // placeholder — blocks evaluation
ErrorNode(StrVal(msg))       → id             // parse error — blocks evaluation
UnboundNode(StrVal(name))    → id             // unresolved name — blocks evaluation
Unit()                       → id             // unit expression (does have Eval rule)

-- Reused from typing example (read-only by evaluator)
EmptyEnv, ExtendEnv, Num, Var, Lam, App, Add, Minus, Let, If
BoolLit, IsZero, BoolTy      // forward-compatible, eval rules added
```

**Key design decisions in the schema:**

**`InValEnv` vs `InEnv`:** The typing example stores *types* in
`InEnv(env, name) → type_id`. Evaluation stores *values* in
`InValEnv(env, name) → value_id`. These MUST be separate tables — merging
a type_id and value_id into the same e-class would be semantically wrong.
Both coexist in one Database, reading from different tables. The `EmptyEnv`
and `ExtendEnv` constructors are shared, but evaluation and typing create
*different* `ExtendEnv` instances (different payloads).

**`Demand` as explicit table:** Registered as a functional table
`Demand(env, expr) → IntVal(1)`, same pattern as the typing example's
`Typing(env, expr)` trigger. Must be registered in `lambda_eval_db()`.

**Operator naming:** `Term`'s `Bop(Plus, a, b)` maps to egglog `Add(a, b)`,
`Bop(Minus, a, b)` maps to `Minus(a, b)` — matching the existing typing
schema. Mapping performed during `seed_database()`.

**Bool/IsZero forward-compatibility:** The evaluation example reuses the typing
example's `BoolLit`, `IsZero`, `BoolTy` tables and adds evaluation rules for
them, even though the parser doesn't produce booleans yet. This keeps schemas
aligned for composition. Tier 1 does NOT add Bool — only handles what `Term`
can express.

**`Hole`/`Error`/`Unbound` handling:** These nodes ARE seeded as explicit
constructor tables (`HoleNode(id)`, `ErrorNode(msg, id)`, `UnboundNode(name, id)`)
so that parent nodes can reference their child IDs. However, **no Demand or
Eval rules match these constructors** — no `Eval` fact is ever derived for them.
This means parent expressions that reference holes have all children present
in the graph, but the Demand propagation naturally stops: `demand-add` fires
and demands both operands, but if one operand is a `HoleNode`, no rule resolves
it, so no `Eval` fact appears, and the parent's `AddReady` trigger never fires.
Sibling subexpressions that don't depend on the hole evaluate normally. This
cascade of "no Eval derivable" IS the partial evaluation behavior.

#### Pure Datalog Rules

Every rule below maps directly to `Rule { query: Array[Atom], actions: Array[Action] }`
using only `Fact` and `Equal` atoms — no inequality, no side effects.

**Demand propagation (top-down):**
```
demand-app:      Demand(env, e), App(f, arg, e)       ⟹ Demand(env, f), Demand(env, arg)
demand-add:      Demand(env, e), Add(a, b, e)         ⟹ Demand(env, a), Demand(env, b)
demand-minus:    Demand(env, e), Minus(a, b, e)       ⟹ Demand(env, a), Demand(env, b)
demand-if-cond:  Demand(env, e), If(c, t, el, e)      ⟹ Demand(env, c)
demand-let-val:  Demand(env, e), Let(x, val, body, e) ⟹ Demand(env, val)
```

Note: `demand-if-cond` only demands the condition, NOT both branches. The
bridge selects which branch to demand after the condition evaluates.

**Leaf resolution (bottom-up):**
```
resolve-num:  Demand(env, e), Num(n, e)                         ⟹ Eval(env, e) = ValInt(n)
resolve-var:  Demand(env, e), Var(x, e), InValEnv(env, x, v)   ⟹ Eval(env, e) = v
resolve-lam:  Demand(env, e), Lam(x, body, e)                  ⟹ Eval(env, e) = Closure(env, x, body)
resolve-unit: Demand(env, e), Unit(e)                            ⟹ Eval(env, e) = ValUnit()
```

Note: `resolve-var` reads from `InValEnv` (values), not `InEnv` (types).

**Trigger detection (Datalog finds "ready" states, bridge acts on them):**

Arithmetic, conditionals, application, and let all produce triggers that the
bridge processes. This is because the current egglog `Action` enum (`Set`,
`Union`, `LetAction`) cannot compute arithmetic (`na + nb`) or call MoonBit
functions. All computation beyond simple fact storage is delegated to the bridge.

```
trigger-add: Demand(env, e), Add(a, b, e),
             Eval(env, a, va), Eval(env, b, vb)
             ⟹ AddReady(env, e) = IntVal(1)

trigger-minus: Demand(env, e), Minus(a, b, e),
               Eval(env, a, va), Eval(env, b, vb)
               ⟹ MinusReady(env, e) = IntVal(1)

trigger-if:  Demand(env, e), If(c, t, el, e), Eval(env, c, vc)
             ⟹ IfReady(env, e) = IntVal(1)

trigger-app: Demand(env, e), App(f, arg, e),
             Eval(env, f, clos), Eval(env, arg, v)
             ⟹ AppReady(env, e) = IntVal(1)

trigger-let: Demand(env, e), Let(x, val, body, e),
             Eval(env, val, v)
             ⟹ LetReady(env, e) = IntVal(1)
```

**Result propagation (using bridge-stored metadata):**
```
resolve-if:  IfBranch(env, e, branch), Eval(env, branch, result)
             ⟹ Eval(env, e) = result

resolve-app: AppBodyEnv(env, e, ext), AppBody(env, e, body),
             Eval(ext, body, result)
             ⟹ Eval(env, e) = result

resolve-let: LetBodyEnv(env, e, ext), LetBody(env, e, body),
             Eval(ext, body, result)
             ⟹ Eval(env, e) = result
```

#### MoonBit Bridge Function

The bridge handles operations that pure Datalog can't express: arithmetic
computation (egglog actions can't compute `na + nb`), branch selection (needs
inequality), environment creation (needs imperative `InValEnv` seeding), and
value-shape guards (detecting runtime type errors).

**Required egglog API extensions (Phase 0):** The bridge needs APIs that
don't exist publicly on `Database` today:

1. **`Database::scan(table_name) -> Array[(Array[Value], Value)]`** — iterate
   all rows in a table. Currently private (`FunctionTable::scan`). Must be
   made public.
2. **`Database::row_count(table_name) -> Int`** — for fact count limits.
   Currently not exposed.

These are small, backward-compatible API additions to `loom/egglog/src/`.
Phase 1 adds them before implementing the evaluator example.

The bridge maintains a **`processed` set** tracking `(env, expr)` pairs it
has already handled, preventing infinite re-processing of the same triggers.
Only genuinely new triggers (from the latest Datalog round) produce new facts.

```moonbit
fn evaluation_bridge(db : Database, processed : HashSet[(Value, Value)]) -> Bool {
  let new_facts = false

  // 0. Check fact count limit
  if db.row_count("Eval") > 10000 { return false }

  // 1. Arithmetic (Add)
  for (env, e) in scan_triggers(db, "AddReady", processed) {
    let (a, b) = lookup_add_children(db, e)
    let va = db.lookup("Eval", [env, a]).unwrap()
    let vb = db.lookup("Eval", [env, b]).unwrap()
    match (extract_int(db, va), extract_int(db, vb)) {
      (Some(na), Some(nb)) => {
        let result = db.call("ValInt", [IntVal(na + nb)])
        db.set("Eval", [env, e], result)
        new_facts = true
      }
      _ => db.set("EvalError", [env, e], StrVal("add: non-integer operand"))
    }
  }

  // 2. Arithmetic (Minus) — same pattern as Add
  for (env, e) in scan_triggers(db, "MinusReady", processed) {
    let (a, b) = lookup_minus_children(db, e)
    let va = db.lookup("Eval", [env, a]).unwrap()
    let vb = db.lookup("Eval", [env, b]).unwrap()
    match (extract_int(db, va), extract_int(db, vb)) {
      (Some(na), Some(nb)) => {
        let result = db.call("ValInt", [IntVal(na - nb)])
        db.set("Eval", [env, e], result)
        new_facts = true
      }
      _ => db.set("EvalError", [env, e], StrVal("minus: non-integer operand"))
    }
  }

  // 3. Branch selection for If nodes
  for (env, e) in scan_triggers(db, "IfReady", processed) {
    let (c, t, el) = lookup_if_children(db, e)
    let cond_val = db.lookup("Eval", [env, c]).unwrap()
    match extract_int(db, cond_val) {
      Some(n) => {
        let branch = if n == 0 { el } else { t }
        db.set("IfBranch", [env, e], branch)
        db.set("Demand", [env, branch], IntVal(1))
        new_facts = true
      }
      None => {
        // Condition evaluated to non-integer (e.g., closure) — type error
        db.set("EvalError", [env, e], StrVal("if: non-integer condition"))
      }
    }
  }

  // 4. Environment creation for App (closure application)
  for (env, e) in scan_triggers(db, "AppReady", processed) {
    let (f, arg) = lookup_app_children(db, e)
    let func_val = db.lookup("Eval", [env, f]).unwrap()
    match extract_closure(db, func_val) {
      Some((cenv, x, body)) => {
        let arg_val = db.lookup("Eval", [env, arg]).unwrap()
        let ext = create_eval_env(db, cenv, x, arg_val)
        db.set("AppBodyEnv", [env, e], ext)
        db.set("AppBody", [env, e], body)
        db.set("Demand", [ext, body], IntVal(1))
        new_facts = true
      }
      None => {
        // Function evaluated to non-closure (e.g., integer) — type error
        db.set("EvalError", [env, e], StrVal("app: non-function application"))
      }
    }
  }

  // 5. Environment creation for Let
  for (env, e) in scan_triggers(db, "LetReady", processed) {
    let (x, val, body) = lookup_let_children(db, e)
    let v = db.lookup("Eval", [env, val]).unwrap()
    let ext = create_eval_env(db, env, x, v)
    db.set("LetBodyEnv", [env, e], ext)
    db.set("LetBody", [env, e], body)
    db.set("Demand", [ext, body], IntVal(1))
    new_facts = true
  }

  db.rebuild()
  new_facts
}

// Helper: scan a trigger table, skip already-processed entries
fn scan_triggers(
  db : Database, table : String, processed : HashSet[(Value, Value)],
) -> Array[(Value, Value)] {
  let results = []
  for (keys, _) in db.scan(table) {
    let pair = (keys[0], keys[1])  // (env, expr)
    if !processed.contains(pair) {
      processed.add(pair)
      results.push(pair)
    }
  }
  results
}
```

**`create_eval_env`** is the evaluation counterpart of `LambdaEnv::extend()`.
It creates `ExtendEnv(parent, x, v)` and transitively seeds `InValEnv` for
all visible bindings, handling shadowing (skip if name equals the new binding).
Pure MoonBit, no Datalog inequality needed.

```moonbit
fn create_eval_env(
  db : Database, parent_env : Value, x : String, v : Value,
) -> Value {
  let ext = db.call("ExtendEnv", [parent_env, StrVal(x), v])
  // Seed the new binding
  db.set("InValEnv", [ext, StrVal(x)], v)
  // Propagate parent bindings (with shadowing)
  for (name, val) in get_visible_bindings(db, parent_env) {
    if name != x {
      db.set("InValEnv", [ext, StrVal(name)], val)
    }
  }
  ext
}
```

#### Module Handling

`Module(defs, body)` is desugared to nested `Let` during the `Term` → egglog
seeding phase (in `seed_database()`, not in Datalog rules):

```
Module([(x, e1), (y, e2)], body)  →  Let(x, e1, Let(y, e2, body))
```

Definitions are evaluated sequentially: earlier bindings are visible to later
ones. This matches Tier 1's `extend_all` behavior. Tier 2 only sees `Let`.

#### Partial Evaluation

`Hole`, `Error`, and `Unbound` nodes are seeded as sentinel constructors
(`HoleNode`, `ErrorNode`, `UnboundNode`) so parent nodes can reference their
IDs. But no Demand or Eval rules match these sentinels, so evaluation
naturally stops at them. Demand propagation flows around holes: in
`let x = 2 in let y = _ in x + 1`, binding `x = 2` evaluates and `x + 1`
evaluates (since `y` is a `HoleNode` that blocks its own `Eval` but doesn't
block sibling subexpressions). This is the key advantage over Tier 1.

#### Composition with Typing

Typing uses `InEnv` (types), evaluation uses `InValEnv` (values). Both coexist
in one Database. A future `TypedEval` outer loop can run both rule sets:

```moonbit
loop {
  db.run_schedule(Saturate(Run(typing_rules ++ eval_rules), 10))
  let changed = evaluation_bridge(db)
  if !changed { break }
}
// Now query both: HasType(env, expr) and Eval(env, expr)
```

This enables type-directed error messages: "expression evaluated to `5` but
has type `Bool`."

### Tier 3: EGraph Optimizer (Future)

Seeds an `EGraph[LambdaLang]` with equivalences derived by egglog:
- `Eval(env, Add(Num(2), Num(3)), ValInt(5))` → `union(Add(2,3), 5)`
- Apply algebraic rewrites (commutativity, constant propagation, dead code)
- `extract(root, ast_size)` returns the cheapest equivalent form

**Tier 3 should use explicit substitution (egg-style), not environments.** This
is the proven approach from egg's `lambda.rs`: beta reduction creates `let`
nodes, substitution is pushed down via local rewrite rules, and capture
avoidance uses e-class analysis tracking free variables. This differs from
Tier 2's environment-based approach — the bridge between them (Phase 4) must
translate between representations. See: egg POPL 2021 paper, Panchekha's
"Binding in E-graphs" analysis.

Future direction: **Slotted E-Graphs** (PLDI 2025) parameterize e-classes by
"slots" abstracting over free variables, making alpha-equivalence structural.
This would simplify Tier 3's binding handling significantly.

Not implemented in Phase 1-2. Existing `loom/egraph/` infrastructure is ready
when needed.

### Escalation Protocol

```
User edit → incr Signal invalidation
  → Tier 1: Memo[Value!StuckReason] recomputes per definition (μs)
    ├── Ok(value) → display immediately
    └── Err(stuck) → collect into escalation batch
                         ↓
  → Tier 2: batch all Stuck expressions into one egglog Database (ms)
    ├── Seed all Stuck expressions + environments in one Database
    ├── Seed Demand for each root expression
    ├── Run Datalog + Bridge loop until fixpoint
    ├── Query Eval(env, expr) for each originally-stuck expression
    ├── found → display value
    └── not found → display "?" or partial result
```

**Batch escalation is critical for performance.** If a module has 10 bindings
and 5 return `Stuck`, we seed all 5 into one Database and run the
Datalog+Bridge loop once. Shared subexpressions and environments are computed
once. This avoids the N × ms trap of N separate fixpoints.

Escalation granularity is per-invalidation-cycle, not per-expression. Within
one reactive update (one user edit), all `Stuck` results are collected, batched,
and resolved together.

### incr Integration (Phase 3)

```moonbit
// Tier 1: per top-level definition, instant
fn create_eval_memo(rt : Runtime, term_memo : Memo[Term]) -> Memo[Value!StuckReason] {
  Memo::new(rt, fn() {
    let term = term_memo.get()
    eval_direct(Env::empty(), term, fuel=1000)  // Tier 1
  })
}

// Tier 2: batch escalation — one Database + Bridge loop for all stuck expressions
fn create_batch_egglog_eval(
  rt : Runtime,
  eval_memos : Array[Memo[Value!StuckReason]],
  term_memos : Array[Memo[Term]],
) -> Memo[Map[Int, Value]] {
  Memo::new(rt, fn() {
    // Collect all stuck expressions from Tier 1
    let stuck = []
    for i, memo in eval_memos {
      match memo.get() {
        Err(_) => stuck.push((i, term_memos[i].get()))
        Ok(_) => ()
      }
    }
    if stuck.is_empty() { return Map::new() }

    // Seed all stuck expressions into one Database
    let db = lambda_eval_db()
    let roots = []
    for (i, term) in stuck {
      let (env, expr_id) = seed_term(db, term)  // Module desugared to Let
      db.set("Demand", [env, expr_id], IntVal(1))
      roots.push((i, env, expr_id))
    }

    // Datalog + Bridge loop until fixpoint
    for _ in 0..<100 {
      db.run_schedule(Saturate(Run(eval_rules), 10))
      let changed = evaluation_bridge(db)
      if !changed { break }
    }

    // Query results
    let results = Map::new()
    for (i, env, expr_id) in roots {
      match db.lookup("Eval", [env, expr_id]) {
        Some(val) => results.set(i, egglog_val_to_value(db, val))
        None => ()  // remains unresolved
      }
    }
    results
  })
}
```

## Phases

### Execution Order

The phases below are numbered by architectural dependency, but **executed in
pragmatic order**: Phase 2 first, then Phase 0 + 1, then Phase 3.

| Order | Phase | Rationale |
|-------|-------|-----------|
| **1st** | Phase 2 (direct evaluator) | ~50-80 lines, immediately useful, zero infrastructure changes |
| **2nd** | Phase 0 (egglog API) | Prerequisite for Phase 1, small and low-risk |
| **3rd** | Phase 1 (egglog evaluator) | Research exploration — validates relational model |
| **4th** | Phase 3 (editor integration) | Wire Tier 1 immediately; add Tier 2 escalation when proven |
| later | Phase 4 (egraph optimizer) | Future, on-demand |

Phase 2 ships a working evaluator. Phases 0+1 are a bet that pays off when
the language grows toward partial evaluation, type inference composition, or
multi-language support. Phase 3 can start with Tier 1 only and add Tier 2
escalation later.

### Phase 0: Egglog API Extensions
**Location:** `loom/egglog/src/`

Small, backward-compatible additions to the egglog Database public API:
1. `Database::scan(table_name) -> Array[(Array[Value], Value)]` — expose
   `FunctionTable::scan` publicly for bridge table iteration
2. `Database::row_count(table_name) -> Int` — expose fact count for limits
3. Tests verifying the new APIs don't break existing examples

**Depends on:** nothing. Prerequisite for Phase 1.

### Phase 1: Egglog Evaluation Example
**Location:** `loom/egglog/examples/lambda-eval/`

Create a standalone egglog example demonstrating relational evaluation with
the Datalog + Bridge hybrid architecture:
1. Define evaluation schema (Demand, Eval, InValEnv, Closure, ValInt, ValUnit,
   HoleNode, ErrorNode, UnboundNode, Unit, trigger tables, bridge metadata
   tables, EvalError)
2. Implement pure Datalog rules (~12 rules: demand, leaf, trigger, resolve)
3. Implement `evaluation_bridge()` function with processed-trigger tracking,
   arithmetic computation, branch selection, env creation, InValEnv seeding,
   and value-shape guards for runtime type errors
4. Implement `create_eval_env()` (evaluation counterpart of `LambdaEnv::extend`)
5. Implement `seed_database()` with `Module` → nested `Let` desugaring and
   `Hole`/`Error`/`Unbound` → sentinel constructors
6. Write tests: arithmetic, beta reduction, let-bindings, partial evaluation,
   `if` branching, nested closures, runtime type errors (applying int as
   function, non-integer if condition), fact count limit
7. Demonstrate composition: run typing + evaluation rules in same database

**Depends on:** Phase 0 (egglog API extensions), existing lambda typing example.

### Phase 2: Direct Evaluator
**Location:** `loom/examples/lambda/src/eval/`

Create a traditional tree-walking evaluator:
1. Define `Value`, `StuckReason`, `Env` types
2. Implement `fn eval(env : Env, term : Term, fuel~ : Int) -> Value!StuckReason`
3. Handle all `Term` variants including `Module` (sequential), `Hole`, `Error`,
   `Unbound`, `Unit`
4. Write tests mirroring the egglog example (same inputs, same outputs)
5. Round-trip test: Tier 1 and Tier 2 must agree on all complete programs
6. Benchmark against egglog for simple expressions

**Depends on:** `Term` AST (`loom/examples/lambda/src/ast/`).

### Phase 3: Editor Integration
**Location:** `lang/lambda/eval/`

Wire evaluators into the incr reactive graph:
1. Create `Memo[EvalResult]` per top-level definition (Tier 1)
2. Create escalation path to egglog (Tier 2)
3. Expose evaluation results via `SyncEditor` or `EditorProtocol`
4. Incremental: only re-evaluate definitions whose `Term` changed

**Depends on:** Phase 1, Phase 2, `incr` Runtime, `lang/lambda/` projection.

### Phase 4: EGraph Optimizer (Future)
**Location:** `loom/egraph/`

Promote egraph PoC to production:
1. Bridge egglog `Eval` facts → egraph equivalence classes
2. Add algebraic rewrite rules (commutativity, distribution, etc.)
3. Cost-driven extraction for "simplify this expression"
4. On-demand trigger, not always-on

**Depends on:** Phase 1, existing egraph infrastructure.

## Acceptance Criteria

### Phase 0
- [ ] `Database::scan(table_name)` returns all rows in a table
- [ ] `Database::row_count(table_name)` returns fact count
- [ ] Existing egglog tests still pass (`cd loom/egglog && moon test`)
- [ ] `moon check` passes

### Phase 1
- [ ] `loom/egglog/examples/lambda-eval/` package exists and builds
- [ ] Pure Datalog rules + bridge function implement full evaluation
- [ ] Arithmetic: `2+3 → 5`, `10-3 → 7`
- [ ] Beta reduction: `((x) => x+1) 5 → 6`, `((x, y) => x+y) 2 3 → 5`
- [ ] Let bindings: `let x=2 in x+x → 4`, nested `let x=1 in let y=2 in x+y → 3`
- [ ] Conditionals: `if 1 then 2 else 3 → 2`, `if 0 then 2 else 3 → 3`
- [ ] Module desugared to nested Let during seeding
- [ ] Partial evaluation: expression with hole evaluates non-hole parts
- [ ] Hole/Error/Unbound: seeded as sentinel nodes, no Eval derived, cascade correct
- [ ] Runtime type errors: applying int as function → EvalError, non-int if → EvalError
- [ ] Bridge processed-set prevents infinite re-processing of same triggers
- [ ] Fact count limit stops evaluation for deeply recursive programs
- [ ] Composition test: typing + evaluation rules in same database, separate
      `InEnv`/`InValEnv` tables, no cross-contamination
- [ ] `cd loom/egglog && moon test` passes

### Phase 2
- [ ] `loom/examples/lambda/src/eval/` package exists and builds
- [ ] `eval(env, term, fuel~) -> Value!StuckReason` handles all `Term` variants
- [ ] Fuel limit prevents infinite loops (`((x) => x x)((x) => x x)` → `Divergence`)
- [ ] `Hole` → `Incomplete`, `Error` → `ParseError`, `Unbound` → `Unbound(name)`
- [ ] Round-trip: Tier 1 and Tier 2 agree on all complete programs
- [ ] `cd loom/examples/lambda && moon test` passes

### Phase 3
- [ ] `Memo[EvalResult]` wired into editor reactive graph
- [ ] Tier 1 → Tier 2 batch escalation works for incomplete programs
- [ ] Re-editing one binding only re-evaluates dependents
- [ ] Type-directed error: running typing + eval rules together catches
      runtime type mismatches (e.g., applying an integer as a function)
- [ ] `moon test` passes in main module

### Phase 4
- [ ] Egraph seeded from egglog Eval facts
- [ ] `extract()` returns simplified expressions
- [ ] Benchmark shows optimization wins on non-trivial programs

## Validation

```bash
# Phase 0
cd loom/egglog && moon test && moon check

# Phase 1
cd loom/egglog && moon test
cd loom/egglog && moon check

# Phase 2
cd loom/examples/lambda && moon test

# Phase 3
moon test
moon check

# All phases
moon info && moon fmt
```

## Risks

- **Egglog performance for large programs:** Semi-naive evaluation has overhead.
  Mitigated by Tier 1 handling the common fast path; Tier 2 only sees
  escalated expressions.
- **Higher-order functions in first-order Datalog:** Closures must be reified as
  data nodes. Programs creating many closures may cause fact explosion.
  Mitigated by outer loop iteration limit (100) and a **fact count limit**
  (configurable, default ~10K) — inspired by egg's `Runner` node limit.
  The bridge checks total fact count each iteration and stops early if
  exceeded.
- **Bridge scan overhead:** The bridge scans trigger tables each iteration.
  For Phase 1, a MoonBit `processed` set suffices. For Phase 3, delta
  tracking from `FunctionalRelation` is more efficient.
- **Eval table conflicts:** `Eval` is a functional table. If two rules produce
  different `IdVal` outputs, egglog unions them (correct). If they produce
  different primitive `IntVal` outputs, egglog aborts (bug). Mitigate: this
  should never happen for a deterministic evaluator. Add an assertion test.
- **Divergence:** `((x) => x x)((x) => x x)` in Tier 1 is caught by fuel limit. In
  Tier 2, the outer loop iteration limit (100) catches it. The bridge keeps
  seeding new `Demand` facts for recursive applications until the limit.
- **Divergence escalation is futile:** If Tier 1 hits its fuel limit, Tier 2
  will hit its loop limit for the same expression. Accept: divergence produces
  `Stuck(Divergence)` at both tiers.
- **Two-representation tax:** Converting `Term` ↔ egglog facts is a surface for
  bugs. Mitigate with round-trip tests (Tier 1 and Tier 2 must agree on all
  complete programs).
- **Environment serialization on escalation:** The entire scope must be seeded
  as egglog facts. Mitigated by batch mode (shared environments) and shallow
  scope depth in practice.
- **Egglog API surface expansion (Phase 0):** Adding `scan` and `row_count`
  to `Database` exposes internal table iteration. Risk: performance if tables
  are large. Mitigated: bridge only scans trigger tables (small) and the fact
  count check is O(1). These are read-only additions — no mutation semantics
  change.

## Incremental Compiler Context

This evaluator is Phase 3 of Canopy's emerging incremental compiler:

| Phase | Status | Substrate |
|---|---|---|
| Incremental lexing | Done | incr Memo (loom) |
| Incremental parsing | Done | incr Memo (loom) |
| Incremental projection | Done | incr Memo + BackdateEq |
| **Incremental evaluation** | **This design** | incr Memo + Datalog |
| Incremental type checking | Example exists | Datalog (egglog) |
| Incremental optimization | PoC exists | EGraph |
| Incremental codegen | Future | incr Memo |

The evaluator validates the egglog knowledge-base model for production use
alongside the existing incr/Memo model. If successful, the same architecture
extends to type checking, optimization, and eventually code generation — all
as rules and facts in one reactive Runtime.

## Notes

- **Value domain:** Intentionally matches only what `Term` can express today
  (Int, Closure, Unit). Tier 2 schema includes Bool/IsZero for forward
  compatibility, but Tier 1 does not.
- **Datalog + Bridge is a pragmatic choice**, not the ideal architecture. The
  current egglog engine lacks `:when` guards (conditional rule firing) and
  can't call MoonBit from rule actions. The bridge does exactly what `:when`
  guards do in the real Rust egglog — this is a proven pattern (Herbie,
  eggcc). A separate future plan covers engine extensions, prioritizing
  `:when` guards over raw `NotEqual` (matches real egglog's approach). See
  memory: `project_egglog_engine_extensions.md`.
- **Phase ordering rationale:** Egglog (Phase 1) before direct evaluator
  (Phase 2) because: (a) egglog validates the relational evaluation model
  which is the novel contribution, (b) the bridge pattern needs to be proven
  before committing to the escalation architecture, (c) the direct evaluator
  is straightforward and low-risk.
- **`seed_database()` is where most bugs will live.** It maps `Term` variants
  to egglog tables (`Bop` → `Add`/`Minus`, `Module` → nested `Let`,
  `Hole`/`Error`/`Unbound` → not seeded). Careful testing of this function is
  critical.
- Related: egraph evaluator PoC (`loom/egraph/lambda_eval_wbtest.mbt`),
  egglog typing example (`loom/egglog/examples/lambda/`),
  incremental compiler vision (memory: `project_incremental_compiler_vision.md`),
  egglog engine extensions (memory: `project_egglog_engine_extensions.md`),
  e-graph/egglog research (memory: `reference_egraph_egglog_research.md`)

## Prior Art

Key references that informed this design:

- **egg `lambda.rs`** — canonical lambda partial evaluator in e-graphs.
  Explicit substitution via `let` nodes, `CaptureAvoid` applier, free-var
  e-class analysis. Basis for Tier 3 approach.
- **egglog `fibonacci-demand.egg`** — demand-driven evaluation with
  `constructor` keyword. Our `Demand` table is the same pattern.
- **Cranelift aegraphs** — production compiler using e-graphs with side-effect
  skeleton maintained separately. Validates our Datalog + Bridge hybrid.
- **Herbie in egglog** — `:when` guards for conditional rule firing, ruleset
  separation for phased analysis. Our bridge does what `:when` guards do.
- **Slotted E-Graphs (PLDI 2025)** — future direction for Tier 3 binding.
- **Hazel** — hole closures for fill-and-resume partial evaluation. Relevant
  to our partial evaluation via cascading non-derivation.
- **egg Runner** — node/iter/time limits + BackoffScheduler. Basis for our
  divergence handling (loop limit + fact count limit).
