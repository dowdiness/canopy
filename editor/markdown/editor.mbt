///|
/// A categorized failure at the headless Markdown editor boundary.
pub(all) suberror MarkdownEditorError {
  InvalidAgentId
  InitializationFailed(detail~ : String)
  ProjectionUnavailable
  InvalidTextRange(start~ : Int, delete_len~ : Int, source_length~ : Int)
  EditFailed(detail~ : String)
}

///|
/// Stable editable block kinds exposed by the Markdown façade.
pub(all) enum MarkdownBlockKind {
  Paragraph
  Heading(level~ : Int)
  UnorderedListItem
  OrderedListItem(start~ : Int, delimiter~ : String)
  CodeBlock(info~ : String)
} derive(Eq, Debug)

///|
/// Immutable, façade-owned snapshot of one supported top-level block.
pub struct MarkdownBlockSnapshot {
  priv node_id : MarkdownNodeId
  priv kind : MarkdownBlockKind
  priv text : String
  priv source_start : Int
  priv source_end : Int
  priv text_start : Int
  priv text_end : Int
  priv marker_start : Int?
  priv marker_end : Int?
  priv fence_open_start : Int?
  priv fence_open_end : Int?
  priv fence_close_start : Int?
  priv fence_close_end : Int?
} derive(Eq, Debug)

///|
pub fn MarkdownBlockSnapshot::node_id(self : Self) -> MarkdownNodeId {
  self.node_id
}

///|
pub fn MarkdownBlockSnapshot::key(self : Self) -> String {
  self.node_id.key()
}

///|
pub fn MarkdownBlockSnapshot::kind(self : Self) -> MarkdownBlockKind {
  self.kind
}

///|
pub fn MarkdownBlockSnapshot::text(self : Self) -> String {
  if @md_sentinel.is_empty_paragraph_text(self.text) {
    ""
  } else {
    self.text
  }
}

///|
/// Retain the parser placeholder only inside the Markdown façade.
fn MarkdownBlockSnapshot::canonical_text(self : Self) -> String {
  self.text
}

///|
pub fn MarkdownBlockSnapshot::source_range(self : Self) -> (Int, Int) {
  (self.source_start, self.source_end)
}

///|
pub fn MarkdownBlockSnapshot::text_range(self : Self) -> (Int, Int) {
  (self.text_start, self.text_end)
}

///|
pub fn MarkdownBlockSnapshot::marker_range(self : Self) -> (Int, Int)? {
  match (self.marker_start, self.marker_end) {
    (Some(start), Some(end)) => Some((start, end))
    _ => None
  }
}

///|
/// Exact opening-fence span for a fenced code block, including its info string.
pub fn MarkdownBlockSnapshot::fence_open_range(self : Self) -> (Int, Int)? {
  match (self.fence_open_start, self.fence_open_end) {
    (Some(start), Some(end)) => Some((start, end))
    _ => None
  }
}

///|
/// Exact closing-fence span for a fenced code block.
pub fn MarkdownBlockSnapshot::fence_close_range(self : Self) -> (Int, Int)? {
  match (self.fence_close_start, self.fence_close_end) {
    (Some(start), Some(end)) => Some((start, end))
    _ => None
  }
}

///|
/// Opaque identity of a projected Markdown node.
pub struct MarkdownNodeId {
  priv value : @core.NodeId
} derive(Eq, Debug)

///|
pub fn MarkdownNodeId::key(self : Self) -> String {
  self.value.to_string()
}

///|
/// Immutable logical selection inside one editable block.
pub struct MarkdownBlockSelection {
  priv node_id : MarkdownNodeId
  priv offset : Int
} derive(Eq, Debug)

///|
pub fn MarkdownBlockSelection::node_id(self : Self) -> MarkdownNodeId {
  self.node_id
}

///|
/// UTF-16 code-unit offset relative to the selected block's text span.
pub fn MarkdownBlockSelection::offset(self : Self) -> Int {
  self.offset
}

///|
/// A caller-owned edit request lowered by the Markdown façade.
pub(all) enum MarkdownEditRequest {
  ReplaceSource(String)
  ReplaceText(start~ : Int, delete_len~ : Int, inserted~ : String)
  CommitEdit(node_id~ : MarkdownNodeId, new_text~ : String)
  CommitTextControlEdit(node_id~ : MarkdownNodeId, new_text~ : String)
  SplitBlock(node_id~ : MarkdownNodeId, offset~ : Int)
  ChangeHeadingLevel(node_id~ : MarkdownNodeId, level~ : Int)
  ToggleListItem(node_id~ : MarkdownNodeId)
  Delete(node_id~ : MarkdownNodeId)
  MergeWithPrevious(node_id~ : MarkdownNodeId)
} derive(Eq, Debug)

///|
/// Immutable, façade-owned projection summary.
pub struct MarkdownProjectionSnapshot {
  priv root_id : MarkdownNodeId?
  priv node_ids : @vector.Vector[MarkdownNodeId]
} derive(Eq, Debug)

///|
pub fn MarkdownProjectionSnapshot::root_id(self : Self) -> MarkdownNodeId? {
  self.root_id
}

///|
pub fn MarkdownProjectionSnapshot::node_ids(
  self : Self,
) -> @vector.Vector[MarkdownNodeId] {
  self.node_ids
}

///|
/// An immutable source snapshot detached from the editor implementation.
pub struct MarkdownDocumentSnapshot {
  priv source : String
  priv projection : MarkdownProjectionSnapshot
  priv blocks : @vector.Vector[MarkdownBlockSnapshot]
} derive(Eq, Debug)

///|
pub fn MarkdownDocumentSnapshot::source(self : Self) -> String {
  self.source
}

///|
pub fn MarkdownDocumentSnapshot::projection(
  self : Self,
) -> MarkdownProjectionSnapshot {
  self.projection
}

///|
pub fn MarkdownDocumentSnapshot::blocks(
  self : Self,
) -> @vector.Vector[MarkdownBlockSnapshot] {
  self.blocks
}

///|
/// Result of one atomic editor commit.
pub(all) enum MarkdownCommitResult {
  Applied(MarkdownDocumentSnapshot, MarkdownBlockSelection?)
  Unchanged(MarkdownDocumentSnapshot)
} derive(Eq, Debug)

///|
/// Opaque, headless Markdown editor façade.
pub struct MarkdownEditor {
  priv editor : @editor.SyncEditor[@md_markdown.Block]
}

///|
/// Construct a Markdown editor and install its initial canonical source.
pub fn MarkdownEditor::MarkdownEditor(
  agent_id~ : String,
  source~ : String,
) -> MarkdownEditor raise MarkdownEditorError {
  let editor = @md_companion.new_markdown_editor(agent_id) catch {
    @text.TextError::EmptyReplicaId => raise MarkdownEditorError::InvalidAgentId
    error =>
      raise MarkdownEditorError::InitializationFailed(detail=error.message())
  }
  editor.set_text(source)
  editor.refresh()
  { editor, }
}

///|
/// Read the last committed canonical source without exposing editor state.
pub fn MarkdownEditor::snapshot(self : Self) -> MarkdownDocumentSnapshot {
  document_snapshot(self.editor)
}

///|
/// Apply one façade-owned request atomically.
pub fn MarkdownEditor::commit(
  self : Self,
  request : MarkdownEditRequest,
) -> Result[MarkdownCommitResult, MarkdownEditorError] {
  match request {
    ReplaceSource(source) =>
      if self.editor.get_text() == source {
        Ok(MarkdownCommitResult::Unchanged(self.snapshot()))
      } else {
        self.editor.set_text(source)
        self.editor.refresh()
        Ok(MarkdownCommitResult::Applied(self.snapshot(), None))
      }
    ReplaceText(start~, delete_len~, inserted~) => {
      let source = self.editor.get_text()
      let source_length = source.length()
      if start < 0 ||
        delete_len < 0 ||
        start > source_length ||
        delete_len > source_length - start {
        Err(
          MarkdownEditorError::InvalidTextRange(
            start~,
            delete_len~,
            source_length~,
          ),
        )
      } else if self.editor.apply_text_edit_exact(
          start, delete_len, inserted, 0,
        ) {
        self.editor.refresh()
        let snapshot = self.snapshot()
        if snapshot.source() == source {
          Ok(MarkdownCommitResult::Unchanged(snapshot))
        } else {
          Ok(MarkdownCommitResult::Applied(snapshot, None))
        }
      } else {
        Err(MarkdownEditorError::EditFailed(detail="text edit rejected"))
      }
    }
    CommitEdit(node_id~, new_text~) =>
      match self.editable_block_text(node_id) {
        Some(_) =>
          self.commit_structural(
            @md_edits.MarkdownEditOp::CommitEdit(
              node_id=node_id.value,
              new_text~,
            ),
          )
        None =>
          Err(
            MarkdownEditorError::EditFailed(
              detail="no editable span for Markdown block target",
            ),
          )
      }
    CommitTextControlEdit(node_id~, new_text~) =>
      match self.editable_block_text(node_id) {
        Some(canonical_text) => {
          let reconciled = if @md_sentinel.is_empty_paragraph_text(
              canonical_text,
            ) {
            new_text
          } else {
            reconcile_text_control_edit(canonical_text, new_text)
          }
          let new_text = if reconciled.is_empty() {
            @md_sentinel.EMPTY_PARAGRAPH_SENTINEL
          } else {
            reconciled
          }
          self.commit_structural(
            @md_edits.MarkdownEditOp::CommitEdit(
              node_id=node_id.value,
              new_text~,
            ),
          )
        }
        None =>
          Err(
            MarkdownEditorError::EditFailed(
              detail="Markdown block target is not an editable top-level block",
            ),
          )
      }
    SplitBlock(node_id~, offset~) =>
      if self.editable_block_target(node_id) {
        self.commit_structural(
          @md_edits.MarkdownEditOp::SplitBlock(node_id=node_id.value, offset~),
        )
      } else {
        Err(
          MarkdownEditorError::EditFailed(
            detail="Markdown block target is not an editable top-level block",
          ),
        )
      }
    ChangeHeadingLevel(node_id~, level~) =>
      self.commit_structural(
        @md_edits.MarkdownEditOp::ChangeHeadingLevel(
          node_id=node_id.value,
          level~,
        ),
      )
    ToggleListItem(node_id~) =>
      self.commit_structural(
        @md_edits.MarkdownEditOp::ToggleListItem(node_id=node_id.value),
      )
    Delete(node_id~) =>
      self.commit_structural(
        @md_edits.MarkdownEditOp::Delete(node_id=node_id.value),
      )
    MergeWithPrevious(node_id~) =>
      if self.editable_block_target(node_id) {
        self.commit_structural(
          @md_edits.MarkdownEditOp::MergeWithPrevious(node_id=node_id.value),
        )
      } else {
        Err(
          MarkdownEditorError::EditFailed(
            detail="Markdown block target is not an editable top-level block",
          ),
        )
      }
  }
}

///|
/// Lower typed structural requests without exposing Tier-2 edit values.
fn MarkdownEditor::commit_structural(
  self : Self,
  op : @md_edits.MarkdownEditOp,
) -> Result[MarkdownCommitResult, MarkdownEditorError] {
  let source = self.editor.get_text()
  guard self.editor.get_proj_node() is Some(_) else {
    return Err(MarkdownEditorError::ProjectionUnavailable)
  }
  match @md_companion.apply_markdown_edit(self.editor, op, 0) {
    Err(detail) => Err(MarkdownEditorError::EditFailed(detail~))
    Ok(_) => {
      self.editor.refresh()
      let snapshot = self.snapshot()
      if snapshot.source() == source {
        // A no-op never authorizes a new caret move for the caller.
        Ok(MarkdownCommitResult::Unchanged(snapshot))
      } else {
        let selection = selection_for_cursor(snapshot, self.editor.get_cursor())
        Ok(MarkdownCommitResult::Applied(snapshot, selection))
      }
    }
  }
}

///|
/// Keep the public block façade narrower than the general Markdown edit API.
/// List items and container descendants remain available to lower-level edit
/// tests, but are not block-surface targets until their own UI contract exists.
fn MarkdownEditor::editable_block_target(
  self : Self,
  node_id : MarkdownNodeId,
) -> Bool {
  for block in self.snapshot().blocks().to_array() {
    if block.node_id() == node_id {
      return match block.kind() {
        MarkdownBlockKind::Paragraph | MarkdownBlockKind::Heading(_) => true
        _ => false
      }
    }
  }
  false
}

///|
/// Read the current canonical payload for one supported top-level block.
fn MarkdownEditor::editable_block_text(
  self : Self,
  node_id : MarkdownNodeId,
) -> String? {
  for block in self.snapshot().blocks().to_array() {
    if block.node_id() == node_id {
      return Some(block.canonical_text())
    }
  }
  None
}

///|
/// Normalize only for comparison with a DOM textarea control value.
fn normalize_text_control_line_endings(text : String) -> String {
  text.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
}

///|
/// Map an LF-normalized UTF-16 offset back into canonical source coordinates.
fn canonical_offset_for_text_control(
  canonical_text : String,
  normalized_offset : Int,
) -> Int {
  let mut canonical_offset = 0
  let mut normalized_offset_seen = 0
  while canonical_offset < canonical_text.length() &&
        normalized_offset_seen < normalized_offset {
    if canonical_text.code_unit_at(canonical_offset).to_int() == 0x0D {
      canonical_offset += 1
      if canonical_offset < canonical_text.length() &&
        canonical_text.code_unit_at(canonical_offset).to_int() == 0x0A {
        canonical_offset += 1
      }
    } else {
      canonical_offset += 1
    }
    normalized_offset_seen += 1
  }
  canonical_offset
}

///|
/// Reconcile a DOM-normalized block value while preserving untouched endings.
fn reconcile_text_control_edit(
  canonical_text : String,
  control_text : String,
) -> String {
  let normalized_canonical = normalize_text_control_line_endings(canonical_text)
  let normalized_control = normalize_text_control_line_endings(control_text)
  let change = @text_change.compute_text_change(
    normalized_canonical, normalized_control,
  )
  let canonical_start = canonical_offset_for_text_control(
    canonical_text,
    change.start,
  )
  let canonical_end = canonical_offset_for_text_control(
    canonical_text,
    change.start + change.delete_len,
  )
  canonical_text[:canonical_start].to_owned() +
  change.inserted +
  canonical_text[canonical_end:].to_owned()
}

///|
/// Resolve the SyncEditor cursor against the detached post-commit snapshot.
fn selection_for_cursor(
  snapshot : MarkdownDocumentSnapshot,
  cursor : Int,
) -> MarkdownBlockSelection? {
  for block in snapshot.blocks().to_array() {
    let (start, end) = block.text_range()
    if cursor >= start && cursor <= end {
      return Some({ node_id: block.node_id(), offset: cursor - start })
    }
  }
  None
}

///|
/// Copy only stable node identities into the façade snapshot.
fn projection_snapshot(
  editor : @editor.SyncEditor[@md_markdown.Block],
) -> MarkdownProjectionSnapshot {
  match editor.get_proj_node() {
    None => { root_id: None, node_ids: @vector.new() }
    Some(root) => {
      let ids : Array[MarkdownNodeId] = []
      root.walk_preorder(node => ids.push({ value: node.id() }))
      { root_id: Some({ value: root.id() }), node_ids: @vector.Vector(ids[:]) }
    }
  }
}

///|
/// Build one detached document snapshot from the editor's typed projection
/// and SourceMap. Unsupported containers remain mapped but are omitted from
/// the editable block view, preserving the #1045 alignment policy.
fn document_snapshot(
  editor : @editor.SyncEditor[@md_markdown.Block],
) -> MarkdownDocumentSnapshot {
  let source = editor.get_text()
  {
    source,
    projection: projection_snapshot(editor),
    blocks: editable_block_snapshots(editor, source),
  }
}

///|
fn editable_block_snapshots(
  editor : @editor.SyncEditor[@md_markdown.Block],
  source : String,
) -> @vector.Vector[MarkdownBlockSnapshot] {
  match editor.get_proj_node() {
    None => @vector.new()
    Some(root) => {
      let source_map = editor.get_source_map()
      let blocks : Array[MarkdownBlockSnapshot] = []
      for node in root.children {
        match node.kind {
          @md_markdown.UnorderedList(_) | @md_markdown.OrderedList(_, _) =>
            if tight_top_level_list(source, node, source_map) {
              for item in node.children {
                match item.kind {
                  @md_markdown.UnorderedListItem(_) =>
                    append_editable_block_snapshot(
                      blocks,
                      item,
                      MarkdownBlockKind::UnorderedListItem,
                      source,
                      source_map,
                    )
                  @md_markdown.OrderedListItem(_, marker) => {
                    guard marker is Some(_) else { continue }
                    let marker = match marker {
                      Some(marker) => marker
                      None => continue
                    }
                    append_editable_block_snapshot(
                      blocks,
                      item,
                      MarkdownBlockKind::OrderedListItem(
                        start=marker.start(),
                        delimiter=ordered_marker_delimiter(marker),
                      ),
                      source,
                      source_map,
                    )
                  }
                  _ => ()
                }
              }
            }
          @md_markdown.Paragraph(_) =>
            append_editable_block_snapshot(
              blocks,
              node,
              MarkdownBlockKind::Paragraph,
              source,
              source_map,
            )
          @md_markdown.Heading(level, _) =>
            append_editable_block_snapshot(
              blocks,
              node,
              MarkdownBlockKind::Heading(level~),
              source,
              source_map,
            )
          @md_markdown.CodeBlock(info, _) =>
            append_editable_block_snapshot(
              blocks,
              node,
              MarkdownBlockKind::CodeBlock(info~),
              source,
              source_map,
            )
          _ => ()
        }
      }
      @vector.Vector(blocks[:])
    }
  }
}

///|
/// Append one block whose SourceMap roles satisfy the typed façade contract.
fn append_editable_block_snapshot(
  blocks : Array[MarkdownBlockSnapshot],
  node : @core.ProjNode[@md_markdown.Block],
  kind : MarkdownBlockKind,
  source : String,
  source_map : @core.SourceMap,
) -> Unit {
  guard source_map.get_range(node.id()) is Some(source_range) else { return }
  let text_span = match source_map.get_token_span(node.id(), "text") {
    Some(span) => span
    None =>
      match source_map.get_token_span(node.id(), "code") {
        Some(span) => span
        None => return
      }
  }
  let marker_range = source_map.get_token_span(node.id(), "marker")
  let fence_open_range = source_map.get_token_span(node.id(), "fence_open")
  let fence_close_range = source_map.get_token_span(node.id(), "fence_close")
  if kind is MarkdownBlockKind::CodeBlock(_) &&
    (fence_open_range is None || fence_close_range is None) {
    return
  }
  blocks.push({
    node_id: { value: node.id() },
    kind,
    text: source[text_span.start:text_span.end].to_owned(),
    source_start: source_range.start,
    source_end: source_range.end,
    text_start: text_span.start,
    text_end: text_span.end,
    marker_start: marker_range.map(r => r.start),
    marker_end: marker_range.map(r => r.end),
    fence_open_start: fence_open_range.map(r => r.start),
    fence_open_end: fence_open_range.map(r => r.end),
    fence_close_start: fence_close_range.map(r => r.start),
    fence_close_end: fence_close_range.map(r => r.end),
  })
}

///|
/// A list is editable only when every direct item is a simple, tight item.
fn tight_top_level_list(
  source : String,
  list : @core.ProjNode[@md_markdown.Block],
  source_map : @core.SourceMap,
) -> Bool {
  for item in list.children {
    if !(item.kind is @md_markdown.Block::UnorderedListItem(_) ||
      item.kind is @md_markdown.Block::OrderedListItem(_, _)) {
      return false
    }
    if item.children.length() != 0 ||
      source_map.get_token_span(item.id(), "text") is None ||
      source_map.get_token_span(item.id(), "marker") is None {
      return false
    }
    let text_span = match source_map.get_token_span(item.id(), "text") {
      Some(span) => span
      None => return false
    }
    let payload = source[text_span.start:text_span.end]
    if payload.contains("\n".view()) || payload.contains("\r".view()) {
      return false
    }
  }
  for i in 0..<(list.children.length() - 1) {
    let current = list.children[i]
    let next = list.children[i + 1]
    let current_range = match source_map.get_range(current.id()) {
      Some(range) => range
      None => return false
    }
    let next_range = match source_map.get_range(next.id()) {
      Some(range) => range
      None => return false
    }
    let gap = source[current_range.end:next_range.start].to_owned()
    let normalized = gap
      .replace_all(old="\r\n", new="\n")
      .replace_all(old="\r", new="\n")
    if normalized.contains("\n\n".view()) {
      return false
    }
  }
  true
}

///|
fn ordered_marker_delimiter(marker : @md_markdown.OrderedListMarker) -> String {
  match marker.delimiter() {
    @md_markdown.Period => "."
    @md_markdown.Paren => ")"
  }
}
