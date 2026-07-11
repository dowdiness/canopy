///| Main entry point for the CRDT editor CLI

///|
/// Runs demos of the CRDT editor
fn main {
  // First run the convergence demo
  run_convergence_demo()
  println("")
  println("")

  // Then run the interactive REPL demo
  run_repl("alice")
}
