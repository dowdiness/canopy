# CRDT Multi-Agent Convergence Fuzz Test Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add property-based fuzz tests that verify N-agent CRDT convergence under arbitrary interleaving of inserts, deletes, undo/redo, and partial syncs.

**Architecture:** A `MultiAgentTrace` generator produces random sequences of `AgentAction`s across 2-5 agents. Each action is applied to the corresponding agent's `TextDoc` + `UndoManager`. After all actions execute, a full all-to-all sync verifies convergence. Uses existing QuickCheck (`@qc`) infrastructure.

**Tech Stack:** MoonBit, `moonbitlang/quickcheck` (`@qc`), `event-graph-walker/text`, `event-graph-walker/undo`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `event-graph-walker/text/text_convergence_fuzz_test.mbt` | Multi-agent fuzz test: generator, properties, tests |

This is a single-file addition — no existing code changes. All types are test-private.

---

### Task 1: AgentAction generator + multi-agent convergence property

**Files:**
- Create: `event-graph-walker/text/text_convergence_fuzz_test.mbt`

- [ ] **Step 1: Write the MultiAgentTrace type and Arbitrary instance**

In `event-graph-walker/text/text_convergence_fuzz_test.mbt`:

```moonbit
///|
/// Actions an agent can take during a fuzz trace.
enum AgentAction {
  FuzzInsert(Int, Int, String) // (agent_idx, pos, char)
  FuzzDelete(Int, Int)         // (agent_idx, pos)
  FuzzUndo(Int)                // (agent_idx)
  FuzzRedo(Int)                // (agent_idx)
  FuzzSync(Int, Int)           // (from_idx, to_idx)
} derive(Show)

///|
/// A generated trace of multi-agent actions.
struct MultiAgentTrace {
  num_agents : Int
  actions : Array[AgentAction]
} derive(Show)

///|
impl @quickcheck.Arbitrary for MultiAgentTrace with arbitrary(size, rs) {
  let chars : Array[String] = [
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j",
  ]
  let num_agents = 2 + (rs.split().next_uint64().to_int().abs() % 4) // 2-5 agents
  // Use scratch docs to track valid positions during generation
  let scratches : Array[@text.TextDoc] = []
  for i = 0; i < num_agents; i = i + 1 {
    scratches.push(@text.TextDoc::new("agent_" + i.to_string()))
  }
  let actions : Array[AgentAction] = []
  let action_count = if size < 5 { 5 } else { size }
  for _ = 0; _ < action_count; _ = _ + 1 {
    let agent = rs.split().next_uint64().to_int().abs() % num_agents
    let doc = scratches[agent]
    let action_type = rs.split().next_uint64().to_int().abs() % 10
    if action_type < 4 {
      // 40% insert
      let len = doc.len()
      let pos = rs.split().next_uint64().to_int().abs() % (len + 1)
      let ch = chars[rs.split().next_uint64().to_int().abs() % chars.length()]
      doc.insert(@text.Pos::at(pos), ch) catch { _ => continue }
      actions.push(FuzzInsert(agent, pos, ch))
    } else if action_type < 7 {
      // 30% delete
      let len = doc.len()
      if len == 0 { continue }
      let pos = rs.split().next_uint64().to_int().abs() % len
      doc.delete(@text.Pos::at(pos)) catch { _ => continue }
      actions.push(FuzzDelete(agent, pos))
    } else if action_type < 8 {
      // 10% undo
      actions.push(FuzzUndo(agent))
    } else if action_type < 9 {
      // 10% redo
      actions.push(FuzzRedo(agent))
    } else {
      // 10% sync pair
      let mut to = rs.split().next_uint64().to_int().abs() % num_agents
      if to == agent {
        to = (to + 1) % num_agents
      }
      // Sync scratch docs too so positions stay valid
      let msg = doc.sync().export_all() catch { _ => continue }
      scratches[to].sync().apply(msg) catch { _ => continue }
      actions.push(FuzzSync(agent, to))
    }
  }
  { num_agents, actions }
}

///|
impl @qc.Shrink for MultiAgentTrace with shrink(self) {
  let results : Array[MultiAgentTrace] = []
  let len = self.actions.length()
  if len > 1 {
    // Try empty
    results.push({ num_agents: self.num_agents, actions: [] })
    // Try first half
    let half = len / 2
    if half > 0 {
      results.push({ num_agents: self.num_agents, actions: self.actions[:half].to_array() })
    }
    // Try dropping last action
    results.push({ num_agents: self.num_agents, actions: self.actions[:len - 1].to_array() })
  }
  results.iter()
}
```

- [ ] **Step 2: Write the convergence property function**

Append to the same file:

```moonbit
///|
/// Execute a multi-agent trace and verify convergence after full sync.
fn prop_multi_agent_convergence(trace : MultiAgentTrace) -> Bool {
  let docs : Array[@text.TextDoc] = []
  let mgrs : Array[@undo.UndoManager] = []
  for i = 0; i < trace.num_agents; i = i + 1 {
    let id = "agent_" + i.to_string()
    docs.push(@text.TextDoc::new(id))
    mgrs.push(@undo.UndoManager::new(id))
  }

  // Execute actions
  for action in trace.actions {
    match action {
      FuzzInsert(agent, pos, ch) => {
        let doc = docs[agent]
        let mgr = mgrs[agent]
        let clamped = if pos > doc.len() { doc.len() } else { pos }
        doc.insert_and_record(
          @text.Pos::at(clamped), ch, mgr, timestamp_ms=0,
        ) catch { _ => continue }
      }
      FuzzDelete(agent, pos) => {
        let doc = docs[agent]
        let mgr = mgrs[agent]
        if doc.len() == 0 { continue }
        let clamped = if pos >= doc.len() { doc.len() - 1 } else { pos }
        doc.delete_and_record(
          @text.Pos::at(clamped), mgr, timestamp_ms=0,
        ) catch { _ => continue }
      }
      FuzzUndo(agent) => {
        if mgrs[agent].can_undo() {
          let _ = mgrs[agent].undo(docs[agent]) catch { _ => () }
        }
      }
      FuzzRedo(agent) => {
        if mgrs[agent].can_redo() {
          let _ = mgrs[agent].redo(docs[agent]) catch { _ => () }
        }
      }
      FuzzSync(from, to) => {
        let msg = docs[from].sync().export_all() catch { _ => continue }
        docs[to].sync().apply(msg) catch { _ => continue }
      }
    }
  }

  // Full all-to-all sync: each agent exports, all others apply
  let messages : Array[@text.SyncMessage] = []
  for doc in docs {
    messages.push(doc.sync().export_all() catch { _ => return true })
  }
  for i = 0; i < docs.length(); i = i + 1 {
    for j = 0; j < messages.length(); j = j + 1 {
      if i != j {
        docs[i].sync().apply(messages[j]) catch { _ => return true }
      }
    }
  }

  // Verify all agents converged to the same text
  let expected = docs[0].text()
  for i = 1; i < docs.length(); i = i + 1 {
    if docs[i].text() != expected {
      return false
    }
  }
  true
}
```

- [ ] **Step 3: Write the test entry point**

Append to the same file:

```moonbit
///|
test "property: multi-agent convergence under random interleaving" {
  @qc.quick_check_fn(prop_multi_agent_convergence)
}
```

- [ ] **Step 4: Run the test**

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/text -f text_convergence_fuzz_test.mbt`
Expected: PASS (QuickCheck runs 100 random traces)

If it fails, the shrunk counterexample will show the minimal trace that breaks convergence — this is the high-value output.

- [ ] **Step 5: Run full test suite to verify no regressions**

Run: `cd event-graph-walker && moon test`
Expected: All existing tests pass + new fuzz test passes.

- [ ] **Step 6: moon check + moon fmt**

Run: `cd event-graph-walker && moon check && moon fmt`
Expected: Clean.

- [ ] **Step 7: Commit**

```bash
cd event-graph-walker
git add text/text_convergence_fuzz_test.mbt
git commit -m "test(text): add multi-agent convergence fuzz test

Property-based test with 2-5 agents performing random inserts, deletes,
undo/redo, and partial syncs. Verifies all replicas converge after
full all-to-all sync."
```

---

### Task 2: Additional convergence properties

**Files:**
- Modify: `event-graph-walker/text/text_convergence_fuzz_test.mbt`

Add two more properties that test specific convergence scenarios.

- [ ] **Step 1: Write sync-order-independence property**

Append to the file:

```moonbit
///|
/// Property: Convergence is independent of sync order.
/// Two agents make concurrent edits. Syncing A→B then B→A
/// must produce the same result as B→A then A→B.
fn prop_sync_order_independence(pair : (RealOps, RealOps)) -> Bool {
  let (ops1, ops2) = pair
  // Path 1: A→B then B→A
  let a1 = @text.TextDoc::new("alice")
  let b1 = @text.TextDoc::new("bob")
  if not(apply_edits(a1, ops1.edits)) { return true }
  if not(apply_edits(b1, ops2.edits)) { return true }
  let msg_a1 = a1.sync().export_all() catch { _ => return true }
  let msg_b1 = b1.sync().export_all() catch { _ => return true }
  b1.sync().apply(msg_a1) catch { _ => return true }
  a1.sync().apply(msg_b1) catch { _ => return true }

  // Path 2: B→A then A→B (fresh docs)
  let a2 = @text.TextDoc::new("alice")
  let b2 = @text.TextDoc::new("bob")
  if not(apply_edits(a2, ops1.edits)) { return true }
  if not(apply_edits(b2, ops2.edits)) { return true }
  let msg_a2 = a2.sync().export_all() catch { _ => return true }
  let msg_b2 = b2.sync().export_all() catch { _ => return true }
  a2.sync().apply(msg_b2) catch { _ => return true }
  b2.sync().apply(msg_a2) catch { _ => return true }

  // Both paths must produce same result
  a1.text() == a2.text() && b1.text() == b2.text() && a1.text() == b1.text()
}

///|
test "property: sync order independence" {
  @qc.quick_check_fn(prop_sync_order_independence)
}
```

- [ ] **Step 2: Write undo-under-concurrency convergence property**

Append to the file:

```moonbit
///|
/// Property: Undo under concurrency still converges.
/// Agent A types, agent B types concurrently, A undoes, then full sync.
fn prop_undo_concurrent_convergence(pair : (RealOps, RealOps)) -> Bool {
  let (ops1, ops2) = pair
  let doc_a = @text.TextDoc::new("alice")
  let doc_b = @text.TextDoc::new("bob")
  let mgr_a = @undo.UndoManager::new("alice")

  // A types with undo recording
  for edit in ops1.edits {
    match edit {
      Insert(pos, ch) =>
        doc_a.insert_and_record(
          @text.Pos::at(pos), ch, mgr_a, timestamp_ms=0,
        ) catch { _ => continue }
      Delete(pos) =>
        doc_a.delete_and_record(
          @text.Pos::at(pos), mgr_a, timestamp_ms=0,
        ) catch { _ => continue }
    }
  }

  // B types concurrently (no undo tracking needed)
  if not(apply_edits(doc_b, ops2.edits)) { return true }

  // A undoes once (if possible)
  if mgr_a.can_undo() {
    let _ = mgr_a.undo(doc_a) catch { _ => () }
  }

  // Full sync
  let msg_a = doc_a.sync().export_all() catch { _ => return true }
  let msg_b = doc_b.sync().export_all() catch { _ => return true }
  doc_a.sync().apply(msg_b) catch { _ => return true }
  doc_b.sync().apply(msg_a) catch { _ => return true }

  // Must converge
  doc_a.text() == doc_b.text()
}

///|
test "property: undo under concurrency converges" {
  @qc.quick_check_fn(prop_undo_concurrent_convergence)
}
```

- [ ] **Step 3: Run tests**

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/text -f text_convergence_fuzz_test.mbt`
Expected: All 3 property tests PASS.

- [ ] **Step 4: Run full suite**

Run: `cd event-graph-walker && moon test`
Expected: All tests pass.

- [ ] **Step 5: moon check + moon fmt + commit**

```bash
cd event-graph-walker && moon check && moon fmt
git add text/text_convergence_fuzz_test.mbt
git commit -m "test(text): add sync-order-independence and undo-concurrency fuzz tests"
```

---

## Post-implementation notes

**Follow-up fuzz tests (future iterations):**
1. **3-agent transitive sync** — A syncs to B, B syncs to C, C syncs to A. Verify convergence without direct A↔C sync.
2. **Undo/redo interleaved with partial sync** — Agent undoes, partially syncs, other agent edits at the undo point, then full sync.
3. **Parser fuzz** — Random byte streams into loom parser, verify no panics.
4. **Stress test** — Increase QuickCheck size to 500+ actions, 10+ agents. Run with `--release` for benchmarking.
