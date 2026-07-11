// Whitebox tests for the causal-graph history view (Phase 1a).
//
// Scenarios are constructed by driving real `SyncEditor` instances through
// scripted ops and reading the resulting `CausalSnapshot`. Tests consume
// only the public snapshot API — they never reach into egw internals.

///|
/// Helper: build a fresh single-editor scenario with `n` sequential
/// inserts of "a" by `agent`. LVs run 0..<n in append order.
fn build_linear(agent : String, n : Int) -> @editor.SyncEditor[@ast.Term] {
  let (editor, _) = @lambda.new_lambda_editor(agent)
  for i in 0..<n {
    editor.insert_at(i, "a", 0)
  }
  editor
}

///|
test "render_history empty" {
  let (editor, _) = @lambda.new_lambda_editor("local")
  match render_history(editor.causal_snapshot(), "local") {
    Empty => ()
    _ => fail("expected Empty")
  }
}

///|
test "render_history single op" {
  let editor = build_linear("local", 1)
  let dot = match render_history(editor.causal_snapshot(), "local") {
    Dot(s) => s
    _ => {
      fail("expected Dot")
      return
    }
  }
  inspect(
    dot,
    content=(
      #|digraph {
      #|  rankdir=TB;
      #|  node [style=filled, shape=box, fontname="JetBrains Mono"];
      #|  { rank=source; n0; }
      #|  n0 [label="You#0", fillcolor="#82aaff", color="#ffcb6b", penwidth=2.5];
      #|}
      #|
    ),
  )
  // Round-trip: emitted DOT parses cleanly.
  match @gv_parser.parse_dot(dot) {
    Ok(_) => ()
    Err(e) => fail("DOT parse failed: \{e.message}")
  }
}

///|
test "render_history linear 3-op chain not compressed" {
  let editor = build_linear("local", 3)
  let dot = match render_history(editor.causal_snapshot(), "local") {
    Dot(s) => s
    _ => {
      fail("expected Dot")
      return
    }
  }
  // Below threshold: three singleton nodes, two edges, tail on frontier.
  // Count nodes/edges loosely so palette tweaks don't churn the test.
  let lines = dot.split("\n").collect()
  let mut node_count = 0
  let mut edge_count = 0
  for line in lines {
    if line.has_prefix("  n") && line.contains("[label=") {
      node_count += 1
    } else if line.contains(" -> n") {
      edge_count += 1
    }
  }
  inspect(node_count, content="3")
  inspect(edge_count, content="2")
  // Only the tail (LV2, seq 2) gets the frontier stroke.
  let frontier_marks = dot.split("penwidth=2.5").collect().length() - 1
  inspect(frontier_marks, content="1")
  match @gv_parser.parse_dot(dot) {
    Ok(_) => ()
    Err(e) => fail("DOT parse failed: \{e.message}")
  }
}

///|
test "render_history 10-op chain extended by 1 — chain compressed, frontier singleton" {
  // 11 ops total: LVs 0..9 form an interior chain (no frontier inside),
  // LV 10 is the sole frontier tip. Chain length 10 ≥ threshold ⇒ compress.
  let editor = build_linear("local", 11)
  let dot = match render_history(editor.causal_snapshot(), "local") {
    Dot(s) => s
    _ => {
      fail("expected Dot")
      return
    }
  }
  // Two compressed nodes total: the chain pill + the frontier singleton.
  let lines = dot.split("\n").collect()
  let mut node_count = 0
  for line in lines {
    if line.has_prefix("  n") && line.contains("[label=") {
      node_count += 1
    }
  }
  inspect(node_count, content="2")
  // Chain label includes "(10 ops)".
  inspect(dot.contains("(10 ops)"), content="true")
  // Frontier singleton — the local agent's tip renders as "You#10".
  inspect(dot.contains("You#10"), content="true")
  // Exactly one frontier-stroked node (the tip).
  let frontier_marks = dot.split("penwidth=2.5").collect().length() - 1
  inspect(frontier_marks, content="1")
  match @gv_parser.parse_dot(dot) {
    Ok(_) => ()
    Err(e) => fail("DOT parse failed: \{e.message}")
  }
}

///|
test "render_history 10-op chain terminating at frontier — 9 compressed + 1 singleton" {
  // 10 ops. LV 9 is the sole frontier; LVs 0..8 are interior (length 9 ≥ 5).
  let editor = build_linear("local", 10)
  let dot = match render_history(editor.causal_snapshot(), "local") {
    Dot(s) => s
    _ => {
      fail("expected Dot")
      return
    }
  }
  let lines = dot.split("\n").collect()
  let mut node_count = 0
  for line in lines {
    if line.has_prefix("  n") && line.contains("[label=") {
      node_count += 1
    }
  }
  inspect(node_count, content="2")
  inspect(dot.contains("(9 ops)"), content="true")
  inspect(dot.contains("You#9"), content="true")
}

///|
test "render_history two-agent divergence — 3 nodes, 2 edges, two fills, two frontier tips" {
  let (alice, _) = @lambda.new_lambda_editor("alice")
  alice.insert_at(0, "a", 0) // LV0 by alice → shared root
  let (bob, _) = @lambda.new_lambda_editor("bob")
  bob.apply_sync(alice.export_all())
  // Now both have alice's LV0 with op_count 1, frontier {0}.
  alice.insert_at(1, "x", 0) // LV1_alice on top of root
  bob.insert_at(1, "y", 0) // LV1_bob on top of root
  alice.apply_sync(bob.export_all())
  // alice now has root + alice-tip + bob-tip; both tips on frontier.
  let dot = match render_history(alice.causal_snapshot(), "alice") {
    Dot(s) => s
    _ => {
      fail("expected Dot")
      return
    }
  }
  let lines = dot.split("\n").collect()
  let mut node_count = 0
  let mut edge_count = 0
  for line in lines {
    if line.has_prefix("  n") && line.contains("[label=") {
      node_count += 1
    } else if line.contains(" -> n") {
      edge_count += 1
    }
  }
  inspect(node_count, content="3")
  inspect(edge_count, content="2")
  // Local agent (alice) gets palette[0] = blue; bob gets a non-zero index.
  inspect(dot.contains("#82aaff"), content="true") // alice fills
  // Two frontier tips.
  let frontier_marks = dot.split("penwidth=2.5").collect().length() - 1
  inspect(frontier_marks, content="2")
  match @gv_parser.parse_dot(dot) {
    Ok(_) => ()
    Err(e) => fail("DOT parse failed: \{e.message}")
  }
}

///|
test "render_history merge — diamond, single frontier" {
  // Build divergence then have alice insert a third op AFTER syncing bob.
  // Result: alice's new op has parents = [alice_tip, bob_tip] ⇒ a merge node.
  let (alice, _) = @lambda.new_lambda_editor("alice")
  alice.insert_at(0, "a", 0)
  let (bob, _) = @lambda.new_lambda_editor("bob")
  bob.apply_sync(alice.export_all())
  alice.insert_at(1, "x", 0)
  bob.insert_at(1, "y", 0)
  alice.apply_sync(bob.export_all())
  // Alice's frontier is now {alice_tip, bob_tip}; her next insert merges.
  alice.insert_at(0, "M", 0)
  let dot = match render_history(alice.causal_snapshot(), "alice") {
    Dot(s) => s
    _ => {
      fail("expected Dot")
      return
    }
  }
  // 4 nodes total. Single frontier: the merge tip.
  let lines = dot.split("\n").collect()
  let mut node_count = 0
  for line in lines {
    if line.has_prefix("  n") && line.contains("[label=") {
      node_count += 1
    }
  }
  inspect(node_count, content="4")
  let frontier_marks = dot.split("penwidth=2.5").collect().length() - 1
  inspect(frontier_marks, content="1")
  match @gv_parser.parse_dot(dot) {
    Ok(_) => ()
    Err(e) => fail("DOT parse failed: \{e.message}")
  }
}

///|
test "render_history graph too large refuses to render" {
  let editor = build_linear("local", MAX_OPS + 1)
  match render_history(editor.causal_snapshot(), "local") {
    TooLarge(n) => inspect(n, content="1001")
    _ => fail("expected TooLarge")
  }
}

///|
test "render_history produces parseable DOT for adversarial agent IDs" {
  // The local agent always renders as "You", but `display_name` for a
  // remote agent uses the trailing 4 chars of its ID — which can be
  // anything, including DOT-special chars. This test wires a remote
  // peer whose suffix contains backslash + double-quote and asserts
  // the emitted DOT round-trips through `@gv_parser.parse_dot`.
  let me = "me"
  let weird = "evil-\\\"x"
  let (alice, _) = @lambda.new_lambda_editor(me)
  alice.insert_at(0, "a", 0)
  let (bob, _) = @lambda.new_lambda_editor(weird)
  bob.apply_sync(alice.export_all())
  bob.insert_at(1, "b", 0)
  alice.apply_sync(bob.export_all())
  let dot = match render_history(alice.causal_snapshot(), me) {
    Dot(s) => s
    _ => {
      fail("expected Dot")
      return
    }
  }
  // Local agent renders as "You"; remote peer's suffix-derived label
  // must be DOT-escaped so the parser doesn't choke.
  inspect(dot.contains("You#0"), content="true")
  match @gv_parser.parse_dot(dot) {
    Ok(_) => ()
    Err(e) => fail("DOT parse failed: \{e.message}")
  }
}

///|
test "escape_dot_string normalizes newlines and escapes specials" {
  inspect(escape_dot_string("plain"), content="plain")
  inspect(
    escape_dot_string("a\"b"),
    content=(
      #|a\"b
    ),
  )
  inspect(
    escape_dot_string("a\\b"),
    content=(
      #|a\\b
    ),
  )
  inspect(escape_dot_string("a\nb\rc"), content="a b c")
}

///|
test "collect_history_data reserves index 0 for local agent past 8 collaborators" {
  // 9 distinct non-local agents (a01..a09) collide with index 0 under a
  // naïve `idx % 8` wrap; the 1..7 wrap rule keeps index 0 reserved.
  let (me, _) = @lambda.new_lambda_editor("me")
  me.insert_at(0, "a", 0)
  let mut pos = 1
  for i in 1..<=9 {
    let agent = "a0" + i.to_string()
    let (peer, _) = @lambda.new_lambda_editor(agent)
    peer.apply_sync(me.export_all())
    peer.insert_at(pos, "x", 0)
    me.apply_sync(peer.export_all())
    pos += 1
  }
  let data = collect_history_data(me.causal_snapshot(), "me")
  inspect(data.agent_color.get("me").unwrap(), content="0")
  // Every non-local agent maps into 1..7 — never 0.
  for i in 1..<=9 {
    let agent = "a0" + i.to_string()
    let c = data.agent_color.get(agent).unwrap()
    inspect(c >= 1 && c <= 7, content="true")
  }
}
