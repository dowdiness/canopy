///|
extern "js" fn cli_args() -> Array[String] =
  #|() => {
  #|  return typeof process !== "undefined" && Array.isArray(process.argv)
  #|    ? process.argv.slice(2)
  #|    : [];
  #|}

///|
extern "js" fn cli_mode() -> String =
  #|() => {
  #|  const argv =
  #|    typeof process !== "undefined" && Array.isArray(process.argv)
  #|      ? process.argv.slice(2)
  #|      : [];
  #|  const mode = argv.find((arg) => arg.length > 0) ?? "all";
  #|  return mode.toLowerCase();
  #|}

///|
extern "js" fn cli_iterations() -> Int? =
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
extern "js" fn cli_operation_filter() -> String? =
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

///|
extern "js" fn read_file(path : String) -> String =
  #|(path) => {
  #|  const load = (mod) =>
  #|    typeof process.getBuiltinModule === "function"
  #|      ? process.getBuiltinModule(mod)
  #|      : typeof require === "function"
  #|        ? require(mod)
  #|        : undefined;
  #|  const fs = load("node:fs");
  #|  if (!fs) throw new Error("could not load node:fs");
  #|  return fs.readFileSync(path, "utf8");
  #|}

///|
extern "js" fn run_step_subprocess(
  operation_code : String,
  source : String,
  text : String,
  timeout_ms : Int,
) -> String =
  #|(operationCode, source, text, timeoutMs) => {
  #|  if (typeof process === "undefined" || !Array.isArray(process.argv)) {
  #|    throw new Error("perf_report subprocess timeouts require Node.js");
  #|  }
  #|  const load = (mod) =>
  #|    typeof process.getBuiltinModule === "function"
  #|      ? process.getBuiltinModule(mod)
  #|      : typeof require === "function"
  #|        ? require(mod)
  #|        : undefined;
  #|  const childProcess = load("node:child_process");
  #|  const fs = load("node:fs");
  #|  const os = load("node:os");
  #|  if (!childProcess || !fs || !os) {
  #|    throw new Error("perf_report subprocess timeouts require node:child_process, node:fs, node:os");
  #|  }
  #|  const { spawnSync } = childProcess;
  #|  const id = `${process.pid}-${Date.now()}`;
  #|  const sourcePath = `${os.tmpdir()}/perf-source-${id}.txt`;
  #|  const textPath = `${os.tmpdir()}/perf-text-${id}.txt`;
  #|  fs.writeFileSync(sourcePath, source);
  #|  fs.writeFileSync(textPath, text);
  #|  try {
  #|    const scriptPath = process.argv[1];
  #|    const result = spawnSync(
  #|      process.execPath,
  #|      [scriptPath, "__step__", operationCode, sourcePath, textPath],
  #|      {
  #|        cwd: process.cwd(),
  #|        encoding: "utf8",
  #|        timeout: timeoutMs,
  #|        killSignal: "SIGKILL",
  #|        maxBuffer: 1024 * 1024 * 16,
  #|      },
  #|    );
  #|    if (result.error && result.error.code === "ETIMEDOUT") {
  #|      return "TIMEOUT";
  #|    }
  #|    if (result.error) {
  #|      throw result.error;
  #|    }
  #|    if (result.status !== 0) {
  #|      const stderr = typeof result.stderr === "string" ? result.stderr.trim() : "";
  #|      throw new Error(
  #|        `perf_report step subprocess failed for ${operationCode}: ${stderr}`,
  #|      );
  #|    }
  #|    return typeof result.stdout === "string" ? result.stdout.trim() : "";
  #|  } finally {
  #|    try { fs.unlinkSync(sourcePath); } catch {}
  #|    try { fs.unlinkSync(textPath); } catch {}
  #|  }
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
  timeout_elapsed_ms : Int?
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

///|
fn operation_code(op : Operation) -> String {
  match op {
    LegacySetTextRefresh => "legacy_set_text_refresh"
    IncrementalEagerRefresh => "incremental_eager_refresh"
    DeferredTextInput => "deferred_text_input"
    DeferredFullCycle => "deferred_full_cycle"
  }
}

///|
fn operation_from_code(code : String) -> Operation {
  match code {
    "legacy_set_text_refresh" => LegacySetTextRefresh
    "incremental_eager_refresh" => IncrementalEagerRefresh
    "deferred_text_input" => DeferredTextInput
    "deferred_full_cycle" => DeferredFullCycle
    _ => abort("unknown benchmark step operation '\{code}'")
  }
}

///|
fn parse_int_field(text : String, context : String) -> Int {
  @strconv.parse_int(text.trim()) catch {
    _ => abort("invalid integer field for \{context}: '\{text}'")
  }
}

///|
fn split_string(text : String, separator : String) -> Array[String] {
  let parts : Array[String] = []
  for part in text.split(separator) {
    parts.push(part.to_string())
  }
  parts
}

///|
fn parse_step_measurement(output : String) -> @app.BenchmarkMeasurement {
  let trimmed = output.trim().to_string()
  if trimmed == "" {
    abort("benchmark step subprocess returned empty output")
  }
  let lines = split_string(trimmed, "\n")
  let header_parts = split_string(lines[0].trim().to_string(), " ")
  if header_parts.length() != 2 || header_parts[0] != "MEASUREMENT" {
    abort("invalid benchmark step header '\{lines[0]}'")
  }
  let total_parts = split_string(header_parts[1], "=")
  if total_parts.length() != 2 || total_parts[0] != "total_ms" {
    abort("invalid benchmark total field '\{header_parts[1]}'")
  }
  let total_ms = parse_int_field(total_parts[1], "total_ms")
  let phases : Array[(String, Int)] = []
  for i = 1; i < lines.length(); i = i + 1 {
    let line = lines[i].trim().to_string()
    if line == "" {
      continue
    }
    let phase_parts = split_string(line, " ")
    if phase_parts.length() != 2 || phase_parts[0] != "PHASE" {
      abort("invalid benchmark phase line '\{line}'")
    }
    let kv = split_string(phase_parts[1], "=")
    if kv.length() != 2 {
      abort("invalid benchmark phase field '\{phase_parts[1]}'")
    }
    phases.push((kv[0], parse_int_field(kv[1], kv[0])))
  }
  { total_ms, phases }
}

///|
fn emit_step_measurement(measurement : @app.BenchmarkMeasurement) -> Unit {
  println("MEASUREMENT total_ms=\{measurement.total_ms}")
  for phase in measurement.phases {
    println("PHASE \{phase.0}=\{phase.1}")
  }
}

///|
fn run_step_with_deadline(
  op : Operation,
  source : String,
  text : String,
  deadline_ms : Int?,
) -> @app.BenchmarkMeasurement? {
  match deadline_ms {
    None => {
      let session = @app.BenchmarkSession::new(source)
      Some(run_operation(op, session, text))
    }
    Some(deadline) => {
      let remaining_ms = deadline - @app.now_ms()
      if remaining_ms <= 0 {
        return None
      }
      let output = run_step_subprocess(
        operation_code(op),
        source,
        text,
        remaining_ms,
      )
      if output == "TIMEOUT" {
        None
      } else {
        Some(parse_step_measurement(output))
      }
    }
  }
}

///|
fn run_internal_step(args : Array[String]) -> Unit {
  if args.length() != 4 {
    abort("internal perf_report step mode expects 4 arguments")
  }
  let op = operation_from_code(args[1])
  let source = read_file(args[2])
  let text = read_file(args[3])
  let session = @app.BenchmarkSession::new(source)
  emit_step_measurement(run_operation(op, session, text))
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
  let timeout_elapsed_json = match result.timeout_elapsed_ms {
    Some(ms) => "\{ms}"
    None => "null"
  }
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
    "{\"scenario\":\"\{result.scenario}\",\"label\":\"\{result.label}\",\"iterations\":\{result.iterations},\"completed\":\{result.completed},\"timed_out\":\{result.timed_out},\"total_ms\":\{result.total_ms},\"timeout_elapsed_ms\":\{timeout_elapsed_json},\"average_ms\":\{result.average_ms}\{phases_json}}",
  )
}

// ── Case runner ─────────────────────────────────────────────────────

///|
fn run_case(
  case_ : BenchmarkCase,
  source : String,
  edited_source : String,
) -> BenchmarkResult {
  let case_started_at = @app.now_ms()
  let deadline_ms = match case_.timeout_ms {
    Some(timeout_ms) => Some(case_started_at + timeout_ms)
    None => None
  }
  // START line
  let timeout_str = match case_.timeout_ms {
    Some(ms) => " timeout_ms=\{ms}"
    None => ""
  }
  println(
    "START \{case_.scenario} \{case_.label} iterations=\{case_.iterations}\{timeout_str}",
  )
  // Warmup
  let mut timed_out = false
  match
    run_step_with_deadline(case_.operation, source, edited_source, deadline_ms) {
    Some(_) => ()
    None => timed_out = true
  }
  // Measure
  let measurements : Array[@app.BenchmarkMeasurement] = []
  let mut total_elapsed = 0
  let mut i = 0
  while i < case_.iterations && !(timed_out) {
    let base = if i % 2 == 0 { source } else { edited_source }
    let next = if i % 2 == 0 { edited_source } else { source }
    match run_step_with_deadline(case_.operation, base, next, deadline_ms) {
      Some(m) => {
        total_elapsed = total_elapsed + m.total_ms
        measurements.push(m)
      }
      None => timed_out = true
    }
    i = i + 1
  }
  let completed = measurements.length()
  let average = if completed > 0 { total_elapsed / completed } else { 0 }
  let avg_phases = average_phases(measurements)
  let wall_elapsed = @app.now_ms() - case_started_at
  // DONE / TIMEOUT line
  if timed_out {
    println(
      "TIMEOUT \{case_.scenario} \{case_.label} elapsed_ms=\{wall_elapsed} completed=\{completed}/\{case_.iterations}",
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
    timeout_elapsed_ms: if timed_out {
      Some(wall_elapsed)
    } else {
      None
    },
    average_ms: average,
    phases: avg_phases,
  }
}

// ── Main ────────────────────────────────────────────────────────────

///|
fn main {
  let args = cli_args()
  if args.length() > 0 && args[0] == "__step__" {
    run_internal_step(args)
    return
  }
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
