///|
/// Mount is handled by main.ts via requestAnimationFrame.
/// This is a no-op kept for API compatibility — called from main after Rabbita mounts.
extern "js" fn js_mount_editor() -> Unit =
  #| function() {
  #|   // Mounting is deferred to main.ts requestAnimationFrame
  #| }

///|
/// Sync MoonBit editor text to the JS-side CRDT editor, then reconcile PM.
/// Called after undo/redo/load-example to keep the two editors in sync.
extern "js" fn js_reconcile_editor_with_text(new_text : String) -> Unit =
  #| function(new_text) {
  #|   var crdt = globalThis.__canopy_crdt;
  #|   if (!crdt) return;
  #|   crdt.set_text(1, new_text);
  #|   var el = document.querySelector('canopy-editor');
  #|   if (!el) return;
  #|   // Trigger projNode setter which syncs CM6 in text mode
  #|   // and reconciles PM in structure mode
  #|   el.projNode = '';
  #| }

///|
/// Set the editor mode on the Web Component ('text' or 'structure').
extern "js" fn js_set_editor_mode(mode : String) -> Unit =
  #| function(mode) {
  #|   var el = document.querySelector('canopy-editor');
  #|   if (el) el.mode = mode;
  #| }

///|
/// Set the selected node in the Web Component by node ID.
extern "js" fn js_set_editor_selected_node(node_id : String) -> Unit =
  #| function(node_id) {
  #|   var el = document.querySelector('canopy-editor');
  #|   if (el) el.selectedNode = node_id;
  #| }

///|
/// Get the current text from the JS-side CRDT editor.
/// Used to sync CM6 edits back to MoonBit's SyncEditor.
extern "js" fn js_get_editor_text() -> String =
  #| function() {
  #|   var crdt = globalThis.__canopy_crdt;
  #|   if (!crdt) return '';
  #|   return crdt.get_text(1);
  #| }

///|
/// Undo on the JS-side CRDT editor, sync CM6, and trigger MoonBit text sync.
extern "js" fn js_undo_and_sync() -> Unit =
  #| function() {
  #|   var crdt = globalThis.__canopy_crdt;
  #|   if (!crdt) return;
  #|   crdt.undo_manager_undo(1);
  #|   var el = document.querySelector('canopy-editor');
  #|   if (el) el.projNode = '';
  #|   var btn = document.getElementById('canopy-text-sync-trigger');
  #|   if (btn) btn.click();
  #| }

///|
/// Redo on the JS-side CRDT editor, sync CM6, and trigger MoonBit text sync.
extern "js" fn js_redo_and_sync() -> Unit =
  #| function() {
  #|   var crdt = globalThis.__canopy_crdt;
  #|   if (!crdt) return;
  #|   crdt.undo_manager_redo(1);
  #|   var el = document.querySelector('canopy-editor');
  #|   if (el) el.projNode = '';
  #|   var btn = document.getElementById('canopy-text-sync-trigger');
  #|   if (btn) btn.click();
  #| }

///|
/// Wire the text-changed event from <canopy-editor> to click a hidden button.
/// The hidden button has Rabbita's on_click=dispatch(TextChangedFromEditor),
/// so clicking it triggers the Rabbita update loop properly.
extern "js" fn js_wire_text_changed_to_button() -> Unit =
  #| function() {
  #|   var el = document.querySelector('canopy-editor');
  #|   if (!el || el.__canopy_events_wired) return;
  #|   el.__canopy_events_wired = true;
  #|   el.addEventListener('text-changed', function() {
  #|     var btn = document.getElementById('canopy-text-sync-trigger');
  #|     if (btn) btn.click();
  #|   });
  #| }
