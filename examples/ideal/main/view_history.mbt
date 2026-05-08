// Phase 1a: causal-graph history view — DOT generation only.
//
// The pipeline is `CausalSnapshot → HistoryData → CompressedData → DOT`.
// UI wiring (BottomTab::History, view_history Html, render command) is
// Phase 1b and lives in view_bottom.mbt; this file is intentionally
// view-free so the algorithm can be tested in isolation.

///|
/// Minimum chain length to warrant compression. Below the threshold,
/// expanding each LV to a singleton node reads more clearly than
/// abstracting them into a "(N ops)" pill.
const CHAIN_THRESHOLD : Int = 5

///|
/// Hard ceiling for Phase 1: above this, refuse to render. A "most recent N"
/// cut is not ancestry-closed and would silently misrepresent the DAG, so
/// the only honest options are render-everything or render-nothing.
const MAX_OPS : Int = 1000

///|
/// Per-agent palette index (0..7). The local agent is pinned to 0 so the
/// user's own ops stay visually anchored across sessions.
struct HistoryData {
  frontier : Map[Int, Bool]
  agent_color : Map[String, Int]
}

///|
/// One node in the rendered graph. A `Chain` carries the full LV list, not
/// just `(start, end, count)`, so future selection / time-travel features
/// can map a click on a compressed node back to its constituents.
enum CompressedNode {
  Single(Int)
  Chain(Array[Int])
}

///|
struct CompressedData {
  nodes : Array[CompressedNode]
  parents : Array[Array[Int]]
}

///|
/// Top-level entry. Three outcomes: empty (no ops), valid DOT, or
/// graph-too-large placeholder. The ceiling check happens before any
/// graph walking so layout cost stays bounded.
pub enum HistoryRender {
  Empty
  Dot(String)
  TooLarge(Int)
}

///|
pub fn render_history(
  snap : @history.CausalSnapshot,
  local_agent : String,
) -> HistoryRender {
  let n = snap.op_count()
  if n == 0 {
    return Empty
  }
  if n > MAX_OPS {
    return TooLarge(n)
  }
  let data = collect_history_data(snap, local_agent)
  let comp = chain_compress(data, snap)
  Dot(emit_dot_string(comp, snap, data, local_agent))
}

///|
/// Walk LVs in order, derive the deterministic palette, and snapshot the
/// frontier as a lookup map for O(1) "is this a tip?" checks during
/// compression and emission.
///
/// Determinism: `local_agent` → 0; remaining agents → 1..7 in lexicographic
/// order, wrapping after 8. The palette rule is the only source of agent
/// identity in this module — no other ordering should leak through.
fn collect_history_data(
  snap : @history.CausalSnapshot,
  local_agent : String,
) -> HistoryData {
  let n = snap.op_count()
  let frontier : Map[Int, Bool] = {}
  for lv in snap.frontier() {
    frontier[lv] = true
  }
  // Gather unique agents.
  let seen : Map[String, Bool] = {}
  let others : Array[String] = []
  for lv in 0..<n {
    match snap.entry(lv) {
      Some(e) => {
        let a = e.agent()
        if !seen.contains(a) {
          seen[a] = true
          if a != local_agent {
            others.push(a)
          }
        }
      }
      None => ()
    }
  }
  others.sort()
  let agent_color : Map[String, Int] = {}
  agent_color[local_agent] = 0
  // Non-local agents wrap through 1..7 so index 0 stays reserved for the
  // local agent — a naïve `idx % 8` would silently recycle the local
  // color at 8+ collaborators and break the primary identity cue.
  let mut idx = 0
  for a in others {
    agent_color[a] = idx % 7 + 1
    idx += 1
  }
  { frontier, agent_color }
}

///|
/// Collapse maximal same-agent runs whose interior nodes have indegree
/// exactly 1 and outdegree exactly 1 — the topological correctness
/// condition for chain quotient — provided neither endpoint is on the
/// frontier ("now" is always shown un-collapsed). Below `CHAIN_THRESHOLD`
/// the chain is left expanded.
///
/// Phase 1 policy: same-agent only. Cross-agent indegree=1/outdegree=1
/// chains are legal but rare, and a multi-agent pill would muddle the
/// "agent A typed N chars" reading.
fn chain_compress(
  data : HistoryData,
  snap : @history.CausalSnapshot,
) -> CompressedData {
  let n = snap.op_count()
  let frontier = data.frontier

  // chain_succ[p] = c if edge p→c is a chain link.
  // Functional in p (p has children_count == 1, so the unique child is c).
  let chain_succ : Map[Int, Int] = {}
  for c in 0..<n {
    if frontier.contains(c) {
      continue
    }
    let entry = match snap.entry(c) {
      Some(e) => e
      None => continue
    }
    let parents_view = entry.parents()
    if parents_view.length() != 1 {
      continue
    }
    let p = parents_view[0]
    if frontier.contains(p) {
      continue
    }
    if snap.children_count(p) != 1 {
      continue
    }
    let p_entry = match snap.entry(p) {
      Some(e) => e
      None => continue
    }
    if p_entry.agent() != entry.agent() {
      continue
    }
    chain_succ[p] = c
  }

  // A node is a chain interior/tail iff it appears as a chain successor.
  // Chain heads have no chain predecessor; we walk forward from each.
  let has_chain_pred : Map[Int, Bool] = {}
  for _, c in chain_succ {
    has_chain_pred[c] = true
  }
  let lv_to_node : Map[Int, Int] = {}
  let nodes : Array[CompressedNode] = []
  for lv in 0..<n {
    if lv_to_node.contains(lv) {
      continue
    }
    if has_chain_pred.contains(lv) {
      // Reached as a successor of an earlier head; skip until walk picks it up.
      // (Heads have lower LVs than their successors — earlier-iteration heads
      // already absorbed this node into their walk.)
      continue
    }
    let chain : Array[Int] = [lv]
    let mut cur = lv
    while chain_succ.get(cur) is Some(next) {
      chain.push(next)
      cur = next
    }
    if chain.length() >= CHAIN_THRESHOLD {
      let node_idx = nodes.length()
      nodes.push(Chain(chain))
      for x in chain {
        lv_to_node[x] = node_idx
      }
    } else {
      for x in chain {
        let node_idx = nodes.length()
        nodes.push(Single(x))
        lv_to_node[x] = node_idx
      }
    }
  }

  // Build per-node parent edges. Self-edges (parent and child collapsed
  // into the same chain) are dropped; duplicate parents (multiple chain
  // members with the same external ancestor — impossible under the
  // indegree=1/outdegree=1 rule, but cheap to guard) are deduped.
  let parents : Array[Array[Int]] = []
  for _ in 0..<nodes.length() {
    parents.push([])
  }
  for c in 0..<n {
    let c_node = match lv_to_node.get(c) {
      Some(i) => i
      None => continue
    }
    let entry = match snap.entry(c) {
      Some(e) => e
      None => continue
    }
    for p in entry.parents() {
      let p_node = match lv_to_node.get(p) {
        Some(i) => i
        None => continue
      }
      if p_node == c_node {
        continue
      }
      let plist = parents[c_node]
      if !plist.contains(p_node) {
        plist.push(p_node)
      }
    }
  }
  { nodes, parents }
}

///|
/// 8-color palette tuned for the dark theme (`#1a1a2e` background) and the
/// project's syntax-color hand. Indices match `HistoryData.agent_color`.
fn palette_color(idx : Int) -> String {
  match idx {
    0 => "#82aaff" // blue — local agent
    1 => "#c792ea" // purple
    2 => "#c3e88d" // green
    3 => "#f78c6c" // orange
    4 => "#ff5370" // red
    5 => "#ffcb6b" // yellow
    6 => "#89ddff" // cyan
    _ => "#bb80ff" // light purple
  }
}

///|
/// Frontier stroke color — must contrast with every fill.
const FRONTIER_STROKE : String = "#ffcb6b"

///|
/// Emit a `digraph` consumable by `@gv_parser.parse_dot`. Layout direction
/// is top-to-bottom (earliest LVs at the top). Roots are pinned to the
/// source rank explicitly so multi-root graphs render with a clear baseline.
///
/// Agent IDs are user-controlled in the protocol, so DOT escaping (backslash,
/// quote, newline) is a correctness requirement, not just hygiene.
fn emit_dot_string(
  comp : CompressedData,
  snap : @history.CausalSnapshot,
  data : HistoryData,
  local_agent : String,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("digraph {\n")
  buf.write_string("  rankdir=TB;\n")
  buf.write_string(
    "  node [style=filled, shape=box, fontname=\"JetBrains Mono\"];\n",
  )

  // Roots: nodes with no parents in the compressed graph.
  let roots : Array[Int] = []
  for i in 0..<comp.nodes.length() {
    if comp.parents[i].is_empty() {
      roots.push(i)
    }
  }
  if !roots.is_empty() {
    buf.write_string("  { rank=source; ")
    for r in roots {
      buf.write_string("n")
      buf.write_string(r.to_string())
      buf.write_string("; ")
    }
    buf.write_string("}\n")
  }

  // Nodes.
  for i in 0..<comp.nodes.length() {
    let (label, agent, is_frontier) = node_attrs(
      comp.nodes[i],
      snap,
      data,
      local_agent,
    )
    let color_idx = data.agent_color.get(agent).unwrap_or(0)
    let fill = palette_color(color_idx)
    buf.write_string("  n")
    buf.write_string(i.to_string())
    buf.write_string(" [label=\"")
    buf.write_string(label)
    buf.write_string("\", fillcolor=\"")
    buf.write_string(fill)
    buf.write_string("\"")
    if is_frontier {
      buf.write_string(", color=\"")
      buf.write_string(FRONTIER_STROKE)
      buf.write_string("\", penwidth=2.5")
    }
    buf.write_string("];\n")
  }

  // Edges.
  for i in 0..<comp.nodes.length() {
    for p in comp.parents[i] {
      buf.write_string("  n")
      buf.write_string(p.to_string())
      buf.write_string(" -> n")
      buf.write_string(i.to_string())
      buf.write_string(";\n")
    }
  }
  buf.write_string("}\n")
  buf.to_string()
}

///|
/// Resolve label, agent, and frontier flag for a single compressed node.
/// Chains are never on the frontier (excluded during compression), so this
/// only checks the singleton case.
fn node_attrs(
  node : CompressedNode,
  snap : @history.CausalSnapshot,
  data : HistoryData,
  local_agent : String,
) -> (String, String, Bool) {
  match node {
    Single(lv) => {
      let entry = snap.entry(lv).unwrap()
      let agent = entry.agent()
      let label = escape_dot_string(display_name(agent, local_agent)) +
        "#" +
        entry.seq().to_string()
      (label, agent, data.frontier.contains(lv))
    }
    Chain(lvs) => {
      let head = snap.entry(lvs[0]).unwrap()
      let agent = head.agent()
      let label = escape_dot_string(display_name(agent, local_agent)) +
        " (" +
        lvs.length().to_string() +
        " ops)"
      (label, agent, false)
    }
  }
}

///|
/// Build the HTML for the agent-color legend strip rendered above the SVG.
///
/// The legend gives users a decoder for the visualization:
/// - "You" with the local agent's fill color (palette index 0).
/// - "Peer-XXXX" for each remote agent, in palette-index order so the
///   reading flow matches the strip's left-to-right color sequence.
/// - A frontier swatch labeled "now" so the amber-stroked nodes are
///   immediately readable as "current tips" rather than decoration.
///
/// Agent IDs are user-controlled in the protocol, so HTML-escape every
/// interpolated string. No legend is emitted when the snapshot has no
/// agents (caller should already have routed to `Empty`).
pub fn legend_html(
  snap : @history.CausalSnapshot,
  local_agent : String,
) -> String {
  let data = collect_history_data(snap, local_agent)
  let buf = StringBuilder::new()
  buf.write_string(
    "<div class=\"history-legend\" role=\"list\" aria-label=\"Causal history color legend\">",
  )
  // Local agent first — anchor for "this color is you."
  match data.agent_color.get(local_agent) {
    Some(idx) =>
      append_legend_chip(
        buf,
        palette_color(idx),
        display_name(local_agent, local_agent),
      )
    None => ()
  }
  // Remote agents in palette-index order so the strip reads left-to-right
  // as palette[1], palette[2], … — matching what the user sees in the SVG.
  let others : Array[(Int, String)] = []
  for agent, idx in data.agent_color {
    if agent != local_agent {
      others.push((idx, agent))
    }
  }
  others.sort_by(fn(a, b) { a.0 - b.0 })
  for pair in others {
    append_legend_chip(
      buf,
      palette_color(pair.0),
      display_name(pair.1, local_agent),
    )
  }
  // Frontier swatch — amber border, no fill — mirrors the SVG's stroke.
  buf.write_string(
    "<span class=\"history-legend-item\" role=\"listitem\"><span class=\"history-legend-frontier\" style=\"border-color:",
  )
  buf.write_string(FRONTIER_STROKE)
  buf.write_string("\"></span>now</span>")
  buf.write_string("</div>")
  buf.to_string()
}

///|
fn append_legend_chip(
  buf : StringBuilder,
  fill : String,
  label : String,
) -> Unit {
  buf.write_string(
    "<span class=\"history-legend-item\" role=\"listitem\"><span class=\"history-legend-dot\" style=\"background:",
  )
  buf.write_string(fill)
  buf.write_string("\"></span>")
  buf.write_string(escape_html_string(label))
  buf.write_string("</span>")
}

///|
/// Single source of truth for agent identity in user-facing labels.
/// The local agent is always "You"; remote agents get a short
/// "Peer-XXXX" name derived from the trailing 4 chars of their agent
/// ID (production IDs look like `ideal-{timestamp}-{random8}` — the
/// prefix is shared across the session so the suffix is the
/// discriminator). For short or non-standard IDs, the full string is
/// kept verbatim.
///
/// Used by both `legend_html` (decoder strip) and `node_attrs` (SVG
/// labels) so a single agent reads with the same name in both
/// surfaces — without this, the legend would say "You" while the
/// graph showed `ideal-mqr4kx0a-9d49…`, and users would have to
/// manually correlate the two.
fn display_name(agent : String, local_agent : String) -> String {
  if agent == local_agent {
    "You"
  } else {
    let n = agent.length()
    if n <= 8 {
      agent
    } else {
      "Peer-" + agent[n - 4:n].to_owned()
    }
  }
}

///|
/// HTML-escape a user-supplied identifier for safe interpolation into
/// `innerHTML`. Quote escaping covers attribute-value contexts; the
/// callers above never put user strings inside attribute values, but
/// keeping it complete avoids a footgun if the legend grows tooltips.
fn escape_html_string(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    match ch {
      '<' => buf.write_string("&lt;")
      '>' => buf.write_string("&gt;")
      '&' => buf.write_string("&amp;")
      '"' => buf.write_string("&quot;")
      '\'' => buf.write_string("&#39;")
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
/// DOT-escape a user-supplied identifier: backslash and double-quote are
/// escaped; newline / carriage-return are replaced with a single space (a
/// raw newline inside a `"..."` literal is rejected by the DOT parser).
fn escape_dot_string(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    match ch {
      '\\' => buf.write_string("\\\\")
      '"' => buf.write_string("\\\"")
      '\n' | '\r' => buf.write_string(" ")
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}
