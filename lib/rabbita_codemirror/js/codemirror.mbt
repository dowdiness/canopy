///|
/// Raw FFI layer for the CodeMirror–Rabbita binding.
///
/// Every `extern "js"` declaration targeting `@codemirror/*` lives here.
/// Opaque JS handles are wrapped as `struct T(@js_value.Value)` newtypes and
/// re-exported to the managed layer.

///|
/// Opaque handle to a loaded CodeMirror ES module. Returned (boxed) by
/// `load_codemirror`'s resolved Promise; threaded explicitly to every op
/// that needs to reach into the module (`js_create_view`,
/// `js_compartment_new`). Binding the module per-view eliminates the
/// "multiple `@codemirror/state` instances" hazard you get from a global.
pub struct CmModule(@js_value.Value)

///|
/// Construct a `CmModule` from the resolved value of
/// `load_codemirror`'s Promise. Use it like:
///
/// ```moonbit nocheck
/// let cm = cm_module_of(load_codemirror(source~).wait())
/// ```
pub fn cm_module_of(value : @js_value.Value) -> CmModule {
  CmModule(value)
}

///|
pub struct CmView(@js_value.Value)

///|
pub struct TransactionSpec(@js_value.Value)

///|
pub struct Compartment(@js_value.Value)

///|
pub struct Extension(@js_value.Value)

///|
pub struct Disposable(() -> Unit)

///|
pub fn Disposable::dispose(self : Disposable) -> Unit {
  (self.0)()
}

///|
/// Wrap an externally constructed CodeMirror extension.
///
/// This is the plug-in escape hatch for language packages and other advanced
/// CodeMirror extensions that are built on the JavaScript side.
pub fn raw_extension(value : @js_value.Value) -> Extension {
  Extension(value)
}

///|
/// Dynamically load a CodeMirror 6 namespace from `source`. The returned
/// Promise resolves to that merged namespace object; wrap it with
/// `cm_module_of` to get a `CmModule` handle.
///
/// For bundled/offline apps, pass `source="global:<name>"` after setting
/// `globalThis[<name>]` to an object containing the CodeMirror state, view,
/// and commands exports.
///
/// Otherwise, `source` is a CDN base URL — the loader appends
/// `@codemirror/state@6`, `@codemirror/view@6`, and
/// `@codemirror/commands@6` to it.
///
/// `https://esm.sh/codemirror@6` metapackage exports only a `default`
/// (the `basicSetup` bundle); it does NOT re-export `Compartment`,
/// `EditorView`, `EditorState`, or `StateEffect`, which the binding's
/// FFI needs. Loading the granular sub-packages and merging keeps the
/// `CmModule` API a single `cm.X`-shaped object the FFI bodies can
/// access uniformly.
///
/// **Multi-version hazard (future):** When language or theme packages
/// are added beyond state/view/commands, each may bring its own
/// transitive `@codemirror/state`, and the resulting "multiple
/// instances of @codemirror/state" runtime error is one of CM6's
/// classic foot-guns. `source` must be a query-free CDN base URL
/// (path only): this loader normalizes a trailing slash, then appends
/// `@codemirror/state@6`, `@codemirror/view@6`, and
/// `@codemirror/commands@6` by string concatenation, so query strings
/// would corrupt the import path. A multi-version mitigation should be
/// designed if the hazard surfaces; pre-1.0 the bare base URL is
/// sufficient since the three currently-loaded packages agree.
///
/// Module loads are memoized per `source` so concurrent calls during
/// startup share a single import. Rejected imports are evicted from the
/// cache so a transient CDN failure does not poison every later call.
pub extern "js" fn load_codemirror(
  source? : String = "https://esm.sh",
) -> @js_value.Promise =
  #| async (source) => {
  #|   const key = Symbol.for("dowdiness.rabbita_codemirror");
  #|   const slot = globalThis[key] ?? (globalThis[key] = {
  #|     modules: new Map(),
  #|     applying: new WeakMap(),
  #|   });
  #|   if (!slot.modules.has(source)) {
  #|     const load = source.startsWith('global:')
  #|       ? Promise.resolve().then(() => {
  #|           const name = source.slice('global:'.length);
  #|           const value = globalThis[name];
  #|           if (!value || typeof value !== 'object') {
  #|             throw new Error(`CodeMirror global source not found: ${source}`);
  #|           }
  #|           return value;
  #|         })
  #|       : (() => {
  #|           const base = source.endsWith('/') ? source : source + '/';
  #|           return Promise.all([
  #|             import(/* @vite-ignore */ base + '@codemirror/state@6'),
  #|             import(/* @vite-ignore */ base + '@codemirror/view@6'),
  #|             import(/* @vite-ignore */ base + '@codemirror/commands@6'),
  #|           ]).then(([state, view, commands]) => ({ ...state, ...view, ...commands }));
  #|         })();
  #|     const p = load.catch(err => {
  #|       slot.modules.delete(source);
  #|       throw err;
  #|     });
  #|     slot.modules.set(source, p);
  #|   }
  #|   return await slot.modules.get(source);
  #| }

///|
extern "js" fn js_create_view_raw(
  cm : @js_value.Value,
  host_id : String,
  init_doc : String,
  extension : @js_value.Value,
) -> @js_value.Value =
  #| (cm, hostId, initDoc, extension) => {
  #|   const parent = document.getElementById(hostId);
  #|   if (!parent) {
  #|     throw new Error(`CodeMirror host not found: ${hostId}`);
  #|   }
  #|   parent.textContent = "";
  #|   const view = new cm.EditorView({
  #|     parent,
  #|     state: cm.EditorState.create({
  #|       doc: initDoc,
  #|       extensions: extension,
  #|     }),
  #|   });
  #|   view._cmModule = cm;
  #|   const key = Symbol.for("dowdiness.rabbita_codemirror");
  #|   const slot = globalThis[key] ?? (globalThis[key] = {
  #|     modules: new Map(),
  #|     applying: new WeakMap(),
  #|   });
  #|   if (!slot.applying.has(view)) {
  #|     slot.applying.set(view, { value: false });
  #|   }
  #|   return view;
  #| }

///|
pub fn js_create_view(
  cm : CmModule,
  host_id : String,
  init_doc : String,
  extension : Extension,
) -> CmView {
  CmView(js_create_view_raw(cm.0, host_id, init_doc, extension.0))
}

///|
extern "js" fn js_dispatch_raw(
  view : @js_value.Value,
  spec : @js_value.Value,
) -> Unit =
  #| (view, spec) => {
  #|   const key = Symbol.for("dowdiness.rabbita_codemirror");
  #|   const slot = globalThis[key] ?? (globalThis[key] = {
  #|     modules: new Map(),
  #|     applying: new WeakMap(),
  #|   });
  #|   let cell = slot.applying.get(view);
  #|   if (!cell) {
  #|     cell = { value: false };
  #|     slot.applying.set(view, cell);
  #|   }
  #|   cell.value = true;
  #|   try {
  #|     view.dispatch(spec);
  #|   } finally {
  #|     cell.value = false;
  #|   }
  #| }

///|
pub fn js_dispatch(view : CmView, spec : TransactionSpec) -> Unit {
  js_dispatch_raw(view.0, spec.0)
}

///|
extern "js" fn js_replace_doc_minimal_raw(
  view : @js_value.Value,
  doc : String,
) -> Unit =
  #| (view, nextDoc) => {
  #|   const current = view.state.doc.toString();
  #|   if (current === nextDoc) return;
  #|
  #|   let from = 0;
  #|   const maxPrefix = Math.min(current.length, nextDoc.length);
  #|   while (from < maxPrefix && current.charCodeAt(from) === nextDoc.charCodeAt(from)) {
  #|     from++;
  #|   }
  #|
  #|   let suffix = 0;
  #|   const maxSuffix = Math.min(current.length - from, nextDoc.length - from);
  #|   while (
  #|     suffix < maxSuffix &&
  #|     current.charCodeAt(current.length - suffix - 1) ===
  #|       nextDoc.charCodeAt(nextDoc.length - suffix - 1)
  #|   ) {
  #|     suffix++;
  #|   }
  #|
  #|   const to = current.length - suffix;
  #|   const insert = nextDoc.slice(from, nextDoc.length - suffix);
  #|   const key = Symbol.for("dowdiness.rabbita_codemirror");
  #|   const slot = globalThis[key] ?? (globalThis[key] = {
  #|     modules: new Map(),
  #|     applying: new WeakMap(),
  #|   });
  #|   let cell = slot.applying.get(view);
  #|   if (!cell) {
  #|     cell = { value: false };
  #|     slot.applying.set(view, cell);
  #|   }
  #|   cell.value = true;
  #|   try {
  #|     view.dispatch({ changes: { from, to, insert } });
  #|   } finally {
  #|     cell.value = false;
  #|   }
  #| }

///|
pub fn js_replace_doc_minimal(view : CmView, doc : String) -> Unit {
  js_replace_doc_minimal_raw(view.0, doc)
}

///|
extern "js" fn js_view_destroy_raw(view : @js_value.Value) -> Unit =
  #| (view) => view.destroy()

///|
pub fn js_view_destroy(view : CmView) -> Unit {
  js_view_destroy_raw(view.0)
}

///|
extern "js" fn js_state_doc_raw(view : @js_value.Value) -> String =
  #| (view) => view.state.doc.toString()

///|
pub fn js_state_doc(view : CmView) -> String {
  js_state_doc_raw(view.0)
}

///|
extern "js" fn js_state_selection_main_raw(
  view : @js_value.Value,
) -> @js_value.Value =
  #| (view) => {
  #|   const sel = view.state.selection.main;
  #|   return {
  #|     from: sel.from,
  #|     to: sel.to,
  #|     anchor: sel.anchor,
  #|     head: sel.head,
  #|   };
  #| }

///|
pub fn js_state_selection_main(view : CmView) -> @js_value.Value {
  js_state_selection_main_raw(view.0)
}

///|
extern "js" fn js_compartment_new_raw(cm : @js_value.Value) -> @js_value.Value =
  #| (cm) => new cm.Compartment()

///|
pub fn js_compartment_new(cm : CmModule) -> Compartment {
  Compartment(js_compartment_new_raw(cm.0))
}

///|
extern "js" fn js_compartment_of_raw(
  compartment : @js_value.Value,
  extension : @js_value.Value,
) -> @js_value.Value =
  #| (compartment, extension) => compartment.of(extension)

///|
pub fn js_compartment_of(
  compartment : Compartment,
  extension : Extension,
) -> Extension {
  Extension(js_compartment_of_raw(compartment.0, extension.0))
}

///|
extern "js" fn js_compartment_reconfigure_raw(
  compartment : @js_value.Value,
  extension : @js_value.Value,
) -> @js_value.Value =
  #| (compartment, extension) => ({
  #|   effects: compartment.reconfigure(extension),
  #| })

///|
pub fn js_compartment_reconfigure(
  compartment : Compartment,
  extension : Extension,
) -> TransactionSpec {
  TransactionSpec(js_compartment_reconfigure_raw(compartment.0, extension.0))
}

///|
extern "js" fn js_extension_combine_raw(
  extensions : Array[@js_value.Value],
) -> @js_value.Value =
  #| (extensions) => extensions

///|
pub fn js_extension_combine(extensions : Array[Extension]) -> Extension {
  js_extension_combine_raw(extensions.map(fn(extension) { extension.0 }))
  |> Extension
}

///|
extern "js" fn js_add_update_listener_raw(
  view : @js_value.Value,
  compartment : @js_value.Value,
  on_doc : (@js_value.Value) -> Unit,
  on_selection : (@js_value.Value) -> Unit,
  on_focus_change : (@js_value.Value) -> Unit,
) -> () -> Unit =
  #| (view, compartment, onDoc, onSelection, onFocusChange) => {
  #|   const key = Symbol.for("dowdiness.rabbita_codemirror");
  #|   const slot = globalThis[key];
  #|   const cm = view._cmModule;
  #|   if (!cm) {
  #|     throw new Error("Listener attach requires a view created via js_create_view");
  #|   }
  #|   const isApplying = () => !!slot.applying.get(view)?.value;
  #|   const listener = cm.EditorView.updateListener.of(update => {
  #|     if (update.docChanged && !isApplying()) {
  #|       onDoc(update.state.doc.toString());
  #|     }
  #|     if ((update.selectionSet || update.docChanged) && !isApplying()) {
  #|       const sel = update.state.selection.main;
  #|       onSelection({
  #|         from: sel.from,
  #|         to: sel.to,
  #|         anchor: sel.anchor,
  #|         head: sel.head,
  #|       });
  #|     }
  #|     if (update.focusChanged && !isApplying()) {
  #|       onFocusChange(!!update.view.hasFocus);
  #|     }
  #|   });
  #|   js_apply_guarded(view, () => {
  #|     view.dispatch({
  #|       effects: compartment.reconfigure(listener),
  #|     });
  #|   });
  #|   let disposed = false;
  #|   return () => {
  #|     if (disposed) return;
  #|     disposed = true;
  #|     js_apply_guarded(view, () => {
  #|       view.dispatch({ effects: compartment.reconfigure([]) });
  #|     });
  #|   };
  #|
  #|   function js_apply_guarded(view, run) {
  #|     let cell = slot.applying.get(view);
  #|     if (!cell) {
  #|       cell = { value: false };
  #|       slot.applying.set(view, cell);
  #|     }
  #|     cell.value = true;
  #|     try {
  #|       run();
  #|     } finally {
  #|       cell.value = false;
  #|     }
  #|   }
  #| }

///|
pub fn js_add_update_listener(
  view : CmView,
  compartment : Compartment,
  on_doc : (@js_value.Value) -> Unit,
  on_selection : (@js_value.Value) -> Unit,
  on_focus_change : (@js_value.Value) -> Unit,
) -> Disposable {
  Disposable(
    js_add_update_listener_raw(
      view.0,
      compartment.0,
      on_doc,
      on_selection,
      on_focus_change,
    ),
  )
}
