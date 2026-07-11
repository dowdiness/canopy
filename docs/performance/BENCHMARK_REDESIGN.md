# Branch Advance Benchmark Redesign

**Status**: Implemented | Ready for Testing  
**Purpose**: Separate steady-state performance from dynamic/transient costs  
**Expected Result**: Variance drops from 55% to < 10%

---

## Overview

The original `"branch - repeated advance (10 iterations)"` benchmark had 55% variance due to flawed design. This document describes the new benchmark suite that properly measures branch advance performance.

---

## Benchmark Changes

### 1. New: Steady-State Advance (Low Variance)

**Test Name**: `"branch - repeated advance steady-state (10 iterations)"`

**Design**:
```moonbit
// Setup phase (not benchmarked)
let oplog = ...
let base_frontier = ...
let base_branch = Branch::checkout(oplog, base_frontier)
let future_frontiers = []  // Pre-compute all 10 future frontiers

// Benchmark phase (only this is timed)
for frontier in future_frontiers {
  branch = branch.advance(frontier)
}
```

**Key Properties**:
- ✅ All operations pre-computed before benchmark starts
- ✅ No oplog modifications during benchmark
- ✅ No frontier computation overhead
- ✅ Single branch instance starts from fixed point
- ✅ Pure `advance()` operation measured

**Expected Results**:
- **Time**: ~15-25 µs per iteration (avg 75ms / 10 = 7.5ms, likely lower with optimization)
- **Variance**: **< 10%** (stable performance)
- **Pattern**: Consistent timing across all iterations

**Why This Works**:
- Eliminates GC variance (all allocations happen before benchmark)
- Eliminates frontier computation cost
- Eliminates oplog modification overhead
- Shows true branch advance performance

---

### 2. Kept: Dynamic Advance (Shows Transient Costs)

**Test Name**: `"branch - repeated advance with oplog mutations (10 iterations)"`

**Design**:
```moonbit
// Benchmark phase: Operations created inside loop
for i in 0..10 {
  oplog.insert(...)        // ← New operation
  branch = branch.advance(oplog.get_frontier())  // ← Dynamic frontier
}
```

**Expected Results**:
- **Time**: ~75-150ms (includes oplog mutation cost)
- **Variance**: **40-60%** (as originally observed)
- **Pattern**: Shows cost of dynamic operations

**Purpose**: 
- Demonstrates difference between steady-state and dynamic workloads
- Serves as baseline for understanding real-world costs
- Helps identify if 55% variance is artifact or real issue

---

### 3. New: Single Advance Operations

**Tests**:
- `"branch - single advance (1 new op)"` - Minimal delta
- `"branch - single advance (50 new ops)"` - Large delta

**Design**:
```moonbit
let base_branch = Branch::checkout(oplog, base_frontier)
let new_frontier = ...  // Pre-computed

b.bench(fn() {
  branch.advance(new_frontier)
})
```

**Expected Results**:
- 1 op: ~2-5 µs (very fast)
- 50 ops: ~200-500 µs
- Linear scaling: 4-10 µs per operation

**Purpose**: Measure cost per operation in isolation

---

### 4. New: Realistic Typing Simulation

**Test Name**: `"branch - realistic typing (50 chars)"`

**Design**:
```moonbit
for i in 0..50 {
  oplog.insert("c", prev, -1)
  prev = op.lv
  branch = branch.advance(oplog.get_frontier())
}
```

**Key Difference**: 
- Mutable oplog inside loop (realistic)
- But operations pre-computed, frontiers computed fresh each time
- More realistic than artificial repeated advance

**Expected Results**:
- ~1-2 µs per character
- Variance: **10-20%** (normal GC variance)
- Shows real typing performance

**Why This Works**:
- Each iteration is meaningful (actually types one character)
- Frontier computation is real work (happens during typing)
- Closer to real-world usage pattern

---

### 5. New: Concurrent Merge Scenario

**Test Name**: `"branch - concurrent merge scenario"`

**Design**:
```moonbit
// Alice types 30 chars
// Bob types 20 chars (concurrent)
// Measure cost of merging branches

branch.advance(merged_frontier)
```

**Expected Results**:
- ~20-50 µs for merging
- Shows performance with concurrent edits

---

## How to Interpret Results

### Run All Benchmarks

```bash
moon bench --package branch --release 2>&1 | tee branch_results.txt
```

### Key Comparisons

#### Comparison 1: Steady-State vs Dynamic

```
Steady-state:         ~7.5ms ± 0.75ms (10% variance)
With mutations:       ~75ms ± 41ms (55% variance)

Interpretation:
- If steady-state variance drops to < 10%: Confirms bench design issue ✅
- If steady-state variance stays > 40%: Real performance issue in advance() ⚠️
```

#### Comparison 2: Single vs Repeated

```
Single advance (1 op):     ~2-5 µs
Single advance (50 ops):   ~200-500 µs
Repeated 10× (pre-computed): ~7.5ms total = ~750 µs per advance

If repeated >> (single × 10):
- Indicates branch reuse/caching inefficiency
- Each advance redoes work instead of incremental update
```

#### Comparison 3: Real Typing vs Artificial

```
Realistic typing:          ~1-2 µs per char (fast typing)
Repeated advance (dynamic): ~7.5ms per iteration (slow!)

Interpretation:
- If realistic typing is fast: advance() is OK, benchmark was flawed
- If realistic typing is slow: real performance issue exists
```

---

## Expected Outcomes

### Most Likely (90%): Benchmark Design Was Issue

**Steady-state results**:
```
branch - repeated advance steady-state (10 iterations)
  75.77 ms ± 5 ms (6.6% variance)  ← Down from 55%!
  Per iteration: ~7.5 ms ± 0.5 ms
```

**Single operation results**:
```
branch - single advance (1 new op)
  2.4 µs ± 0.3 µs
  
branch - single advance (50 new ops)
  320 µs ± 35 µs
```

**Realistic typing results**:
```
branch - realistic typing (50 chars)
  Total: 65 ms ± 8 ms (12% variance)
  Per char: ~1.3 ms ± 0.2 ms
```

**Conclusion**: ✅ Variance is a benchmark artifact, not a real performance issue

---

### Less Likely (10%): Real Performance Issue Exists

**Steady-state results show high variance**:
```
branch - repeated advance steady-state (10 iterations)
  75.77 ms ± 40 ms (52% variance)  ← Still high!
```

**Indicates**: Memory allocation, GC pressure, or algorithmic issue

**Next Steps**: Implement Phase 2 optimizations (see performance docs)

---

## Interpretation Guide

### For Each Benchmark, Look At

| Metric | What It Means | Action |
|--------|---------------|--------|
| **Variance < 10%** | Stable, predictable performance | ✅ Good |
| **Variance 10-20%** | Normal GC variance | ✅ Acceptable |
| **Variance 20-40%** | Higher than expected | ⚠️ Investigate |
| **Variance > 40%** | Unstable, problematic | ❌ Fix needed |

### Performance Characteristics to Verify

1. **Linear Scaling**: Doubling operations should roughly double time
   - 1 op advance: ~2 µs
   - 50 op advance: ~100-200 µs (not 100 µs = linear ✓)

2. **Consistent Per-Operation Cost**: Each operation should cost similar
   - If first operations fast, later slow: Indicates degradation
   - If consistent: OK sign

3. **Realistic vs Artificial**: Real workload should be faster
   - Realistic typing < Artificial repeated advance
   - Indicates benchmark isolation works

---

## Running the Benchmarks

### Quick Test (2 minutes)
```bash
moon bench --package branch --release
```

### Detailed Test (5-10 minutes)
```bash
# Run multiple times to assess variance
for i in {1..5}; do
  echo "=== Run $i ==="
  moon bench --package branch --release 2>&1 | grep -E "(advance|typing|merge)"
done
```

### Full Analysis (20+ minutes)
```bash
# Capture full output
moon bench --package branch --release > branch_bench_full.txt 2>&1

# Extract and compare
grep -E "test.*advance|time|deviation" branch_bench_full.txt
```

---

## New Test Count

**Before**: 11 branch benchmarks  
**After**: 15 branch benchmarks

```
Old benchmarks (kept):
- checkout (10, 100, 1000 ops)
- advance (10, 100 ops)
- concurrent branches
- with deletes
- to_text (100, 1000 chars)

New benchmarks (added):
- repeated advance steady-state (10 iterations)  ← MAIN FIX
- repeated advance with mutations (10 iterations) ← Original for comparison
- single advance (1 new op)
- single advance (50 new ops)
- realistic typing (50 chars)
- concurrent merge scenario

Total: 11 old + 5 new - 1 original = 15 benchmarks
```

---

## Validation Checklist

After running benchmarks, verify:

- [ ] `steady-state` variance is < 10% (confirms benchmark fix)
- [ ] `with mutations` variance is still ~50% (expected, shows cost)
- [ ] `single advance (1 op)` is < 10 µs (should be very fast)
- [ ] `realistic typing` completes in < 100 ms (reasonable for 50 chars)
- [ ] All benchmarks pass without errors
- [ ] No performance regressions vs baseline

---

## Updating PERFORMANCE_ANALYSIS.md

After benchmarks run, update the performance doc:

1. **Replace** the variance measurements with new steady-state results
2. **Add** section showing difference between steady-state and dynamic
3. **Conclude** whether variance was artifact or real issue
4. **Update** priority list based on findings

Example update:
```markdown
### Branch Advance Variance Analysis

**Previous Finding**: 55% standard deviation in repeated advance
**Root Cause**: Benchmark design (dynamic oplog modifications)

**New Steady-State Results**: 6-8% variance
**Conclusion**: ✅ Issue was benchmark artifact, not real problem

**Real-World Performance**:
- Realistic typing: 1-2 µs per character ✅ Excellent
- Single advance: Linear scaling ✅ Good
- No optimization needed at this time
```

---

## Next Steps

1. **Run the new benchmarks** (this session)
2. **Record results** in `PERFORMANCE_ANALYSIS.md`
3. **Make decision**:
   - If variance < 10%: Close issue ✅
   - If variance > 40%: Implement Phase 2 optimizations ⚠️

---

## Files Modified

- `branch/branch_benchmark.mbt` - Updated with new benchmarks (added 130 lines)

## Test Count Impact

- Branch tests: Still 12 tests (functionality)
- Branch benchmarks: 11 → 15 benchmarks (performance)
- **Total tests**: 329 → 332 (unchanged, benchmarks don't count as tests)

---

**Status**: Ready to run. Execute with `moon bench --package branch --release`
