// ViewUpdater: Computes incremental view patches by diffing ViewNode trees.

///|
priv struct RegisteredDiagnosticFix {
  id : Int
  fix : @loom_core.DiagnosticFix
}

///|
fn RegisteredDiagnosticFix::RegisteredDiagnosticFix(
  id : Int,
  fix : @loom_core.DiagnosticFix,
) -> RegisteredDiagnosticFix {
  { id, fix }
}

///|
priv struct PublishedDiagnostic {
  id : Int
  diagnostic : @loom_core.Diagnostic
  rendered_message : String?
  fixes : Array[RegisteredDiagnosticFix]
}

///|
fn PublishedDiagnostic::PublishedDiagnostic(
  id : Int,
  diagnostic : @loom_core.Diagnostic,
  rendered_message : String?,
  fixes : Array[RegisteredDiagnosticFix],
) -> PublishedDiagnostic {
  { id, diagnostic, rendered_message, fixes: fixes.copy() }
}

///|
pub struct ViewUpdateState {
  mut previous : @protocol.ViewNode?
  mut previous_decorations : Array[@protocol.Decoration]?
  mut had_errors : Bool
  priv mut next_diagnostic_snapshot_id : Int
  priv mut diagnostic_snapshot : (
    Int,
    @loom_core.SourceId,
    @text.Version,
    Array[(Int, Array[(Int, @loom_core.DiagnosticFix)])],
  )?
} derive(Debug)

///|
pub fn ViewUpdateState::ViewUpdateState() -> ViewUpdateState {
  {
    previous: None,
    previous_decorations: None,
    had_errors: false,
    next_diagnostic_snapshot_id: 0,
    diagnostic_snapshot: None,
  }
}

///|
pub fn ViewUpdateState::set_previous(
  self : ViewUpdateState,
  value : @protocol.ViewNode?,
) -> Unit {
  self.previous = value
}

///|
pub fn ViewUpdateState::set_had_errors(
  self : ViewUpdateState,
  value : Bool,
) -> Unit {
  self.had_errors = value
}

///|
fn diagnostic_protocol_severity(
  severity : @loom_core.DiagnosticSeverity,
) -> @protocol.Severity {
  match severity {
    @loom_core.DiagnosticSeverity::Error => @protocol.SevError
    @loom_core.DiagnosticSeverity::Warning => @protocol.SevWarning
    @loom_core.DiagnosticSeverity::Info => @protocol.SevInfo
    @loom_core.DiagnosticSeverity::Hint => @protocol.SevHint
  }
}

///|
fn diagnostic_fix_applicability(
  applicability : @loom_core.FixApplicability,
) -> String {
  match applicability {
    @loom_core.FixApplicability::Always => "always"
    @loom_core.FixApplicability::MaybeIncorrect => "maybe_incorrect"
  }
}

///|
fn current_source_diagnostic_fixes(
  source_id : @loom_core.SourceId,
  diagnostic : @loom_core.Diagnostic,
) -> Array[RegisteredDiagnosticFix] {
  diagnostic
  .fixes()
  .mapi((id, fix) => RegisteredDiagnosticFix(id, fix))
  .filter(registered => {
    registered.fix.edits()[0].span().source_id() == source_id
  })
}

///|
priv struct CurrentSourceResolver {
  source_id : @diagnostic.SourceId
  snapshot : @diagnostic.SourceSnapshot
}

///|
impl @diagnostic.SourceResolver for CurrentSourceResolver with fn resolve_source(
  self,
  requested_source_id,
) {
  if requested_source_id == self.source_id {
    Some(self.snapshot)
  } else {
    None
  }
}

///|
fn diagnostic_source_resolver(
  source_id : @diagnostic.SourceId,
  source : String,
) -> CurrentSourceResolver {
  {
    source_id,
    snapshot: @diagnostic.SourceSnapshot(
      "<input>",
      source,
      @diagnostic.LineIndex::new(source),
    ),
  }
}

///|
fn protocol_diagnostic_rows(
  source_id : @loom_core.SourceId,
  snapshot_id : Int,
  published : PublishedDiagnostic,
) -> Iter[@protocol.Diagnostic] {
  let diagnostic = published.diagnostic
  let severity = diagnostic_protocol_severity(diagnostic.severity())
  let code = diagnostic.code().map(code => code.value())
  let summaries = published.fixes.map(registered => {
    @protocol.DiagnosticFixSummary(
      id=registered.id,
      title=registered.fix.title(),
      applicability=diagnostic_fix_applicability(registered.fix.applicability()),
    )
  })
  let has_actions = published.rendered_message is Some(_) &&
    !summaries.is_empty()
  let message = published.rendered_message.unwrap_or(diagnostic.message())
  let protocol_diagnostic = (from, to) => {
    let protocol_snapshot_id : Int? = if has_actions {
      Some(snapshot_id)
    } else {
      None
    }
    let protocol_diagnostic_id : Int? = if has_actions {
      Some(published.id)
    } else {
      None
    }
    @protocol.Diagnostic(
      from~,
      to~,
      severity~,
      message~,
      code?,
      snapshot_id?=protocol_snapshot_id,
      diagnostic_id?=protocol_diagnostic_id,
      fixes=if has_actions { summaries.copy() } else { [] },
    )
  }
  let labels = diagnostic.labels()
  if labels.is_empty() {
    Iter::singleton(protocol_diagnostic(0, 0))
  } else {
    labels
    .iter()
    .filter(label => {
      label.style() == @loom_core.LabelStyle::Primary &&
      label.span().source_id() == source_id
    })
    .map(label => {
      let range = label.span().range()
      protocol_diagnostic(range.start().value(), range.end().value())
    })
  }
}

///|
fn[T] ViewUpdateState::publish_diagnostics(
  self : ViewUpdateState,
  editor : SyncEditor[T],
  diagnostics : @loom_core.DiagnosticSet,
) -> Array[@protocol.Diagnostic] {
  if diagnostics.is_empty() {
    self.diagnostic_snapshot = None
    return []
  }
  let snapshot_id = self.next_diagnostic_snapshot_id
  self.next_diagnostic_snapshot_id += 1
  let source_id = editor.parser_source_id()
  let source = editor.get_text()
  let resolver = diagnostic_source_resolver(source_id, source)
  let published = diagnostics
    .items()
    .mapi((id, diagnostic) => {
      let rendered_message : String? = Some(diagnostic.render_plain(resolver)) catch {
        _ => None
      }
      let fixes = match rendered_message {
        Some(_) => current_source_diagnostic_fixes(source_id, diagnostic)
        None => []
      }
      PublishedDiagnostic(id, diagnostic, rendered_message, fixes)
    })
  let registered = published
    .iter()
    .filter(item => !item.fixes.is_empty())
    .map(item => {
      (item.id, item.fixes.map(registered => (registered.id, registered.fix)))
    })
    .to_array()
  self.diagnostic_snapshot = Some(
    (snapshot_id, source_id, editor.get_version(), registered),
  )
  published
  .iter()
  .flat_map(item => protocol_diagnostic_rows(source_id, snapshot_id, item))
  .to_array()
}

///|
pub fn[T : Eq] ViewUpdateState::apply_diagnostic_fix(
  self : ViewUpdateState,
  editor : SyncEditor[T],
  snapshot_id~ : Int,
  diagnostic_id~ : Int,
  fix_id~ : Int,
  timestamp_ms~ : Int,
) -> Bool {
  guard snapshot_id >= 0 && diagnostic_id >= 0 && fix_id >= 0 else {
    return false
  }
  guard self.diagnostic_snapshot
    is Some((current_snapshot_id, source_id, version, diagnostics)) else {
    return false
  }
  guard current_snapshot_id == snapshot_id &&
    source_id == editor.parser_source_id() &&
    version == editor.get_version() else {
    return false
  }
  guard diagnostics.search_by(item => {
      match item {
        (id, _) => id == diagnostic_id
      }
    })
    is Some(diagnostic_index) else {
    return false
  }
  let (_, fixes) = diagnostics[diagnostic_index]
  guard fixes.search_by(item => {
      match item {
        (id, _) => id == fix_id
      }
    })
    is Some(fix_index) else {
    return false
  }
  let (_, fix) = fixes[fix_index]
  guard editor.apply_diagnostic_fix_candidate(source_id, fix, timestamp_ms) else {
    return false
  }
  self.diagnostic_snapshot = None
  true
}

///|
pub fn[T : @loom_core.Renderable] SyncEditor::get_view_tree(
  self : SyncEditor[T],
) -> @protocol.ViewNode? {
  match self.get_proj_node() {
    Some(proj_node) => {
      let source_map = self.get_source_map()
      let source_text = Some(self.get_text())
      let annotations = match self.capabilities.get_annotations {
        Some(get_ann) => get_ann()
        None => Map([])
      }
      match self.capabilities.to_view_node {
        Some(convert) =>
          Some(convert(proj_node, source_map, annotations, source_text))
        None =>
          Some(
            @protocol.proj_to_view_node(
              proj_node,
              source_map,
              source_text~,
              annotations~,
            ),
          )
      }
    }
    None => None
  }
}

///|
/// Narrow Loom diagnostics to the existing current-document protocol shape.
/// Label and diagnostic order are preserved. A truly locationless diagnostic
/// keeps the compatibility `0..0` range; labeled diagnostics emit only primary
/// labels belonging to `source_id`.
pub fn project_diagnostics_for_source(
  source_id : @loom_core.SourceId,
  diagnostics : @loom_core.DiagnosticSet,
) -> Array[@protocol.Diagnostic] {
  diagnostics
  .items()
  .iter()
  .flat_map(diagnostic => {
    let severity = diagnostic_protocol_severity(diagnostic.severity())
    let code = diagnostic.code().map(code => code.value())
    let protocol_diagnostic = (from, to) => {
      @protocol.Diagnostic(
        from~,
        to~,
        severity~,
        message=diagnostic.message(),
        code?,
      )
    }
    let labels = diagnostic.labels()
    if labels.is_empty() {
      Iter::singleton(protocol_diagnostic(0, 0))
    } else {
      labels
      .iter()
      .filter(label => {
        label.style() == @loom_core.LabelStyle::Primary &&
        label.span().source_id() == source_id
      })
      .map(label => {
        let range = label.span().range()
        protocol_diagnostic(range.start().value(), range.end().value())
      })
    }
  })
  .to_array()
}

///|
/// Combine diagnostics only when every input belongs to the current source
/// snapshot. The returned set owns its collection and preserves parser-first
/// producer order.
fn merge_current_diagnostics(
  editor_source : String,
  parser_source : String,
  parser_diagnostics : @loom_core.DiagnosticSet,
  semantic_snapshot : (String, @loom_core.DiagnosticSet)?,
) -> @loom_core.DiagnosticSet {
  if editor_source != parser_source {
    return @loom_core.DiagnosticSet::empty()
  }
  let merged = parser_diagnostics.copy()
  match semantic_snapshot {
    Some((semantic_source, semantic_diagnostics)) if semantic_source ==
      parser_source => merged.add_all(semantic_diagnostics)
    _ => ()
  }
  merged
}

///|
pub fn[T : @loom_core.Renderable] compute_view_patches(
  state : ViewUpdateState,
  editor : SyncEditor[T],
) -> Array[@protocol.ViewPatch] {
  let patches : Array[@protocol.ViewPatch] = []
  let current = editor.get_view_tree()
  let current_decorations = match editor.capabilities.get_decorations {
    Some(get_decos) => get_decos()
    None => []
  }
  match (state.previous, current) {
    (None, None) => patches.push(@protocol.ViewPatch::FullTree(root=None))
    (None, Some(curr)) =>
      patches.push(@protocol.ViewPatch::FullTree(root=Some(curr)))
    (Some(_), None) => patches.push(@protocol.ViewPatch::FullTree(root=None))
    (Some(prev), Some(curr)) => diff_view_nodes(prev, curr, patches)
  }
  match state.previous_decorations {
    Some(prev) if prev == current_decorations => ()
    _ =>
      if !current_decorations.is_empty() ||
        state.previous_decorations is Some(_) {
        patches.push(
          @protocol.ViewPatch::SetDecorations(decorations=current_decorations),
        )
      }
  }
  state.previous_decorations = Some(current_decorations)
  let parser_snapshot = editor.parser_snapshot().read_or_abort()
  let semantic_snapshot = match editor.capabilities.get_diagnostics {
    Some(get_diagnostics) => get_diagnostics()
    None => None
  }
  let current_diagnostics = merge_current_diagnostics(
    editor.get_text(),
    parser_snapshot.source,
    parser_snapshot.diagnostics,
    semantic_snapshot,
  )
  let diagnostics = state.publish_diagnostics(editor, current_diagnostics)
  if !diagnostics.is_empty() {
    patches.push(@protocol.ViewPatch::SetDiagnostics(diagnostics~))
    state.had_errors = true
  } else if state.had_errors {
    patches.push(@protocol.ViewPatch::SetDiagnostics(diagnostics=[]))
    state.had_errors = false
  }
  state.previous = current
  patches
}

///|
fn diff_view_nodes(
  prev : @protocol.ViewNode,
  curr : @protocol.ViewNode,
  patches : Array[@protocol.ViewPatch],
) -> Unit {
  // If node identity changed at this position (e.g., a new block was inserted
  // shifting siblings), emit ReplaceNode so the frontend gets the correct ID.
  if prev.id != curr.id {
    patches.push(@protocol.ViewPatch::ReplaceNode(node_id=prev.id, node=curr))
    return
  }
  if prev.kind_tag != curr.kind_tag {
    patches.push(@protocol.ViewPatch::ReplaceNode(node_id=prev.id, node=curr))
    return
  }
  // token_spans changes require ReplaceNode because UpdateNode doesn't carry spans
  if prev.token_spans != curr.token_spans {
    patches.push(@protocol.ViewPatch::ReplaceNode(node_id=prev.id, node=curr))
    return
  }
  // annotation changes require ReplaceNode because UpdateNode doesn't carry annotations
  if prev.annotations != curr.annotations {
    patches.push(@protocol.ViewPatch::ReplaceNode(node_id=prev.id, node=curr))
    return
  }
  if prev.label != curr.label ||
    prev.css_class != curr.css_class ||
    prev.text != curr.text {
    patches.push(
      @protocol.ViewPatch::UpdateNode(
        node_id=curr.id,
        label=curr.label,
        css_class=curr.css_class,
        text=curr.text,
      ),
    )
  }
  let prev_len = prev.children.length()
  let curr_len = curr.children.length()
  let min_len = if prev_len < curr_len { prev_len } else { curr_len }
  for i in 0..<min_len {
    diff_view_nodes(prev.children[i], curr.children[i], patches)
  }
  if curr_len > prev_len {
    for i in prev_len..<curr_len {
      patches.push(
        @protocol.ViewPatch::InsertChild(
          parent_id=curr.id,
          index=i,
          child=curr.children[i],
        ),
      )
    }
  }
  // Remove from end to start for stable indices
  if prev_len > curr_len {
    for i = prev_len - 1; i >= curr_len; i = i - 1 {
      patches.push(
        @protocol.ViewPatch::RemoveChild(
          parent_id=curr.id,
          index=i,
          child_id=prev.children[i].id,
        ),
      )
    }
  }
}
