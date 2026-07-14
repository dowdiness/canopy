///|
/// Read the agent ID from the host bridge installed before module import.
extern "js" fn js_get_agent_id() -> String =
  #| function() {
  #|   var id = globalThis.__canopy_bridge?.agentId;
  #|   return typeof id === 'string' ? id : '';
  #| }

///|
/// Current session-relative time in milliseconds for CRDT undo grouping.
/// Reads sessionStartMs from the host bridge so MoonBit and TypeScript share the same clock.
extern "js" fn js_now_ms() -> Int =
  #| function() {
  #|   var bridge = globalThis.__canopy_bridge;
  #|   var start = bridge?.sessionStartMs;
  #|   if (typeof start !== 'number') return 0;
  #|   var elapsed = Math.floor(Date.now() - start);
  #|   return Math.max(0, Math.min(2147483647, elapsed));
  #| }

///|
/// Build the ideal editor's CodeMirror extension from the exact CM namespace
/// passed by the rabbita binding.
extern "js" fn js_make_ideal_cm_extension_raw(
  cm : @js_value.Value,
) -> @js_value.Value =
  #| function(cm) {
  #|   const CANOPY_EVENT_REQUEST_UNDO = "request-undo";
  #|   const CANOPY_EVENT_REQUEST_REDO = "request-redo";
  #|   const dispatchTextEditorEvent = (eventType) => {
  #|     const target = document.getElementById("canopy-text-editor");
  #|     if (target && typeof target.dispatchEvent === "function") {
  #|       target.dispatchEvent(new CustomEvent(eventType, {
  #|         bubbles: true,
  #|         composed: true,
  #|       }));
  #|     }
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
  #|         dispatchTextEditorEvent(CANOPY_EVENT_REQUEST_UNDO);
  #|         return true;
  #|       },
  #|     },
  #|     {
  #|       key: "Mod-Shift-z",
  #|       run: () => {
  #|         dispatchTextEditorEvent(CANOPY_EVENT_REQUEST_REDO);
  #|         return true;
  #|       },
  #|     },
  #|     {
  #|       key: "Mod-y",
  #|       run: () => {
  #|         dispatchTextEditorEvent(CANOPY_EVENT_REQUEST_REDO);
  #|         return true;
  #|       },
  #|     },
  #|     ...defaultKeymap,
  #|   ]);
  #|   const languageExtensions = normalizeExtensions(
  #|     globalThis.__canopy_bridge?.createLambdaExtensions,
  #|   );
  #|   const peerExtensions = normalizeExtensions(
  #|     globalThis.__canopy_bridge?.createPeerCursorExtension,
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
  #|   var triggerAutosave = globalThis.__canopy_bridge?.triggerAutosave;
  #|   if (typeof triggerAutosave === 'function') {
  #|     triggerAutosave();
  #|   }
  #| }

///|
/// Broadcast local text-mode cursor/selection state from the binding.
extern "js" fn js_after_cm_selection_changed(from : Int, to : Int) -> Unit =
  #| function(from, to) {
  #|   var bridge = globalThis.__canopy_bridge;
  #|   if (!bridge) return;
  #|   var state = bridge._pendingCmSelection ?? {};
  #|   state.from = from;
  #|   state.to = to;
  #|   if (state.timer != null) {
  #|     bridge._pendingCmSelection = state;
  #|     return;
  #|   }
  #|   state.timer = setTimeout(function() {
  #|     state.timer = null;
  #|     bridge._pendingCmSelection = state;
  #|     if (typeof bridge.onSelectionChanged === 'function') {
  #|       bridge.onSelectionChanged(state.from, state.to);
  #|     }
  #|   }, 50);
  #|   bridge._pendingCmSelection = state;
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
  #|   var bridge = globalThis.__canopy_bridge;
  #|   if (bridge) bridge.overlayOpen = open;
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
/// Get viewport dimensions as JSON for overlay position clamping.
extern "js" fn js_get_viewport_size() -> String =
  #| function() {
  #|   if (typeof window === "undefined") return '{}';
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
  #|   var perf = globalThis.__canopy_bridge?.perfCurrent;
  #|   if (!perf || !perf.spans) return;
  #|   if (!perf._starts) perf._starts = {};
  #|   perf._starts[name] = performance.now();
  #| }

///|
/// End a named browser perf span for the current benchmark sample.
extern "js" fn js_perf_end(name : String) -> Unit =
  #| function(name) {
  #|   var perf = globalThis.__canopy_bridge?.perfCurrent;
  #|   if (!perf || !perf.spans || !perf._starts) return;
  #|   var start = perf._starts[name];
  #|   if (typeof start !== 'number') return;
  #|   perf.spans[name] = (perf.spans[name] || 0) + performance.now() - start;
  #|   delete perf._starts[name];
  #| }

// Note: editor event wiring is done in main.ts wireEditorEvents() — not here.
