// S3 capability-dispatch gate benchmark (architecture redesign proposal
// § Notes unknown 3). Measures the cost of routing the handle_text_intent
// hot path (SyncEditor::apply_text_edit) through a capability record of
// closures — the lang/runtime SPI shape — against today's direct method
// call. Two layers:
//   1. realistic keystroke pairs on a JSON document (full edit pipeline)
//   2. isolated call-shape microbench bounding the per-call indirection
// Run with: moon bench --release -p dowdiness/canopy/lang/json/companion

///|
/// Mirrors the S3 capability-record shape: hot text ops as mandatory
/// closure fields plus one optional field (the LanguageCapabilities
/// pattern) to measure the per-call Option unwrap.
priv struct TextOpsCaps {
  apply_text_edit : (Int, Int, String, Int) -> Unit
  apply_text_edit_opt : ((Int, Int, String, Int) -> Unit)?
}

///|
fn make_text_ops_caps(
  editor : @editor.SyncEditor[@json.JsonValue],
) -> TextOpsCaps {
  {
    apply_text_edit: fn(from, del, ins, ts) {
      editor.apply_text_edit(from, del, ins, ts)
    },
    apply_text_edit_opt: Some(fn(from, del, ins, ts) {
      editor.apply_text_edit(from, del, ins, ts)
    }),
  }
}

///|
priv enum DispatchMode {
  Direct
  CapsField
  CapsOptField
}

///|
/// Realistic hot path: alternating insert/delete keystroke pairs through
/// apply_text_edit, rotating the edit position across member-value spots
/// so no single operand stays JIT-hot. The capability record is built ONCE
/// before the loop (S3 stores it in the handle at construction time).
fn run_text_intent_dispatch_bench(
  b : @bench.T,
  member_count : Int,
  mode : DispatchMode,
) -> Unit {
  let source = json_bench_object(member_count)
  let editor = new_json_editor("bench")
  editor.set_text(source)
  ignore(editor.get_proj_node())
  ignore(editor.get_source_map())
  let caps = make_text_ops_caps(editor)
  // Edit positions: just after the value digit of 4 members spread across
  // the doc. Member i line: `  "k<i>": <i>` — find positions by scanning.
  let positions : Array[Int] = []
  let quarter = member_count / 4
  for q in 0..<4 {
    let idx = q * quarter
    let needle = "\"k\{idx}\": "
    let mut found = -1
    for p in 0..<(source.length() - needle.length()) {
      if source.view(start_offset=p, end_offset=p + needle.length()) ==
        needle.view() {
        found = p + needle.length()
        break
      }
    }
    guard found >= 0 else { abort("bench setup: member k\{idx} not found") }
    positions.push(found)
  }
  let mut i = 0
  let mut inserted = false
  b.bench(fn() {
    let pos = positions[i / 2 % positions.length()]
    let (del, ins) = if inserted { (1, "") } else { (0, "1") }
    match mode {
      Direct => editor.apply_text_edit(pos, del, ins, i)
      CapsField => (caps.apply_text_edit)(pos, del, ins, i)
      CapsOptField =>
        match caps.apply_text_edit_opt {
          Some(f) => f(pos, del, ins, i)
          None => ()
        }
    }
    inserted = !inserted
    i += 1
    b.keep(i)
  })
}

///|
test "text intent dispatch - direct call (100 members)" (b : @bench.T) {
  run_text_intent_dispatch_bench(b, 100, Direct)
}

///|
test "text intent dispatch - caps field (100 members)" (b : @bench.T) {
  run_text_intent_dispatch_bench(b, 100, CapsField)
}

///|
test "text intent dispatch - caps optional field (100 members)" (b : @bench.T) {
  run_text_intent_dispatch_bench(b, 100, CapsOptField)
}

///|
test "text intent dispatch - direct call (1000 members)" (b : @bench.T) {
  run_text_intent_dispatch_bench(b, 1000, Direct)
}

///|
test "text intent dispatch - caps field (1000 members)" (b : @bench.T) {
  run_text_intent_dispatch_bench(b, 1000, CapsField)
}

///|
test "text intent dispatch - caps optional field (1000 members)" (b : @bench.T) {
  run_text_intent_dispatch_bench(b, 1000, CapsOptField)
}

// ── Isolated call-shape microbench ──────────────────────────────────────
// Bounds the absolute per-call indirection cost with a trivial body so the
// dispatch itself dominates. 1000 calls per iteration, varied operands.

///|
fn dispatch_probe_work(a : Int, c : Int, s : String, t : Int) -> Int {
  a + c + s.length() + t
}

///|
priv struct ProbeCaps {
  f : (Int, Int, String, Int) -> Int
  g : ((Int, Int, String, Int) -> Int)?
}

///|
const PROBE_CALLS = 1000

///|
test "isolated dispatch - direct call x1000" (b : @bench.T) {
  b.bench(fn() {
    let mut acc = 0
    for i in 0..<PROBE_CALLS {
      acc += dispatch_probe_work(i, i + 1, "x", i * 3)
    }
    b.keep(acc)
  })
}

///|
test "isolated dispatch - caps field x1000" (b : @bench.T) {
  let caps : ProbeCaps = {
    f: fn(a, c, s, t) { dispatch_probe_work(a, c, s, t) },
    g: None,
  }
  b.bench(fn() {
    let mut acc = 0
    for i in 0..<PROBE_CALLS {
      acc += (caps.f)(i, i + 1, "x", i * 3)
    }
    b.keep(acc)
  })
}

///|
test "isolated dispatch - caps optional field x1000" (b : @bench.T) {
  let caps : ProbeCaps = {
    f: fn(a, c, s, t) { dispatch_probe_work(a, c, s, t) },
    g: Some(fn(a, c, s, t) { dispatch_probe_work(a, c, s, t) }),
  }
  b.bench(fn() {
    let mut acc = 0
    for i in 0..<PROBE_CALLS {
      match caps.g {
        Some(f) => acc += f(i, i + 1, "x", i * 3)
        None => ()
      }
    }
    b.keep(acc)
  })
}
