///|
pub extern "js" fn cli_mode() -> String =
  #|() => {
  #|  const argv =
  #|    typeof process !== "undefined" && Array.isArray(process.argv)
  #|      ? process.argv.slice(2)
  #|      : [];
  #|  const mode = argv.find((arg) => arg.length > 0) ?? "all";
  #|  return mode.toLowerCase();
  #|}

///|
pub extern "js" fn cli_iterations() -> Int? =
  #|() => {
  #|  const argv =
  #|    typeof process !== "undefined" && Array.isArray(process.argv)
  #|      ? process.argv.slice(2)
  #|      : [];
  #|  // argv[1]: if it's a number, it's the iteration override
  #|  if (argv.length >= 2) {
  #|    const p1 = Number.parseInt(argv[1], 10);
  #|    if (Number.isFinite(p1) && p1 > 0) return p1;
  #|  }
  #|  // argv[2]: if argv[1] was a filter string, check argv[2]
  #|  if (argv.length >= 3) {
  #|    const p2 = Number.parseInt(argv[2], 10);
  #|    if (Number.isFinite(p2) && p2 > 0) return p2;
  #|  }
  #|  return undefined;
  #|}

///|
pub extern "js" fn cli_operation_filter() -> String? =
  #|() => {
  #|  const argv =
  #|    typeof process !== "undefined" && Array.isArray(process.argv)
  #|      ? process.argv.slice(2)
  #|      : [];
  #|  if (argv.length < 2) return undefined;
  #|  const parsed = Number.parseInt(argv[1], 10);
  #|  if (Number.isFinite(parsed) && parsed > 0) return undefined;
  #|  return argv[1].replace(/-/g, " ");
  #|}

// ── Types ────────────────────────────────────────────────────────────

///|
enum Operation {
  LegacySetTextRefresh
  IncrementalEagerRefresh
  DeferredTextInput
  DeferredFullCycle
}

///|
struct BenchmarkCase {
  scenario : String
  label : String
  operation : Operation
  iterations : Int
  timeout_ms : Int?
}

///|
struct BenchmarkResult {
  scenario : String
  label : String
  iterations : Int
  completed : Int
  timed_out : Bool
  total_ms : Int
  average_ms : Int
  phases : Array[(String, Int)]
}

// ── Source generation ────────────────────────────────────────────────

///|
fn benchmark_source(let_count : Int, tail_literal : String) -> String {
  let segments : Array[String] = []
  for i = 0; i < let_count - 1; i = i + 1 {
    segments.push("let x\{i} = 0 in ")
  }
  segments.push("let x\{let_count - 1} = \{tail_literal} in x\{let_count - 1}")
  segments.join("")
}

// ── Case registry ───────────────────────────────────────────────────

///|
fn medium_cases(iterations : Int) -> Array[BenchmarkCase] {
  [
    {
      scenario: "medium",
      label: "legacy set_text + refresh",
      operation: LegacySetTextRefresh,
      iterations,
      timeout_ms: None,
    },
    {
      scenario: "medium",
      label: "incremental apply_text_edit + refresh",
      operation: IncrementalEagerRefresh,
      iterations,
      timeout_ms: None,
    },
    {
      scenario: "medium",
      label: "deferred text input only",
      operation: DeferredTextInput,
      iterations,
      timeout_ms: None,
    },
    {
      scenario: "medium",
      label: "deferred full cycle",
      operation: DeferredFullCycle,
      iterations,
      timeout_ms: None,
    },
  ]
}

///|
fn large_cases(iterations : Int) -> Array[BenchmarkCase] {
  [
    {
      scenario: "large",
      label: "deferred text input only",
      operation: DeferredTextInput,
      iterations,
      timeout_ms: Some(30000),
    },
    {
      scenario: "large",
      label: "deferred full cycle",
      operation: DeferredFullCycle,
      iterations,
      timeout_ms: Some(60000),
    },
  ]
}

// ── Operation runner ────────────────────────────────────────────────

///|
fn run_operation(
  op : Operation,
  session : @app.BenchmarkSession,
  text : String,
) -> @app.BenchmarkMeasurement {
  match op {
    DeferredFullCycle => session.deferred_full_cycle_timed(text)
    LegacySetTextRefresh => {
      let t0 = @app.now_ms()
      session.legacy_set_text_refresh(text)
      { total_ms: @app.now_ms() - t0, phases: [] }
    }
    IncrementalEagerRefresh => {
      let t0 = @app.now_ms()
      session.incremental_eager_refresh(text)
      { total_ms: @app.now_ms() - t0, phases: [] }
    }
    DeferredTextInput => {
      let t0 = @app.now_ms()
      session.deferred_text_input(text)
      { total_ms: @app.now_ms() - t0, phases: [] }
    }
  }
}

// ── Phase averaging ─────────────────────────────────────────────────

///|
fn average_phases(
  measurements : Array[@app.BenchmarkMeasurement],
) -> Array[(String, Int)] {
  if measurements.is_empty() || measurements[0].phases.is_empty() {
    return []
  }
  let n = measurements.length()
  let result : Array[(String, Int)] = []
  for i = 0; i < measurements[0].phases.length(); i = i + 1 {
    let (name, _) = measurements[0].phases[i]
    let mut sum = 0
    for m in measurements {
      sum = sum + m.phases[i].1
    }
    result.push((name, sum / n))
  }
  result
}

// ── Output formatting ───────────────────────────────────────────────

///|
fn format_phases(phases : Array[(String, Int)]) -> String {
  if phases.is_empty() {
    return ""
  }
  let parts : Array[String] = []
  for phase in phases {
    parts.push(" \{phase.0}=\{phase.1}")
  }
  parts.join("")
}

///|
fn emit_json(result : BenchmarkResult) -> Unit {
  let phases_json = if result.phases.is_empty() {
    ""
  } else {
    let parts : Array[String] = []
    for phase in result.phases {
      parts.push("\"\{phase.0}\":\{phase.1}")
    }
    let joined = parts.join(",")
    ",\{joined}"
  }
  println(
    "{\"scenario\":\"\{result.scenario}\",\"label\":\"\{result.label}\",\"iterations\":\{result.iterations},\"completed\":\{result.completed},\"timed_out\":\{result.timed_out},\"total_ms\":\{result.total_ms},\"average_ms\":\{result.average_ms}\{phases_json}}",
  )
}

// ── Case runner ─────────────────────────────────────────────────────

///|
fn run_case(
  case_ : BenchmarkCase,
  source : String,
  edited_source : String,
) -> BenchmarkResult {
  // START line
  let timeout_str = match case_.timeout_ms {
    Some(ms) => " timeout_ms=\{ms}"
    None => ""
  }
  println(
    "START \{case_.scenario} \{case_.label} iterations=\{case_.iterations}\{timeout_str}",
  )
  // Warmup
  let warmup = @app.BenchmarkSession::new(source)
  let _ = run_operation(case_.operation, warmup, edited_source)
  // Measure
  let measurements : Array[@app.BenchmarkMeasurement] = []
  let mut total_elapsed = 0
  let mut timed_out = false
  let mut i = 0
  while i < case_.iterations && not(timed_out) {
    let base = if i % 2 == 0 { source } else { edited_source }
    let next = if i % 2 == 0 { edited_source } else { source }
    let session = @app.BenchmarkSession::new(base)
    let m = run_operation(case_.operation, session, next)
    total_elapsed = total_elapsed + m.total_ms
    measurements.push(m)
    match case_.timeout_ms {
      Some(budget) => if total_elapsed > budget { timed_out = true }
      None => ()
    }
    i = i + 1
  }
  let completed = measurements.length()
  let average = if completed > 0 { total_elapsed / completed } else { 0 }
  let avg_phases = average_phases(measurements)
  // DONE / TIMEOUT line
  if timed_out {
    println(
      "TIMEOUT \{case_.scenario} \{case_.label} elapsed_ms=\{total_elapsed} completed=\{completed}/\{case_.iterations}",
    )
  } else {
    let phase_str = format_phases(avg_phases)
    println(
      "DONE  \{case_.scenario} \{case_.label} total=\{total_elapsed} avg=\{average}\{phase_str}",
    )
  }
  {
    scenario: case_.scenario,
    label: case_.label,
    iterations: case_.iterations,
    completed,
    timed_out,
    total_ms: total_elapsed,
    average_ms: average,
    phases: avg_phases,
  }
}

// ── Main ────────────────────────────────────────────────────────────

///|
fn main {
  let mode = cli_mode()
  let iterations = cli_iterations()
  let op_filter = cli_operation_filter()
  let medium_source = benchmark_source(80, "0")
  let medium_edited = benchmark_source(80, "1")
  let large_source = benchmark_source(320, "0")
  let large_edited = benchmark_source(320, "1")
  // Build case list
  let default_iters = match iterations {
    Some(n) => n
    None => 5
  }
  let mut cases : Array[BenchmarkCase] = []
  match mode {
    "medium" => cases = medium_cases(default_iters)
    "large" => cases = large_cases(default_iters)
    "all" => {
      for c in medium_cases(default_iters) {
        cases.push(c)
      }
      for c in large_cases(default_iters) {
        cases.push(c)
      }
    }
    _ => {
      println("Unknown mode '\{mode}', expected one of: all, medium, large")
      return
    }
  }
  // Apply operation filter
  match op_filter {
    Some(filter) => cases = cases.filter(fn(c) { c.label.contains(filter) })
    None => ()
  }
  // Header
  println("Rabbita performance report")
  println("Source sizes: medium=80 lets, large=320 lets")
  println("Mode: \{mode}")
  match iterations {
    Some(n) => println("Iterations override: \{n}")
    None => ()
  }
  match op_filter {
    Some(filter) => println("Operation filter: \{filter}")
    None => ()
  }
  println("Cases: \{cases.length()}")
  println("")
  // Run cases
  let results : Array[BenchmarkResult] = []
  for case_ in cases {
    let (source, edited) = if case_.scenario == "medium" {
      (medium_source, medium_edited)
    } else {
      (large_source, large_edited)
    }
    results.push(run_case(case_, source, edited))
    println("")
  }
  // JSON summary
  println("--- JSON ---")
  for result in results {
    emit_json(result)
  }
}
