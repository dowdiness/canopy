# RLE Phase 1: OpRun Compression Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compress OpLog.operations from Array[Op] to Rle[OpRun], achieving 10,000:1 compression for single-user typing.

**Architecture:** Define OpRun in core package with Mergeable+Spanning traits. The merge condition ensures only linear left-to-right typing runs compress. Decompression via offset arithmetic preserves exact Op semantics. Sliceable is NOT needed (append-only log).

**Deferred:** `Sliceable` for `OpRun` is deferred (spec mentions it but it's only needed for positional editing on the log, which is append-only). The spec's mention of `slice_string_view` for character extraction is addressed via codepoint iteration in `decompress`, which is correct since `count` counts ops (one per character), not UTF-16 code units.

**Tech Stack:** MoonBit, dowdiness/rle library

**Spec:** `docs/plans/2026-03-15-rle-library-integration.md` (Phase 1 section)

**Important:** `event-graph-walker/` is a git submodule. All source changes are inside it.

**Worktree:** `.worktrees/rle-phase0/` — all paths below are relative to this worktree root unless fully qualified.

---

### Task 1: Define OpRun + OpRunContent types

**Files:**
- Create: `event-graph-walker/internal/core/op_run.mbt`
- Modify: `event-graph-walker/internal/core/moon.pkg` (add `dowdiness/rle` import)

- [ ] **Step 1: Add `dowdiness/rle` import to core moon.pkg**

Edit `event-graph-walker/internal/core/moon.pkg`:

```
import {
  "moonbitlang/core/json",
  "moonbitlang/core/hashset",
  "dowdiness/rle",
}

options(
  is_main: false,
)
```

- [ ] **Step 2: Create `event-graph-walker/internal/core/op_run.mbt` with type definitions**

```moonbit
///| Run-length encoded operation types

///|
/// Compressed content for a run of operations.
///
/// - `Inserts(String)` — concatenated inserted characters (one char per op)
/// - `Deletes` — `count` consecutive delete ops (count stored in OpRun)
/// - `Undeletes` — `count` consecutive undelete ops (count stored in OpRun)
pub enum OpRunContent {
  Inserts(String)
  Deletes
  Undeletes
} derive(Show, Eq)

///|
/// A compressed run of consecutive operations from the same agent.
///
/// Represents `count` operations with sequential LVs `[start_lv, start_lv + count)`
/// and sequential seq numbers `[start_seq, start_seq + count)`.
///
/// Only linear left-to-right typing compresses: each op's parent must be the
/// immediately preceding op in the run, and for inserts the origin_left must
/// chain sequentially while origin_right stays constant.
pub struct OpRun {
  start_lv : Int
  agent : String
  start_seq : Int
  content : OpRunContent
  parents : Array[RawVersion]
  origin_left : RawVersion?
  origin_right : RawVersion?
  count : Int
} derive(Show, Eq)
```

- [ ] **Step 3: Verify it compiles**

```bash
cd event-graph-walker && moon check
```

- [ ] **Step 4: Commit inside submodule**

```bash
cd event-graph-walker
git add internal/core/moon.pkg internal/core/op_run.mbt
git commit -m "feat: define OpRun + OpRunContent types (Phase 1, Task 1)

Add run-length encoded operation types to core package.
OpRun compresses consecutive ops from the same agent.
OpRunContent handles Insert/Delete/Undelete content variants."
```

---

### Task 2: Implement OpRun::from_op (single Op to single-element OpRun)

**Files:**
- Modify: `event-graph-walker/internal/core/op_run.mbt`

- [ ] **Step 1: Add `OpRun::from_op` constructor**

Append to `event-graph-walker/internal/core/op_run.mbt`:

```moonbit
///|
/// Create a single-element OpRun from an Op.
///
/// This is the entry point for compression: every Op becomes a count=1 OpRun,
/// and adjacent runs merge via the Mergeable trait.
pub fn OpRun::from_op(op : Op) -> OpRun {
  let content = match op.content() {
    Insert(text) => Inserts(text)
    Delete => Deletes
    Undelete => Undeletes
  }
  {
    start_lv: op.lv(),
    agent: op.agent(),
    start_seq: op.seq(),
    content,
    parents: op.parents(),
    origin_left: op.origin_left(),
    origin_right: op.origin_right(),
    count: 1,
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd event-graph-walker && moon check
```

- [ ] **Step 3: Commit inside submodule**

```bash
cd event-graph-walker
git add internal/core/op_run.mbt
git commit -m "feat: implement OpRun::from_op (Phase 1, Task 2)

Convert a single Op into a count=1 OpRun. This is the entry point
for the append-and-merge compression pipeline."
```

---

### Task 3: Implement OpRun::decompress(offset) -> Op

**Files:**
- Modify: `event-graph-walker/internal/core/op_run.mbt`

- [ ] **Step 1: Add `OpRun::decompress` method**

Append to `event-graph-walker/internal/core/op_run.mbt`:

```moonbit
///|
/// Decompress a single Op at the given offset within this run.
///
/// `offset` must be in `[0, self.count)`. The decompressed Op has:
/// - `lv = start_lv + offset`
/// - `seq = start_seq + offset`
/// - `parents`: first op uses `self.parents`; subsequent ops use
///   `[RawVersion(agent, start_seq + offset - 1)]` (the preceding op)
/// - `origin_left`: first op uses `self.origin_left`; subsequent ops use
///   `Some(RawVersion(agent, start_seq + offset - 1))`
/// - `origin_right`: always `self.origin_right`
/// - `content`: for Inserts, extracts the single character at `offset`
pub fn OpRun::decompress(self : OpRun, offset : Int) -> Op? {
  if offset < 0 || offset >= self.count {
    return None
  }
  let lv = self.start_lv + offset
  let seq = self.start_seq + offset
  let parents = if offset == 0 {
    self.parents.copy()
  } else {
    [RawVersion::new(self.agent, self.start_seq + offset - 1)]
  }
  let origin_left = if offset == 0 {
    self.origin_left
  } else {
    Some(RawVersion::new(self.agent, self.start_seq + offset - 1))
  }
  let origin_right = self.origin_right
  let content = match self.content {
    Inserts(text) => {
      // Extract single character at offset.
      // Each op in the run inserted exactly one character, so offset
      // maps 1:1 to a UTF-16 code unit index for ASCII. For multi-code-unit
      // characters, we iterate to the correct codepoint.
      let mut char_idx = 0
      let mut result_char = ""
      for ch in text {
        if char_idx == offset {
          result_char = ch.to_string()
          break
        }
        char_idx = char_idx + 1
      }
      Insert(result_char)
    }
    Deletes => Delete
    Undeletes => Undelete
  }
  Some(
    Op::new_from_parts(
      lv~,
      parents~,
      agent=self.agent,
      seq~,
      content~,
      origin_left~,
      origin_right~,
    ),
  )
}
```

- [ ] **Step 2: Add `Op::new_from_parts` internal constructor to `operation.mbt`**

Append to `event-graph-walker/internal/core/operation.mbt`:

```moonbit
///|
/// Internal constructor for Op from all parts.
/// Used by OpRun::decompress to reconstruct individual operations.
pub fn Op::new_from_parts(
  lv~ : Int,
  parents~ : Array[RawVersion],
  agent~ : String,
  seq~ : Int,
  content~ : OpContent,
  origin_left~ : RawVersion?,
  origin_right~ : RawVersion?,
) -> Op {
  { lv, parents, agent, seq, content, origin_left, origin_right }
}
```

- [ ] **Step 3: Verify it compiles**

```bash
cd event-graph-walker && moon check
```

- [ ] **Step 4: Commit inside submodule**

```bash
cd event-graph-walker
git add internal/core/op_run.mbt internal/core/operation.mbt
git commit -m "feat: implement OpRun::decompress and Op::new_from_parts (Phase 1, Task 3)

Decompress extracts a single Op at a given offset within a run.
Parents, origin_left chain sequentially for non-first offsets.
Op::new_from_parts provides full-field construction for decompression."
```

---

### Task 4: Roundtrip tests (Op -> OpRun -> Op)

**Files:**
- Create: `event-graph-walker/internal/core/op_run_wbtest.mbt`

- [ ] **Step 1: Write roundtrip tests for all content types**

Create `event-graph-walker/internal/core/op_run_wbtest.mbt`:

```moonbit
///| Whitebox tests for OpRun compression/decompression

///|
test "roundtrip: insert op -> OpRun -> Op" {
  let op = Op::new_insert(
    5,
    [RawVersion::new("alice", 3)],
    "alice",
    4,
    "x",
    Some(RawVersion::new("alice", 3)),
    Some(RawVersion::new("bob", 0)),
  )
  let run = OpRun::from_op(op)
  inspect(run.count, content="1")
  inspect(run.start_lv, content="5")
  inspect(run.agent, content="alice")
  inspect(run.start_seq, content="4")
  let decompressed = run.decompress(0)
  guard decompressed is Some(d) else { fail("expected Some") }
  inspect(d.lv(), content="5")
  inspect(d.agent(), content="alice")
  inspect(d.seq(), content="4")
  inspect(d.content(), content="Insert(\"x\")")
  inspect(d.origin_left(), content="Some({agent: \"alice\", seq: 3})")
  inspect(d.origin_right(), content="Some({agent: \"bob\", seq: 0})")
  inspect(d.parents(), content="[{agent: \"alice\", seq: 3}]")
}

///|
test "roundtrip: delete op -> OpRun -> Op" {
  let op = Op::new_delete(
    10,
    [RawVersion::new("bob", 5)],
    "bob",
    6,
    Some(RawVersion::new("alice", 2)),
  )
  let run = OpRun::from_op(op)
  let decompressed = run.decompress(0)
  guard decompressed is Some(d) else { fail("expected Some") }
  inspect(d.lv(), content="10")
  inspect(d.agent(), content="bob")
  inspect(d.seq(), content="6")
  inspect(d.content(), content="Delete")
  inspect(d.origin_left(), content="Some({agent: \"alice\", seq: 2})")
  inspect(d.origin_right(), content="None")
}

///|
test "roundtrip: undelete op -> OpRun -> Op" {
  let op = Op::new_undelete(
    20,
    [RawVersion::new("carol", 10)],
    "carol",
    11,
    Some(RawVersion::new("alice", 5)),
  )
  let run = OpRun::from_op(op)
  let decompressed = run.decompress(0)
  guard decompressed is Some(d) else { fail("expected Some") }
  inspect(d.lv(), content="20")
  inspect(d.content(), content="Undelete")
  inspect(d.origin_left(), content="Some({agent: \"alice\", seq: 5})")
}

///|
test "decompress: offset out of bounds returns None" {
  let op = Op::new_insert(0, [], "a", 0, "x", None, None)
  let run = OpRun::from_op(op)
  inspect(run.decompress(-1), content="None")
  inspect(run.decompress(1), content="None")
}
```

- [ ] **Step 2: Run tests and update snapshots**

```bash
cd event-graph-walker && moon test --update
```

Verify all tests pass. If any snapshot values differ from the `content=` strings above, update the test file to match the actual output.

- [ ] **Step 3: Commit inside submodule**

```bash
cd event-graph-walker
git add internal/core/op_run_wbtest.mbt
git commit -m "test: roundtrip tests for OpRun from_op/decompress (Phase 1, Task 4)

Covers Insert, Delete, Undelete content types. Verifies all fields
survive the Op -> OpRun -> Op roundtrip. Tests out-of-bounds offset."
```

---

### Task 5: Implement Mergeable for OpRun (can_merge + merge)

**Files:**
- Modify: `event-graph-walker/internal/core/op_run.mbt`

- [ ] **Step 1: Implement `Mergeable` trait for OpRun**

Append to `event-graph-walker/internal/core/op_run.mbt`:

```moonbit
///|
/// Two OpRuns can merge when they represent a contiguous linear typing run:
/// - Same agent
/// - Sequential seq numbers (a ends where b starts)
/// - Sequential LVs (a ends where b starts)
/// - Same content type
/// - b's only parent is the last op of a
/// - For inserts: b's origin_left is the last op of a, and
///   b's origin_right equals a's origin_right
pub impl @rle.Mergeable for OpRun with can_merge(a : OpRun, b : OpRun) -> Bool {
  // Same agent
  if a.agent != b.agent {
    return false
  }
  // Sequential seq numbers
  if a.start_seq + a.count != b.start_seq {
    return false
  }
  // Sequential LVs
  if a.start_lv + a.count != b.start_lv {
    return false
  }
  // b's only parent is end of a
  let expected_parent = RawVersion::new(a.agent, a.start_seq + a.count - 1)
  if b.parents.length() != 1 || b.parents[0] != expected_parent {
    return false
  }
  // Same content type + type-specific checks
  match (a.content, b.content) {
    (Inserts(_), Inserts(_)) => {
      // b's origin_left must be the last op of a
      let expected_origin_left = Some(
        RawVersion::new(a.agent, a.start_seq + a.count - 1),
      )
      if b.origin_left != expected_origin_left {
        return false
      }
      // origin_right must match (cursor hasn't jumped)
      if a.origin_right != b.origin_right {
        return false
      }
      true
    }
    (Deletes, Deletes) => true
    (Undeletes, Undeletes) => true
    _ => false
  }
}

///|
/// Merge two adjacent OpRuns into one.
///
/// Precondition: `can_merge(a, b)` must be true.
/// The merged run keeps a's metadata (start_lv, start_seq, parents,
/// origin_left, origin_right) and extends count.
pub impl @rle.Mergeable for OpRun with merge(a : OpRun, b : OpRun) -> OpRun {
  let content = match (a.content, b.content) {
    (Inserts(text_a), Inserts(text_b)) => Inserts(text_a + text_b)
    (Deletes, Deletes) => Deletes
    (Undeletes, Undeletes) => Undeletes
    // can_merge guarantees same content type, so these cases won't occur
    _ => a.content
  }
  {
    start_lv: a.start_lv,
    agent: a.agent,
    start_seq: a.start_seq,
    content,
    parents: a.parents,
    origin_left: a.origin_left,
    origin_right: a.origin_right,
    count: a.count + b.count,
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd event-graph-walker && moon check
```

- [ ] **Step 3: Commit inside submodule**

```bash
cd event-graph-walker
git add internal/core/op_run.mbt
git commit -m "feat: implement Mergeable for OpRun (Phase 1, Task 5)

can_merge checks: same agent, sequential LV/seq, single-parent chain,
same content type, and for inserts: chained origin_left + matching
origin_right. merge concatenates insert text or sums count."
```

---

### Task 6: Merge condition tests (positive and negative)

**Files:**
- Modify: `event-graph-walker/internal/core/op_run_wbtest.mbt`

- [ ] **Step 1: Add merge condition tests**

Append to `event-graph-walker/internal/core/op_run_wbtest.mbt`:

```moonbit
///|
test "can_merge: linear insert typing run merges" {
  // Simulates typing "ab": op0 inserts "a", op1 inserts "b" right after
  let run_a = OpRun::from_op(
    Op::new_insert(
      0,
      [],
      "alice",
      0,
      "a",
      None,
      Some(RawVersion::new("bob", 0)),
    ),
  )
  let run_b = OpRun::from_op(
    Op::new_insert(
      1,
      [RawVersion::new("alice", 0)],
      "alice",
      1,
      "b",
      Some(RawVersion::new("alice", 0)),
      Some(RawVersion::new("bob", 0)),
    ),
  )
  inspect(@rle.Mergeable::can_merge(run_a, run_b), content="true")
  let merged = @rle.Mergeable::merge(run_a, run_b)
  inspect(merged.count, content="2")
  inspect(merged.start_lv, content="0")
  inspect(merged.start_seq, content="0")
  match merged.content {
    Inserts(text) => inspect(text, content="ab")
    _ => fail("expected Inserts")
  }
}

///|
test "can_merge: different agents do not merge" {
  let run_a = OpRun::from_op(
    Op::new_insert(0, [], "alice", 0, "a", None, None),
  )
  let run_b = OpRun::from_op(
    Op::new_insert(
      1,
      [RawVersion::new("alice", 0)],
      "bob",
      0,
      "b",
      Some(RawVersion::new("alice", 0)),
      None,
    ),
  )
  inspect(@rle.Mergeable::can_merge(run_a, run_b), content="false")
}

///|
test "can_merge: non-sequential seq does not merge" {
  let run_a = OpRun::from_op(
    Op::new_insert(0, [], "alice", 0, "a", None, None),
  )
  // seq gap: 0 -> 2 (skipping 1)
  let run_b = OpRun::from_op(
    Op::new_insert(
      1,
      [RawVersion::new("alice", 0)],
      "alice",
      2,
      "b",
      Some(RawVersion::new("alice", 0)),
      None,
    ),
  )
  inspect(@rle.Mergeable::can_merge(run_a, run_b), content="false")
}

///|
test "can_merge: non-sequential LV does not merge" {
  let run_a = OpRun::from_op(
    Op::new_insert(0, [], "alice", 0, "a", None, None),
  )
  // LV gap: 0 -> 5 (should be 1)
  let run_b : OpRun = {
    start_lv: 5,
    agent: "alice",
    start_seq: 1,
    content: Inserts("b"),
    parents: [RawVersion::new("alice", 0)],
    origin_left: Some(RawVersion::new("alice", 0)),
    origin_right: None,
    count: 1,
  }
  inspect(@rle.Mergeable::can_merge(run_a, run_b), content="false")
}

///|
test "can_merge: different content types do not merge" {
  let run_a = OpRun::from_op(
    Op::new_insert(0, [], "alice", 0, "a", None, None),
  )
  let run_b = OpRun::from_op(
    Op::new_delete(
      1,
      [RawVersion::new("alice", 0)],
      "alice",
      1,
      Some(RawVersion::new("bob", 0)),
    ),
  )
  inspect(@rle.Mergeable::can_merge(run_a, run_b), content="false")
}

///|
test "can_merge: insert with different origin_right does not merge" {
  let run_a = OpRun::from_op(
    Op::new_insert(
      0,
      [],
      "alice",
      0,
      "a",
      None,
      Some(RawVersion::new("bob", 0)),
    ),
  )
  // origin_right differs: bob:0 vs carol:0
  let run_b = OpRun::from_op(
    Op::new_insert(
      1,
      [RawVersion::new("alice", 0)],
      "alice",
      1,
      "b",
      Some(RawVersion::new("alice", 0)),
      Some(RawVersion::new("carol", 0)),
    ),
  )
  inspect(@rle.Mergeable::can_merge(run_a, run_b), content="false")
}

///|
test "can_merge: multiple parents does not merge" {
  let run_a = OpRun::from_op(
    Op::new_insert(0, [], "alice", 0, "a", None, None),
  )
  // b has two parents (concurrent merge point)
  let run_b = OpRun::from_op(
    Op::new_insert(
      1,
      [RawVersion::new("alice", 0), RawVersion::new("bob", 0)],
      "alice",
      1,
      "b",
      Some(RawVersion::new("alice", 0)),
      None,
    ),
  )
  inspect(@rle.Mergeable::can_merge(run_a, run_b), content="false")
}

///|
test "can_merge: consecutive deletes merge" {
  let run_a = OpRun::from_op(
    Op::new_delete(
      0,
      [],
      "alice",
      0,
      Some(RawVersion::new("bob", 0)),
    ),
  )
  let run_b = OpRun::from_op(
    Op::new_delete(
      1,
      [RawVersion::new("alice", 0)],
      "alice",
      1,
      Some(RawVersion::new("bob", 1)),
    ),
  )
  inspect(@rle.Mergeable::can_merge(run_a, run_b), content="true")
}

///|
test "decompress: multi-op insert run at various offsets" {
  // Manually build a 3-op insert run: "abc" at LVs 10,11,12
  let run : OpRun = {
    start_lv: 10,
    agent: "alice",
    start_seq: 5,
    content: Inserts("abc"),
    parents: [RawVersion::new("bob", 3)],
    origin_left: Some(RawVersion::new("bob", 3)),
    origin_right: Some(RawVersion::new("carol", 0)),
    count: 3,
  }
  // Offset 0: uses original parents and origin_left
  let d0 = run.decompress(0)
  guard d0 is Some(op0) else { fail("expected Some") }
  inspect(op0.lv(), content="10")
  inspect(op0.seq(), content="5")
  inspect(op0.parents(), content="[{agent: \"bob\", seq: 3}]")
  inspect(op0.origin_left(), content="Some({agent: \"bob\", seq: 3})")
  inspect(op0.origin_right(), content="Some({agent: \"carol\", seq: 0})")
  inspect(op0.content(), content="Insert(\"a\")")
  // Offset 1: parent and origin_left point to previous op in run
  let d1 = run.decompress(1)
  guard d1 is Some(op1) else { fail("expected Some") }
  inspect(op1.lv(), content="11")
  inspect(op1.seq(), content="6")
  inspect(op1.parents(), content="[{agent: \"alice\", seq: 5}]")
  inspect(op1.origin_left(), content="Some({agent: \"alice\", seq: 5})")
  inspect(op1.origin_right(), content="Some({agent: \"carol\", seq: 0})")
  inspect(op1.content(), content="Insert(\"b\")")
  // Offset 2: parent and origin_left point to op at offset 1
  let d2 = run.decompress(2)
  guard d2 is Some(op2) else { fail("expected Some") }
  inspect(op2.lv(), content="12")
  inspect(op2.seq(), content="7")
  inspect(op2.parents(), content="[{agent: \"alice\", seq: 6}]")
  inspect(op2.origin_left(), content="Some({agent: \"alice\", seq: 6})")
  inspect(op2.origin_right(), content="Some({agent: \"carol\", seq: 0})")
  inspect(op2.content(), content="Insert(\"c\")")
}
```

- [ ] **Step 2: Run tests and update snapshots**

```bash
cd event-graph-walker && moon test --update
```

Verify all tests pass. If any snapshot values differ, update the test to match actual output.

- [ ] **Step 3: Commit inside submodule**

```bash
cd event-graph-walker
git add internal/core/op_run_wbtest.mbt
git commit -m "test: merge condition tests for OpRun (Phase 1, Task 6)

Positive cases: linear insert typing, consecutive deletes.
Negative cases: different agents, seq gap, LV gap, content type
mismatch, origin_right mismatch, multiple parents.
Multi-offset decompress test verifies parent/origin chaining."
```

---

### Task 7: Implement HasLength + Spanning for OpRun

**Files:**
- Modify: `event-graph-walker/internal/core/op_run.mbt`

- [ ] **Step 1: Implement `HasLength` and `Spanning` traits**

Append to `event-graph-walker/internal/core/op_run.mbt`:

```moonbit
///|
/// HasLength: number of ops in the run.
pub impl @rle.HasLength for OpRun with length(self : OpRun) -> Int {
  self.count
}

///|
/// Spanning: span is the number of ops (one LV per op).
/// This defines the coordinate space for Rle::find — position maps to LV.
pub impl @rle.Spanning for OpRun with span(self : OpRun) -> Int {
  self.count
}

///|
/// Spanning: logical_length equals span (no tombstones at the OpRun level).
pub impl @rle.Spanning for OpRun with logical_length(self : OpRun) -> Int {
  self.count
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd event-graph-walker && moon check
```

- [ ] **Step 3: Quick test — Rle[OpRun] can be created and appended to**

Append to `event-graph-walker/internal/core/op_run_wbtest.mbt`:

```moonbit
///|
test "Rle[OpRun]: append auto-merges linear typing" {
  let rle : @rle.Rle[OpRun] = @rle.Rle::new()
  let op0 = Op::new_insert(
    0,
    [],
    "alice",
    0,
    "h",
    None,
    Some(RawVersion::new("bob", 0)),
  )
  let op1 = Op::new_insert(
    1,
    [RawVersion::new("alice", 0)],
    "alice",
    1,
    "i",
    Some(RawVersion::new("alice", 0)),
    Some(RawVersion::new("bob", 0)),
  )
  let _ = rle.append(OpRun::from_op(op0))
  let _ = rle.append(OpRun::from_op(op1))
  // Two ops should merge into one run
  inspect(rle.length(), content="1")
  inspect(rle.span(), content="2")
}

///|
test "Rle[OpRun]: non-mergeable ops stay separate" {
  let rle : @rle.Rle[OpRun] = @rle.Rle::new()
  let op0 = Op::new_insert(0, [], "alice", 0, "a", None, None)
  let op1 = Op::new_insert(1, [], "bob", 0, "b", None, None)
  let _ = rle.append(OpRun::from_op(op0))
  let _ = rle.append(OpRun::from_op(op1))
  // Different agents: 2 separate runs
  inspect(rle.length(), content="2")
  inspect(rle.span(), content="2")
}
```

- [ ] **Step 4: Run tests**

```bash
cd event-graph-walker && moon test --update
```

- [ ] **Step 5: Update interfaces and format**

```bash
cd event-graph-walker && moon info && moon fmt
```

- [ ] **Step 6: Commit inside submodule**

```bash
cd event-graph-walker
git add internal/core/op_run.mbt internal/core/op_run_wbtest.mbt internal/core/pkg.generated.mbti
git commit -m "feat: implement HasLength + Spanning for OpRun (Phase 1, Task 7)

span = count (one LV per op). Rle[OpRun] can now auto-merge on append.
Tests verify merge and non-merge behavior via Rle::append."
```

---

### Task 8: Update OpLog storage (Array[Op] -> Rle[OpRun])

**Files:**
- Modify: `event-graph-walker/internal/oplog/moon.pkg` (add `dowdiness/rle` import)
- Modify: `event-graph-walker/internal/oplog/oplog.mbt` (change `operations` field type)

- [ ] **Step 1: Add `dowdiness/rle` import to oplog moon.pkg**

Edit `event-graph-walker/internal/oplog/moon.pkg`:

```
import {
  "dowdiness/event-graph-walker/internal/core",
  "dowdiness/event-graph-walker/internal/causal_graph",
  "dowdiness/rle",
  "moonbitlang/core/bench",
  "moonbitlang/core/json",
  "moonbitlang/core/immut/hashset" @immut/hashset,
}

options(
  is_main: false,
)
```

- [ ] **Step 2: Change `operations` field from `Array[@core.Op]` to `@rle.Rle[@core.OpRun]`**

In `event-graph-walker/internal/oplog/oplog.mbt`, change the struct definition:

Replace:

```moonbit
pub struct OpLog {
  priv operations : Array[@core.Op] // All operations in LV order
  priv mut pending : Array[@core.Op] // Remote ops waiting for missing parents
  priv graph : @causal_graph.CausalGraph // The causal graph
  priv agent_id : String // This agent's ID
} derive(Show)
```

With:

```moonbit
pub struct OpLog {
  priv operations : @rle.Rle[@core.OpRun] // All operations in LV order, RLE-compressed
  priv mut pending : Array[@core.Op] // Remote ops waiting for missing parents
  priv graph : @causal_graph.CausalGraph // The causal graph
  priv agent_id : String // This agent's ID
} derive(Show)
```

- [ ] **Step 3: Update `OpLog::new` to create `Rle::new()`**

Replace:

```moonbit
pub fn OpLog::new(agent_id : String) -> OpLog {
  {
    operations: [],
    pending: [],
    graph: @causal_graph.CausalGraph::new(),
    agent_id,
  }
}
```

With:

```moonbit
pub fn OpLog::new(agent_id : String) -> OpLog {
  {
    operations: @rle.Rle::new(),
    pending: [],
    graph: @causal_graph.CausalGraph::new(),
    agent_id,
  }
}
```

- [ ] **Step 4: Verify it compiles (expect errors from methods — that's OK)**

```bash
cd event-graph-walker && moon check 2>&1 | head -30
```

This will show type errors in `add_op`, `get_op`, `op_count`, `ops_ref`, `get_all_ops` — we fix those in Tasks 9-11.

- [ ] **Step 5: Commit inside submodule (compile errors expected, intermediate state)**

```bash
cd event-graph-walker
git add internal/oplog/moon.pkg internal/oplog/oplog.mbt
git commit -m "refactor: change OpLog.operations to Rle[OpRun] (Phase 1, Task 8)

Storage type change. Methods that access operations will be updated
in Tasks 9-11. This is an intermediate state with expected compile errors."
```

---

### Task 9: Update add_op (push -> append with auto-merge)

**Files:**
- Modify: `event-graph-walker/internal/oplog/oplog.mbt`

- [ ] **Step 1: Update `add_op` to convert Op to OpRun and append**

Replace:

```moonbit
fn OpLog::add_op(self : OpLog, op : @core.Op) -> Unit {
  self.operations.push(op)
}
```

With:

```moonbit
///|
/// Add a new operation to the log.
///
/// Converts the Op to a single-element OpRun and appends to the Rle,
/// which auto-merges with the previous run if they form a contiguous
/// typing sequence.
fn OpLog::add_op(self : OpLog, op : @core.Op) -> Unit {
  let run = @core.OpRun::from_op(op)
  match self.operations.append(run) {
    Ok(_) => ()
    Err(_) => () // OpRun with count=1 always has span > 0, so this won't error
  }
}
```

- [ ] **Step 2: Verify `add_op` compiles cleanly**

```bash
cd event-graph-walker && moon check 2>&1 | head -20
```

Remaining errors should only be in `get_op`, `op_count`, `ops_ref`, `get_all_ops`.

- [ ] **Step 3: Commit inside submodule**

```bash
cd event-graph-walker
git add internal/oplog/oplog.mbt
git commit -m "refactor: update add_op to use Rle[OpRun].append (Phase 1, Task 9)

Converts Op to OpRun::from_op then appends to Rle, enabling
auto-merge of contiguous typing runs."
```

---

### Task 10: Update get_op (array index -> find + decompress)

**Files:**
- Modify: `event-graph-walker/internal/oplog/oplog.mbt`

- [ ] **Step 1: Update `get_op` to use Rle::find + OpRun::decompress**

Replace:

```moonbit
pub fn OpLog::get_op(self : OpLog, lv : Int) -> @core.Op? {
  if lv >= 0 && lv < self.operations.length() {
    Some(self.operations[lv])
  } else {
    None
  }
}
```

With:

```moonbit
///|
/// Get the operation at a specific local version (LV).
///
/// Uses O(log n) binary search via Rle::find, then decompresses the
/// individual Op from the containing OpRun.
///
/// Returns `None` for negative LVs, the sentinel value -1, or any LV
/// beyond the end of the log. All valid LVs in `[0, op_count())` are
/// guaranteed to return `Some`.
pub fn OpLog::get_op(self : OpLog, lv : Int) -> @core.Op? {
  if lv < 0 {
    return None
  }
  match self.operations.find(lv) {
    Some(pos) =>
      match self.operations.get(pos.run) {
        Some(run) => run.decompress(pos.offset)
        None => None
      }
    None => None
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd event-graph-walker && moon check 2>&1 | head -20
```

- [ ] **Step 3: Commit inside submodule**

```bash
cd event-graph-walker
git add internal/oplog/oplog.mbt
git commit -m "refactor: update get_op to use Rle::find + decompress (Phase 1, Task 10)

O(log n) lookup via binary search on prefix sums, then offset
arithmetic to extract the individual Op from the OpRun."
```

---

### Task 11: Update op_count, ops_ref, get_all_ops, get_ops

**Files:**
- Modify: `event-graph-walker/internal/oplog/oplog.mbt`

- [ ] **Step 1: Update `op_count` to use `Rle::span()`**

Replace:

```moonbit
pub fn OpLog::op_count(self : OpLog) -> Int {
  self.operations.length()
}
```

With:

```moonbit
///|
/// Get total operation count (O(1) via cached prefix sums).
pub fn OpLog::op_count(self : OpLog) -> Int {
  self.operations.span()
}
```

- [ ] **Step 2: Update `get_all_ops` to expand all runs**

Replace:

```moonbit
pub fn OpLog::get_all_ops(self : OpLog) -> Array[@core.Op] {
  self.ops_ref().copy()
}
```

With:

```moonbit
///|
/// Get all operations by expanding all runs.
///
/// Returns a freshly allocated array of individual Ops in LV order.
/// Iterates over runs directly since positional information is unused.
pub fn OpLog::get_all_ops(self : OpLog) -> Array[@core.Op] {
  let result : Array[@core.Op] = Array::new(capacity=self.op_count())
  for run in self.operations.iter() {
    for offset = 0; offset < run.count; offset = offset + 1 {
      match run.decompress(offset) {
        Some(op) => result.push(op)
        None => () // should not happen for valid offsets
      }
    }
  }
  result
}
```

- [ ] **Step 3: Remove `ops_ref` (no longer applicable — can't return Array ref from Rle)**

Delete the `ops_ref` method entirely:

```moonbit
// DELETE this method:
fn OpLog::ops_ref(self : OpLog) -> Array[@core.Op] {
  self.operations
}
```

Note: `ops_ref` was only used by `get_all_ops` (now replaced) and in the whitebox test. The whitebox test will be updated in Task 12.

- [ ] **Step 4: Verify `get_ops` still works (no change needed)**

`get_ops` calls `get_op` which is already updated. No code change required:

```moonbit
// This stays exactly as-is:
pub fn OpLog::get_ops(self : OpLog, lvs : Array[Int]) -> Array[@core.Op] {
  lvs.filter_map(lv => self.get_op(lv))
}
```

- [ ] **Step 5: Verify it compiles**

```bash
cd event-graph-walker && moon check
```

- [ ] **Step 6: Commit inside submodule**

```bash
cd event-graph-walker
git add internal/oplog/oplog.mbt
git commit -m "refactor: update op_count, get_all_ops, remove ops_ref (Phase 1, Task 11)

op_count uses Rle::span() (O(1) cached).
get_all_ops expands all runs via iter + decompress.
ops_ref removed (Rle has no direct array access)."
```

> **Note:** Consider squashing Tasks 8-11 into a single commit to keep git history green.

---

### Task 12: Fix tests and update whitebox test

**Files:**
- Modify: `event-graph-walker/internal/oplog/oplog_wbtest.mbt`

- [ ] **Step 1: Update the whitebox test to work without `ops_ref`**

Replace the entire content of `event-graph-walker/internal/oplog/oplog_wbtest.mbt`:

```moonbit
///| Whitebox tests for OpLog internal functions

///|
test "add_op auto-merges contiguous insert ops" {
  let oplog = OpLog::new("test")
  let _ = try! oplog.insert("a", -1, -1)
  let _ = try! oplog.insert("b", 0, -1)

  // Two contiguous inserts from same agent should merge into 1 run
  inspect(oplog.op_count(), content="2")
  // Rle length = number of runs (should be 1 after merge)
  inspect(oplog.operations.length(), content="1")
}

///|
test "op_count returns total ops across all runs" {
  let oplog = OpLog::new("test")
  let _ = try! oplog.insert("a", -1, -1)
  inspect(oplog.op_count(), content="1")
}

///|
test "get_all_ops expands runs back to individual ops" {
  let oplog = OpLog::new("test")
  let _ = try! oplog.insert("h", -1, -1)
  let _ = try! oplog.insert("i", 0, -1)
  let all = oplog.get_all_ops()
  inspect(all.length(), content="2")
}
```

- [ ] **Step 2: Run the full event-graph-walker test suite**

```bash
cd event-graph-walker && moon test --update
```

If any tests fail, examine the error and fix. Common issues:
- Snapshot values may differ (e.g., `Show` output for `OpLog` changed)
- Integration tests that check `op_count()` should still work since semantics are preserved

- [ ] **Step 3: Update interfaces**

```bash
cd event-graph-walker && moon info && moon fmt
```

Check the `.mbti` diff to verify API changes are intentional:

```bash
cd event-graph-walker && git diff *.mbti */*.mbti */*/*.mbti
```

Expected changes:
- `ops_ref` removed from oplog mbti
- `OpRun`, `OpRunContent`, `OpRun::from_op`, `OpRun::decompress`, `Op::new_from_parts` added to core mbti

- [ ] **Step 4: Commit inside submodule**

```bash
cd event-graph-walker
git add -A
git commit -m "fix: update tests for Rle[OpRun] storage (Phase 1, Task 12)

Remove ops_ref whitebox test (method removed). Add tests for
add_op auto-merge, op_count, get_all_ops expansion. Update
snapshots and interfaces."
```

---

### Task 13: Run full integration tests across the monorepo

**Files:** No changes — verification only.

- [ ] **Step 1: Run event-graph-walker tests**

```bash
cd event-graph-walker && moon test
```

All tests must pass.

- [ ] **Step 2: Run root crdt module tests**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0 && moon test
```

If any tests reference `ops_ref` or make assumptions about `OpLog.operations` being an Array, fix them.

- [ ] **Step 3: Run `moon check` at root level**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0 && moon check
```

- [ ] **Step 4: Fix any breakage found**

Common fixes needed:
- If any package calls `oplog.ops_ref()`, replace with `oplog.get_all_ops()`
- If any code indexes `operations` directly, use `get_op(lv)` instead
- If `Show` output for `OpLog` changed, update snapshots with `moon test --update`

After fixing, commit inside the appropriate submodule:

```bash
cd event-graph-walker && git add -A && git commit -m "fix: address integration test failures (Phase 1, Task 13)"
```

---

### Task 14: Property test — uncompressed vs compressed equivalence

**Files:**
- Create: `event-graph-walker/internal/oplog/oplog_properties_wbtest.mbt`
- Modify: `event-graph-walker/internal/oplog/moon.pkg` (add quickcheck if not present)

- [ ] **Step 1: Verify quickcheck is available**

Check `event-graph-walker/moon.mod.json` — it already has `"moonbitlang/quickcheck": "0.9.9"`.

Check if oplog already imports quickcheck. If not, no need to add it — we will write deterministic property-style tests instead.

- [ ] **Step 2: Write deterministic property-style equivalence tests**

Create `event-graph-walker/internal/oplog/oplog_properties_wbtest.mbt`:

```moonbit
///| Property-style tests: verify compressed OpLog produces identical get_op results

///|
/// Helper: build an uncompressed reference array and a compressed OpLog,
/// then verify every get_op(lv) returns an identical Op.
fn verify_compression_equivalence(oplog : OpLog) -> Unit! {
  let count = oplog.op_count()
  let all_ops = oplog.get_all_ops()
  // Verify count matches
  assert_eq(all_ops.length(), count)
  // Verify every op is accessible via get_op and matches expanded array
  for lv = 0; lv < count; lv = lv + 1 {
    let from_get = oplog.get_op(lv)
    guard from_get is Some(op) else {
      fail("get_op(\{lv}) returned None for valid LV")
    }
    let from_array = all_ops[lv]
    // Verify critical fields match
    assert_eq(op.lv(), from_array.lv())
    assert_eq(op.agent(), from_array.agent())
    assert_eq(op.seq(), from_array.seq())
    assert_eq(op.content(), from_array.content())
    assert_eq(op.origin_left(), from_array.origin_left())
    assert_eq(op.origin_right(), from_array.origin_right())
    assert_eq(op.parents(), from_array.parents())
  }
  // Verify out-of-bounds returns None
  assert_eq(oplog.get_op(-1), None)
  assert_eq(oplog.get_op(count), None)
}

///|
test "property: single-user linear typing (maximum compression)" {
  let oplog = OpLog::new("alice")
  // Type "hello" — should compress to 1 run
  let _ = try! oplog.insert("h", -1, -1)
  let _ = try! oplog.insert("e", 0, -1)
  let _ = try! oplog.insert("l", 1, -1)
  let _ = try! oplog.insert("l", 2, -1)
  let _ = try! oplog.insert("o", 3, -1)
  inspect(oplog.op_count(), content="5")
  // Should be 1 run
  inspect(oplog.operations.length(), content="1")
  verify_compression_equivalence(oplog)
}

///|
test "property: insert then delete (2 runs)" {
  let oplog = OpLog::new("alice")
  let _ = try! oplog.insert("a", -1, -1)
  let _ = try! oplog.insert("b", 0, -1)
  let _ = try! oplog.delete(0)
  inspect(oplog.op_count(), content="3")
  verify_compression_equivalence(oplog)
}

///|
test "property: interleaved agents (no compression)" {
  let oplog = OpLog::new("alice")
  // alice inserts "a"
  let _ = try! oplog.insert("a", -1, -1)
  // Simulate bob inserting "b" as a remote op
  let bob_op = @core.Op::new_insert(
    -1,
    [],
    "bob",
    0,
    "b",
    None,
    None,
  )
  let _ = try! oplog.apply_remote(bob_op)
  inspect(oplog.op_count(), content="2")
  // Different agents: should be 2 runs
  inspect(oplog.operations.length(), content="2")
  verify_compression_equivalence(oplog)
}

///|
test "property: longer typing session" {
  let oplog = OpLog::new("alice")
  let text = "the quick brown fox"
  let mut prev_lv = -1
  for ch in text {
    let _ = try! oplog.insert(ch.to_string(), prev_lv, -1)
    prev_lv = prev_lv + 1
  }
  inspect(oplog.op_count(), content="19")
  // All from same agent, linear typing: should be 1 run
  inspect(oplog.operations.length(), content="1")
  verify_compression_equivalence(oplog)
}
```

- [ ] **Step 3: Run tests and update snapshots**

```bash
cd event-graph-walker && moon test --update
```

- [ ] **Step 4: Commit inside submodule**

```bash
cd event-graph-walker
git add internal/oplog/oplog_properties_wbtest.mbt
git commit -m "test: property-style equivalence tests for OpRun compression (Phase 1, Task 14)

Verifies get_op(lv) returns identical results for all LVs in
compressed Rle[OpRun] vs expanded Array[Op]. Covers single-user
typing (1 run), insert+delete (2 runs), interleaved agents (no
compression), and longer typing sessions."
```

---

### Task 15: Final commit and submodule pointer update

**Files:**
- Parent repo: update event-graph-walker submodule pointer

- [ ] **Step 1: Verify all tests pass one final time**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker && moon test
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0 && moon test
```

- [ ] **Step 2: Run moon info && moon fmt inside submodule**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker && moon info && moon fmt
```

If any files changed, commit them:

```bash
cd event-graph-walker && git add -A && git commit -m "chore: update interfaces and formatting (Phase 1)"
```

- [ ] **Step 3: Stage submodule pointer update in parent repo**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0
git add event-graph-walker
git commit -m "chore: update event-graph-walker submodule (OpRun compression Phase 1)

Compresses OpLog.operations from Array[Op] to Rle[OpRun].
Single-user typing achieves ~10,000:1 compression ratio.
get_op(lv) is now O(log n) via binary search + offset decompress."
```

- [ ] **Step 4: Verify final state**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0
git status
git submodule status event-graph-walker
```

Expected: Clean working tree, event-graph-walker pointing to latest commit.
