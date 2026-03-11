///|
struct Scenario {
  label : String
  source : String
  edited_source : String
  iterations : Int
}

///|
struct ReportSample {
  session : @app.BenchmarkSession
  next_text : String
}

///|
pub extern "js" fn now_ms() -> Int =
  #|() => {
  #|  const clock = globalThis.performance?.now?.bind(globalThis.performance);
  #|  return Math.round(clock ? clock() : Date.now());
  #|}

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
  #|  if (argv.length < 2) {
  #|    return null;
  #|  }
  #|  const parsed = Number.parseInt(argv[1], 10);
  #|  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
  #|}

///|
fn benchmark_source(let_count : Int, tail_literal : String) -> String {
  let segments : Array[String] = []
  for i = 0; i < let_count - 1; i = i + 1 {
    segments.push("let x\{i} = 0 in ")
  }
  segments.push("let x\{let_count - 1} = \{tail_literal} in x\{let_count - 1}")
  segments.join("")
}

///|
fn scenarios() -> Array[Scenario] {
  [
    {
      label: "medium",
      source: benchmark_source(80, "0"),
      edited_source: benchmark_source(80, "1"),
      iterations: 5,
    },
    {
      label: "large",
      source: benchmark_source(320, "0"),
      edited_source: benchmark_source(320, "1"),
      iterations: 5,
    },
  ]
}

///|
fn with_iterations(scenario : Scenario, iterations : Int?) -> Scenario {
  match iterations {
    Some(iterations) => { ..scenario, iterations }
    None => scenario
  }
}

///|
fn average_ms(
  scenario : Scenario,
  apply_step : (@app.BenchmarkSession, String) -> Unit,
) -> Int {
  let warmup = @app.BenchmarkSession::new(scenario.source)
  apply_step(warmup, scenario.edited_source)
  let samples : Array[ReportSample] = []
  let mut use_edited = true
  for _i = 0; _i < scenario.iterations; _i = _i + 1 {
    let base_text = if use_edited {
      scenario.source
    } else {
      scenario.edited_source
    }
    let next_text = if use_edited {
      scenario.edited_source
    } else {
      scenario.source
    }
    samples.push({ session: @app.BenchmarkSession::new(base_text), next_text })
    use_edited = !use_edited
  }
  let started = now_ms()
  for sample in samples {
    apply_step(sample.session, sample.next_text)
  }
  let elapsed = now_ms() - started
  elapsed / scenario.iterations
}

///|
fn print_report_line(
  label : String,
  scenario : Scenario,
  apply_step : (@app.BenchmarkSession, String) -> Unit,
) -> Unit {
  let avg_ms = average_ms(scenario, apply_step)
  println("\{scenario.label} \{label}: ~\{avg_ms} ms/edit")
}

///|
fn print_medium_report(scenario : Scenario) -> Unit {
  print_report_line("legacy set_text + refresh", scenario, fn(session, text) {
    session.legacy_set_text_refresh(text)
  })
  print_report_line("incremental apply_text_edit + refresh", scenario, fn(
    session,
    text,
  ) {
    session.incremental_eager_refresh(text)
  })
  print_report_line("deferred text input only", scenario, fn(session, text) {
    session.deferred_text_input(text)
  })
  print_report_line("deferred full cycle", scenario, fn(session, text) {
    session.deferred_full_cycle(text)
  })
}

///|
fn print_large_report(scenario : Scenario) -> Unit {
  print_report_line("deferred text input only", scenario, fn(session, text) {
    session.deferred_text_input(text)
  })
  print_report_line("deferred full cycle", scenario, fn(session, text) {
    session.deferred_full_cycle(text)
  })
}

///|
fn main {
  let benchmark_scenarios = scenarios()
  let iterations = cli_iterations()
  let medium = with_iterations(benchmark_scenarios[0], iterations)
  let large = with_iterations(benchmark_scenarios[1], iterations)
  let mode = cli_mode()
  println("Rabbita performance report")
  println("Source sizes: medium=80 lets, large=320 lets")
  println("Mode: \{mode}")
  match iterations {
    Some(iterations) => println("Iterations override: \{iterations}")
    None => ()
  }
  match mode {
    "large" => print_large_report(large)
    "medium" => print_medium_report(medium)
    "all" => {
      print_medium_report(medium)
      print_large_report(large)
    }
    _ => {
      println("Unknown mode '\{mode}', expected one of: all, medium, large")
    }
  }
}
