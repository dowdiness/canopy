///|
/// Read the agent ID set by JS before module import.
extern "js" fn js_get_agent_id() -> String =
  #| function() {
  #|   var id = globalThis.__canopy_agent_id;
  #|   return typeof id === 'string' ? id : '';
  #| }

///|
/// Sync MoonBit editor text to the JS-side CRDT editor, then reconcile PM.
/// Called after load-example to keep the two editors in sync.
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
  #|   }
  #|   if (!el) return;
  #|   el.projNode = '';
  #| }

///|
/// Sync CM6, broadcast to peers, always notify local change.
/// Used by undo/redo where the CRDT text is already correct.
extern "js" fn js_sync_and_broadcast(_new_text : String) -> Unit =
  #| function() {
  #|   var el = document.querySelector('canopy-editor');
  #|   if (!el) return;
  #|   if (typeof el.syncAfterExternalChange === 'function') {
  #|     el.syncAfterExternalChange();
  #|   }
  #|   if (typeof el.notifyLocalChange === 'function') {
  #|     el.notifyLocalChange();
  #|   }
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
/// NOTE: This calls cmView.focus() — steals focus from outline panel.
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
/// Read and consume the pending sync status set by JS.
extern "js" fn js_take_sync_status() -> String =
  #| function() {
  #|   var s = globalThis.__canopy_pending_sync_status;
  #|   globalThis.__canopy_pending_sync_status = null;
  #|   return typeof s === 'string' ? s : '';
  #| }

///|
/// Set innerHTML of an element by ID. Used for Graphviz SVG rendering.
extern "js" fn js_set_inner_html(element_id : String, html : String) -> Unit =
  #| function(id, html) {
  #|   var el = document.getElementById(id);
  #|   if (el) el.innerHTML = html;
  #| }

///|
/// Consume the pending action overlay node ID set by JS.
extern "js" fn js_take_action_overlay_node() -> String =
  #| function() {
  #|   var v = globalThis.__canopy_pending_action_overlay_node;
  #|   globalThis.__canopy_pending_action_overlay_node = null;
  #|   return v || '';
  #| }

///|
/// Consume the pending action key pressed set by JS.
extern "js" fn js_take_action_key() -> String =
  #| function() {
  #|   var v = globalThis.__canopy_pending_action_key;
  #|   globalThis.__canopy_pending_action_key = null;
  #|   return v || '';
  #| }

///|
/// Tell JS whether the action overlay is currently open.
extern "js" fn js_set_overlay_open(open : Bool) -> Unit =
  #| function(open) {
  #|   globalThis.__canopy_overlay_open = open;
  #| }

///|
/// Get the bounding rect of the currently selected ProseMirror node as JSON.
extern "js" fn js_get_selected_node_rect() -> String =
  #| function() {
  #|   var el = document.querySelector('canopy-editor');
  #|   if (!el || !el.shadowRoot) return '{}';
  #|   var sel = el.shadowRoot.querySelector('.ProseMirror-selectednode');
  #|   if (!sel) return '{}';
  #|   var r = sel.getBoundingClientRect();
  #|   return JSON.stringify({ top: Math.round(r.top), left: Math.round(r.left), bottom: Math.round(r.bottom), right: Math.round(r.right) });
  #| }

///|
/// Reconcile ProseMirror after a tree edit applied on the MoonBit side.
extern "js" fn js_reconcile_after_tree_edit() -> Unit =
  #| function() {
  #|   var el = document.querySelector('canopy-editor');
  #|   if (el && el._bridge) el._bridge.afterLocalEdit();
  #| }

///|
/// Focus the action overlay panel element.
/// Called after render when the overlay becomes visible.
extern "js" fn js_focus_overlay_panel() -> Unit =
  #| function() {
  #|   var el = document.querySelector('canopy-editor');
  #|   if (!el || !el.shadowRoot) return;
  #|   var panel = el.shadowRoot.querySelector('.action-overlay-panel');
  #|   if (panel) panel.focus();
  #| }

///|
/// Get viewport dimensions as JSON for overlay position clamping.
extern "js" fn js_get_viewport_size() -> String =
  #| function() {
  #|   return JSON.stringify({ width: window.innerWidth, height: window.innerHeight });
  #| }

///|
/// Get bounding rect of the selected outline row for overlay anchoring.
extern "js" fn js_get_outline_selected_rect() -> String =
  #| function() {
  #|   var sel = document.querySelector('.outline-panel .tree-row.selected');
  #|   if (!sel) return '{}';
  #|   var r = sel.getBoundingClientRect();
  #|   return JSON.stringify({ top: Math.round(r.top), left: Math.round(r.left), bottom: Math.round(r.bottom), right: Math.round(r.right) });
  #| }

///|
/// Scroll the selected outline row into view.
extern "js" fn js_scroll_outline_to_selected() -> Unit =
  #| function() {
  #|   var sel = document.querySelector('.outline-panel .tree-row.selected');
  #|   if (sel) sel.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  #| }

///|
/// Focus the action overlay panel in the page DOM (not shadow DOM).
/// Used when overlay is opened from outline keyboard context.
extern "js" fn js_focus_outline_overlay() -> Unit =
  #| function() {
  #|   var panel = document.querySelector('.action-overlay-panel');
  #|   if (panel) panel.focus();
  #| }

///|
/// Focus the tree-rows div so keyboard navigation works after node clicks.
/// Called after js_set_editor_selected_node to override CM6's cmView.focus().
extern "js" fn js_focus_tree_rows() -> Unit =
  #| function() {
  #|   var el = document.querySelector('.tree-rows');
  #|   if (el) el.focus();
  #| }

// Note: editor event wiring is done in main.ts wireEditorEvents() — not here.
