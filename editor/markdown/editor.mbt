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
      self.commit_structural(
        @md_edits.MarkdownEditOp::CommitEdit(node_id=node_id.value, new_text~),
      )
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
  self.editable_block_text(node_id) is Some(_)
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
        let kind = match node.kind {
          @md_markdown.Paragraph(_) => Some(MarkdownBlockKind::Paragraph)
          @md_markdown.Heading(level, _) =>
            Some(MarkdownBlockKind::Heading(level~))
          _ => None
        }
        match kind {
          None => ()
          Some(kind) => {
            guard source_map.get_range(node.id()) is Some(source_range) else {
              continue
            }
            guard source_map.get_token_span(node.id(), "text")
              is Some(text_span) else {
              continue
            }
            let text_range = (text_span.start, text_span.end)
            let marker_range = match
              source_map.get_token_span(node.id(), "marker") {
              Some(range) => Some((range.start, range.end))
              None => None
            }
            blocks.push({
              node_id: { value: node.id() },
              kind,
              text: source[text_range.0:text_range.1].to_owned(),
              source_start: source_range.start,
              source_end: source_range.end,
              text_start: text_range.0,
              text_end: text_range.1,
              marker_start: match marker_range {
                Some(range) => Some(range.0)
                None => None
              },
              marker_end: match marker_range {
                Some(range) => Some(range.1)
                None => None
              },
            })
          }
        }
      }
      @vector.Vector(blocks[:])
    }
  }
}
