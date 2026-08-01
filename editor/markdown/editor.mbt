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
/// Opaque identity of a projected Markdown node.
pub struct MarkdownNodeId {
  priv value : @core.NodeId
} derive(Eq, Debug)

///|
/// A caller-owned edit request lowered by the Markdown façade.
pub(all) enum MarkdownEditRequest {
  ReplaceSource(String)
  ReplaceText(start~ : Int, delete_len~ : Int, inserted~ : String)
  CommitEdit(node_id~ : MarkdownNodeId, new_text~ : String)
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
/// Result of one atomic editor commit.
pub(all) enum MarkdownCommitResult {
  Applied(MarkdownDocumentSnapshot)
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
  {
    source: self.editor.get_text(),
    projection: projection_snapshot(self.editor),
  }
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
        Ok(MarkdownCommitResult::Applied(self.snapshot()))
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
          Ok(MarkdownCommitResult::Applied(snapshot))
        }
      } else {
        Err(MarkdownEditorError::EditFailed(detail="text edit rejected"))
      }
    }
    CommitEdit(node_id~, new_text~) =>
      self.commit_structural(
        @md_edits.MarkdownEditOp::CommitEdit(node_id=node_id.value, new_text~),
      )
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
      self.commit_structural(
        @md_edits.MarkdownEditOp::MergeWithPrevious(node_id=node_id.value),
      )
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
        Ok(MarkdownCommitResult::Unchanged(snapshot))
      } else {
        Ok(MarkdownCommitResult::Applied(snapshot))
      }
    }
  }
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
