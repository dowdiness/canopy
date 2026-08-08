// PROTOTYPE — throwaway terminal shell for Markdown public API RC1 logic.

///|
fn lifecycle_label(state : LifecycleState) -> String {
  match state {
    DetachedSource => "DetachedSource"
    Mounted(writer~) => "Mounted(\{writer})"
    DetachedHistory => "DetachedHistory"
  }
}

///|
fn hidden_ranges_label(ranges : Array[HiddenRange]) -> String {
  if ranges.is_empty() {
    "[]"
  } else {
    let labels = ranges.map(range => "\{range.start}..\{range.end}")
    "[" + labels.join(", ") + "]"
  }
}

///|
fn internal_transform_label(transform : PrototypeTransform?) -> String {
  match transform {
    None => "none"
    Some(edit) => {
      let inserted = edit.inserted.escape()
      "start=\{edit.start} delete=\{edit.delete_len} insert=\{inserted}"
    }
  }
}

///|
fn public_transform_label(transform : PublicTransform?) -> String {
  match transform {
    None => "none"
    Some(edit) => {
      let inserted = edit.inserted.escape()
      "start=\{edit.start} delete=\{edit.delete_len} insert=\{inserted}"
    }
  }
}

///|
fn integration_label(report : IntegrationReport?) -> String {
  match report {
    None => "not run"
    Some(report) => {
      let passed = report.cases.fold(init=0, (count, item) => {
        if item.passed {
          count + 1
        } else {
          count
        }
      })
      let status = if report.passed { "PASS" } else { "FAIL" }
      "\{status} (\{passed}/\{report.cases.length()})"
    }
  }
}

///|
fn integration_failure_label(report : IntegrationReport?) -> String {
  match report {
    None => "none"
    Some(report) => {
      let first_failure : IntegrationCase? = report.cases.fold(init=None, (
        found,
        item,
      ) => {
        match found {
          Some(_) => found
          None => if item.passed { None } else { Some(item) }
        }
      })
      match first_failure {
        None => "none"
        Some(item) => item.name + ": " + item.detail
      }
    }
  }
}

///|
fn render(model : PrototypeModel) -> Unit {
  let bold = "\u001b[1m"
  let dim = "\u001b[2m"
  let reset = "\u001b[0m"
  let lifecycle = lifecycle_label(model.lifecycle.state)
  let lifecycle_source = model.lifecycle.source.escape()
  let internal_source = model.coordinates.internal_source.escape()
  let public_source = model.coordinates.public_source.escape()
  let hidden = hidden_ranges_label(model.coordinates.hidden)
  let internal_edit = internal_transform_label(model.coordinates.last_internal)
  let public_edit = public_transform_label(model.coordinates.last_public)
  let integration = integration_label(model.integration)
  let integration_failure = integration_failure_label(model.integration)
  let coordinate_status = if model.coordinates.invariant_holds {
    "PASS"
  } else {
    "FAIL"
  }
  println("\u001b[2J\u001b[H")
  println("\{bold}Markdown API RC1 — LOGIC PROTOTYPE\{reset}")
  println("\{dim}Throwaway branch: prototype/markdown-api-rc1\{reset}")
  println("")
  println("\{bold}Mount lifecycle\{reset}")
  println("  state:               \{lifecycle}")
  println("  source:              \{lifecycle_source}")
  println("  causal version:      \{model.lifecycle.version}")
  println("  mount generation:    \{model.lifecycle.mount_generation}")
  println("  fail next unmount:   \{model.lifecycle.fail_next_unmount}")
  println("  last transition:     \{model.lifecycle.last_event}")
  println("")
  println("\{bold}Portable coordinate projection\{reset}")
  println("  scenario:            \{model.coordinates.scenario_name}")
  println("  internal source:     \{internal_source}")
  println("  hidden UTF-16:       \{hidden}")
  println("  public source:       \{public_source}")
  println(
    "  edit progress:       \{model.coordinates.applied_edits}/\{model.coordinates.edits.length()}",
  )
  println("  last internal edit:  \{internal_edit}")
  println("  last public edit:    \{public_edit}")
  println("  projection invariant:\{coordinate_status}")
  println("")
  println("\{bold}Real Markdown integration\{reset}")
  println("  matrix:              \{integration}")
  println("  first failure:       \{integration_failure}")
  println("")
  println("\{dim}\{model.notice}\{reset}")
  println("")
  println(
    "\{bold}[m]\{reset} mount  \{bold}[u]\{reset} unmount  \{bold}[f]\{reset} fail next unmount  \{bold}[e]\{reset} edit document",
  )
  println(
    "\{bold}[a]\{reset} coordinate edit  \{bold}[n]\{reset} next scenario  \{bold}[i]\{reset} real integration  \{bold}[q]\{reset} quit",
  )
}

///|
fn action_for(command : String) -> PrototypeAction? {
  match command {
    "m" => Some(Mount)
    "u" => Some(Unmount)
    "f" => Some(ToggleUnmountFailure)
    "e" => Some(ApplyDocumentEdit)
    "a" => Some(ApplyCoordinateEdit)
    "n" => Some(NextScenario)
    _ => None
  }
}

///|
async fn main {
  for model = initial_model() {
    render(model)
    guard @stdio.stdin.read_until("\n") is Some(line) else { break }
    let command = line.trim().to_owned()
    if command == "q" {
      break
    }
    if command == "i" {
      let report = run_integration_matrix()
      continue reduce(model, RecordIntegration(report))
    }
    match action_for(command) {
      Some(action) => continue reduce(model, action)
      None => continue { ..model, notice: "unknown command: " + command }
    }
  }
}
