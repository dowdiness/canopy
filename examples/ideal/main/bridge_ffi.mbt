///|
/// Read the agent ID set by JS before module import.
extern "js" fn js_get_agent_id() -> String =
  #| function() {
  #|   var id = globalThis.__canopy_agent_id;
  #|   return typeof id === 'string' ? id : '';
  #| }

///|
/// Current session-relative time in milliseconds for CRDT undo grouping.
extern "js" fn js_now_ms() -> Int =
  #| function() {
  #|   const key = "__canopy_session_start_ms";
  #|   if (typeof globalThis[key] !== "number") {
  #|     globalThis[key] = Date.now();
  #|   }
  #|   const elapsed = Math.floor(Date.now() - globalThis[key]);
  #|   return Math.max(0, Math.min(2147483647, elapsed));
  #| }

///|
/// Build the ideal editor's CodeMirror extension from the exact CM namespace
/// passed by the rabbita binding.
extern "js" fn js_make_ideal_cm_extension_raw(
  cm : @js_value.Value,
) -> @js_value.Value =
  #| function(cm) {
  #|   const click = (id) => {
  #|     const btn = document.getElementById(id);
  #|     if (btn && typeof btn.click === 'function') btn.click();
  #|   };
  #|   const normalizeExtensions = (factory) => {
  #|     const provided = typeof factory === 'function' ? factory(cm) : [];
  #|     return Array.isArray(provided) ? provided : [provided];
  #|   };
  #|   const theme = cm.EditorView.theme({
  #|     "&": {
  #|       backgroundColor: "transparent",
  #|       color: "var(--canopy-fg, #e4e4f0)",
  #|       fontFamily: "var(--canopy-font-mono, 'Iosevka', monospace)",
  #|       fontSize: "18px",
  #|       height: "100%",
  #|     },
  #|     ".cm-scroller": {
  #|       overflow: "auto",
  #|       height: "100%",
  #|     },
  #|     ".cm-content": {
  #|       caretColor: "var(--canopy-fg, #e4e4f0)",
  #|       padding: "16px",
  #|       minHeight: "100%",
  #|     },
  #|     "&.cm-focused": {
  #|       outline: "none",
  #|     },
  #|     ".cm-cursor": {
  #|       borderLeftColor: "var(--canopy-fg, #e4e4f0)",
  #|     },
  #|     ".cm-gutters": {
  #|       backgroundColor: "transparent",
  #|       color: "var(--canopy-muted, #8888a8)",
  #|       border: "none",
  #|     },
  #|     ".cm-activeLineGutter": {
  #|       backgroundColor: "transparent",
  #|       color: "var(--canopy-fg, #e4e4f0)",
  #|     },
  #|     ".cm-activeLine": {
  #|       backgroundColor: "rgba(255,255,255,0.03)",
  #|     },
  #|     ".peer-cursor-widget": {
  #|       position: "relative",
  #|       display: "inline",
  #|       borderLeft: "2px solid var(--color)",
  #|       marginLeft: "-1px",
  #|       pointerEvents: "none",
  #|     },
  #|     ".peer-cursor-label": {
  #|       position: "absolute",
  #|       bottom: "100%",
  #|       left: "-1px",
  #|       background: "var(--color)",
  #|       color: "#fff",
  #|       fontSize: "10px",
  #|       fontFamily: "system-ui, sans-serif",
  #|       padding: "1px 4px",
  #|       borderRadius: "2px 2px 2px 0",
  #|       whiteSpace: "nowrap",
  #|       pointerEvents: "none",
  #|       opacity: "0.9",
  #|     },
  #|     ".peer-selection": {
  #|       backgroundColor: "var(--color)",
  #|       opacity: "0.2",
  #|     },
  #|   });
  #|   const defaultKeymap = Array.isArray(cm.defaultKeymap) ? cm.defaultKeymap : [];
  #|   const keymap = cm.keymap.of([
  #|     {
  #|       key: "Mod-z",
  #|       run: () => {
  #|         click("canopy-editor-undo-trigger");
  #|         return true;
  #|       },
  #|     },
  #|     {
  #|       key: "Mod-Shift-z",
  #|       run: () => {
  #|         click("canopy-editor-redo-trigger");
  #|         return true;
  #|       },
  #|     },
  #|     {
  #|       key: "Mod-y",
  #|       run: () => {
  #|         click("canopy-editor-redo-trigger");
  #|         return true;
  #|       },
  #|     },
  #|     ...defaultKeymap,
  #|   ]);
  #|   const languageExtensions = normalizeExtensions(
  #|     globalThis.__canopy_create_lambda_cm_extensions,
  #|   );
  #|   const peerExtensions = normalizeExtensions(
  #|     globalThis.__canopy_create_cm_peer_cursor_extension,
  #|   );
  #|   return [theme, ...languageExtensions, keymap, ...peerExtensions];
  #| }

///|
#warnings("-unused_error_type")
fn js_make_ideal_cm_extension(cm : @js_value.Value) -> @cm_js.Extension raise {
  @cm_js.raw_extension(js_make_ideal_cm_extension_raw(cm))
}

///|
/// Broadcast and autosave after a local edit handled by MoonBit.
extern "js" fn js_after_local_text_edit() -> Unit =
  #| function() {
  #|   var el = document.querySelector('canopy-editor');
  #|   if (el && typeof el.notifyLocalChange === 'function') {
  #|     el.notifyLocalChange();
  #|   }
  #|   if (typeof globalThis.__canopy_trigger_autosave === 'function') {
  #|     globalThis.__canopy_trigger_autosave();
  #|   }
  #| }

///|
/// Broadcast local text-mode cursor/selection state from the binding.
extern "js" fn js_after_cm_selection_changed(from : Int, to : Int) -> Unit =
  #| function(from, to) {
  #|   const state = globalThis.__canopy_pending_cm_selection ?? {};
  #|   state.from = from;
  #|   state.to = to;
  #|   if (state.timer != null) {
  #|     globalThis.__canopy_pending_cm_selection = state;
  #|     return;
  #|   }
  #|   state.timer = setTimeout(() => {
  #|     state.timer = null;
  #|     globalThis.__canopy_pending_cm_selection = state;
  #|     var crdt = globalThis.__canopy_crdt;
  #|     var handle = globalThis.__canopy_crdt_handle;
  #|     var name = globalThis.__canopy_agent_name || "You";
  #|     var color = globalThis.__canopy_agent_color || "#8250df";
  #|     if (crdt && handle != null && typeof crdt.ephemeral_set_presence_with_selection === 'function') {
  #|       crdt.ephemeral_set_presence_with_selection(handle, name, color, state.from, state.to);
  #|     }
  #|     if (typeof globalThis.__canopy_broadcast_ephemeral === 'function') {
  #|       globalThis.__canopy_broadcast_ephemeral();
  #|     }
  #|   }, 50);
  #|   globalThis.__canopy_pending_cm_selection = state;
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
/// Structure mode focuses the ProseMirror view after selecting the node.
extern "js" fn js_set_editor_selected_node(node_id : String) -> Unit =
  #| function(node_id) {
  #|   var el = document.querySelector('canopy-editor');
  #|   if (el) el.selectedNode = node_id;
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
/// Focus the tree-rows div so keyboard navigation works after node clicks.
/// Called after editor selection updates when the outline should keep focus.
extern "js" fn js_focus_tree_rows() -> Unit =
  #| function() {
  #|   var el = document.querySelector('.tree-rows');
  #|   if (el) el.focus();
  #| }

///|
/// Start a named browser perf span for the current benchmark sample.
extern "js" fn js_perf_begin(name : String) -> Unit =
  #| function(name) {
  #|   var perf = globalThis.__canopy_perf_current;
  #|   if (!perf || !perf.spans) return;
  #|   if (!perf._starts) perf._starts = {};
  #|   perf._starts[name] = performance.now();
  #| }

///|
/// End a named browser perf span for the current benchmark sample.
extern "js" fn js_perf_end(name : String) -> Unit =
  #| function(name) {
  #|   var perf = globalThis.__canopy_perf_current;
  #|   if (!perf || !perf.spans || !perf._starts) return;
  #|   var start = perf._starts[name];
  #|   if (typeof start !== 'number') return;
  #|   perf.spans[name] = (perf.spans[name] || 0) + performance.now() - start;
  #|   delete perf._starts[name];
  #| }

// Note: editor event wiring is done in main.ts wireEditorEvents() — not here.
