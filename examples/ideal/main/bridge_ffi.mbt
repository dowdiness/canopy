///|
/// Read the agent ID set by JS before module import.
extern "js" fn js_get_agent_id() -> String =
  #| function() {
  #|   var id = globalThis.__canopy_agent_id;
  #|   return typeof id === 'string' ? id : '';
  #| }

///|
/// Sync MoonBit editor text to the JS-side CRDT editor, then reconcile PM.
/// Called after undo/redo/load-example to keep the two editors in sync.
extern "js" fn js_reconcile_editor_with_text(new_text : String) -> Unit =
  #| function(new_text) {
  #|   var crdt = globalThis.__canopy_crdt;
  #|   var handle = globalThis.__canopy_crdt_handle;
  #|   if (!crdt || handle == null) return;
  #|   var el = document.querySelector('canopy-editor');
  #|   if (crdt.get_text(handle) !== new_text) {
  #|     if (crdt.set_text_and_record) {
  #|       crdt.set_text_and_record(handle, new_text, Date.now());
  #|     } else {
  #|       crdt.set_text(handle, new_text);
  #|     }
  #|     if (el && typeof el.notifyLocalChange === 'function') {
  #|       el.notifyLocalChange();
  #|     }
  #|   }
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
/// Consume the last node selected from the Web Component.
extern "js" fn js_take_selected_node_id() -> String =
  #| function() {
  #|   var nodeId = globalThis.__canopy_pending_node_selection;
  #|   globalThis.__canopy_pending_node_selection = null;
  #|   return typeof nodeId === 'string' ? nodeId : '';
  #| }

///|
/// Consume the pending structural edit op forwarded from the Web Component.
/// Clears the global to prevent stale reads.
extern "js" fn js_take_structural_edit_op() -> String =
  #| function() {
  #|   var pending = globalThis.__canopy_pending_structural_edit;
  #|   if (!pending) return '';
  #|   return typeof pending.op === 'string' ? pending.op : '';
  #| }

///|
/// Consume the pending structural edit node ID and clear the global.
extern "js" fn js_take_structural_edit_node_id() -> String =
  #| function() {
  #|   var pending = globalThis.__canopy_pending_structural_edit;
  #|   globalThis.__canopy_pending_structural_edit = null;
  #|   if (!pending) return '';
  #|   return typeof pending.nodeId === 'string' ? pending.nodeId : '';
  #| }

///|
/// Undo on the JS-side CRDT editor, sync CM6, and trigger MoonBit text sync.
extern "js" fn js_undo_and_sync() -> Unit =
  #| function() {
  #|   var crdt = globalThis.__canopy_crdt;
  #|   var handle = globalThis.__canopy_crdt_handle;
  #|   if (!crdt || handle == null) return;
  #|   if (!crdt.undo_manager_can_undo(handle)) return;
  #|   crdt.undo_manager_undo(handle);
  #|   var el = document.querySelector('canopy-editor');
  #|   if (el && typeof el.notifyLocalChange === 'function') {
  #|     el.notifyLocalChange();
  #|   }
  #|   if (el) el.projNode = '';
  #|   var btn = document.getElementById('canopy-text-sync-trigger');
  #|   if (btn) btn.click();
  #| }

///|
/// Redo on the JS-side CRDT editor, sync CM6, and trigger MoonBit text sync.
extern "js" fn js_redo_and_sync() -> Unit =
  #| function() {
  #|   var crdt = globalThis.__canopy_crdt;
  #|   var handle = globalThis.__canopy_crdt_handle;
  #|   if (!crdt || handle == null) return;
  #|   if (!crdt.undo_manager_can_redo(handle)) return;
  #|   crdt.undo_manager_redo(handle);
  #|   var el = document.querySelector('canopy-editor');
  #|   if (el && typeof el.notifyLocalChange === 'function') {
  #|     el.notifyLocalChange();
  #|   }
  #|   if (el) el.projNode = '';
  #|   var btn = document.getElementById('canopy-text-sync-trigger');
  #|   if (btn) btn.click();
  #| }

///|
/// Set innerHTML of an element by ID. Used for Graphviz SVG rendering.
extern "js" fn js_set_inner_html(element_id : String, html : String) -> Unit =
  #| function(id, html) {
  #|   var el = document.getElementById(id);
  #|   if (el) el.innerHTML = html;
  #| }

// Note: editor event wiring is done in main.ts wireEditorEvents() — not here.
