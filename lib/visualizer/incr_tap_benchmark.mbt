// Incr tap benchmarks — run with: moon bench --release

///|
const SMALL_BENCH_CELL_COUNT = 256

///|
const LARGE_BENCH_CELL_COUNT = 2048

///|
fn make_bench_fanout(
  count : Int,
) -> (Array[@incr.Derived[Int]], RecomputeTap) raise Failure {
  guard count > 0 else {
    abort("benchmark fanout must contain at least one cell")
  }
  let rt = @incr.Runtime()
  let input = @incr.Signal(rt, 0, label="bench_input")
  let memos : Array[@incr.Derived[Int]] = []
  for i in 0..<count {
    memos.push(
      @incr.Derived(
        rt,
        () => input.get() + i,
        label="bench_memo_" + i.to_string(),
      ),
    )
  }
  let tap = RecomputeTap::attach(rt)
  for memo in memos {
    ignore(memo.read_or_abort())
  }
  (memos, tap)
}

///|
fn make_bench_snapshot(count : Int) -> RecomputeSnapshot raise Failure {
  let (memos, tap) = make_bench_fanout(count)
  // Keep the derived handles live while the snapshot discovers the graph.
  ignore(memos.length())
  tap.snapshot()
}

///|
test "bench/incr_tap/snapshot_fanout_256" (b : @bench.T) {
  let (memos, tap) = make_bench_fanout(SMALL_BENCH_CELL_COUNT)
  b.keep(memos.length())
  b.bench(fn() { b.keep(tap.snapshot()) })
}

///|
test "bench/incr_tap/snapshot_fanout_2048" (b : @bench.T) {
  let (memos, tap) = make_bench_fanout(LARGE_BENCH_CELL_COUNT)
  b.keep(memos.length())
  b.bench(fn() { b.keep(tap.snapshot()) })
}

///|
test "bench/incr_tap/to_visual_graph_fanout_256" (b : @bench.T) {
  let snapshot = make_bench_snapshot(SMALL_BENCH_CELL_COUNT)
  b.bench(fn() { b.keep(snapshot.to_visual_graph()) })
}

///|
test "bench/incr_tap/to_visual_graph_fanout_2048" (b : @bench.T) {
  let snapshot = make_bench_snapshot(LARGE_BENCH_CELL_COUNT)
  b.bench(fn() { b.keep(snapshot.to_visual_graph()) })
}
