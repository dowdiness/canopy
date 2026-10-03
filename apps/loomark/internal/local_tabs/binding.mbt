///| Experimental browser shell; no ordinary repository or account initialization.

///|
pub extern "js" fn enabled() -> Bool =
  #| () => typeof location !== 'undefined' && new URLSearchParams(location.search).get('local-tabs-worker') === '1'

///|
extern "js" fn mounted() =
  #| () => {
  #|   const element=document.getElementById('loomark-text');
  #|   if(!globalThis.localTabs){element.readOnly=true;document.getElementById('status').textContent='Experimental assets unavailable. Use the isolated trial build.';return;}
  #|   globalThis.localTabs.mount(element);
  #| }

///|
extern "js" fn disposed() =
  #| () => globalThis.localTabs?.dispose()

///|
extern "js" fn input_change(
  start : Int,
  deleted : Int,
  inserted : String,
  full : Bool,
) =
  #| (start,deleted,inserted,full) => globalThis.localTabs?.onChange({start,deleted,inserted,full})

///|
extern "js" fn composing(value : Bool) =
  #| value => globalThis.localTabs?.onComposing(value)

///|
priv suberror LocalTabsLifetime {
  LocalTabsLifetime
}

///|
fn lifetime() -> @sub.Sub {
  @sub.custom_sub(
    "loomark-local-tabs-experiment",
    @sub.Scope::Local,
    LocalTabsLifetime,
    @sub.SubLoader((_, _) => {
      Some({ unload: _ => disposed(), update_tagger: _ => (), })
    }),
  )
}

///|
fn admit(
  editor : @editor.MarkdownEditor,
  input : @editor.InputEdit,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    match editor.admit(input) {
      Some(ReplaceRange(start~, delete_len~, inserted~)) =>
        input_change(start, delete_len, inserted, false)
      Some(ReplaceAll(text)) => input_change(0, 0, text, true)
      None => ()
    }
  })
}

///|
pub fn app() -> @rabbita.Val[@rabbita.Html] {
  let editor = @editor.MarkdownEditor::MarkdownEditor("loomark-text")
  let (_model, _emit) : (@rabbita.Val[Int], @cmd.Emit[Int]) = @rabbita.create_state_with_init(
    init=_ => (0, @cmd.custom_cmd(_ => mounted(), kind=@cmd.after_render)),
    update=(model, _, _) => (model, @cmd.none),
    subscriptions=(_, _) => lifetime(),
  )
  @rabbita.Val::constant(
    @html.div(class="loomark-experiment", [
      @html.header([
        @html.h1("Loomark"),
        @html.span("Local tabs — experimental Text mode"),
        @html.span(id="status", "Restoring — editor is read-only"),
      ]),
      @html.nav([
        @html.input(
          id="document-name",
          value="synthetic-demo",
          attrs=@html.Attrs::build().aria_label("Synthetic document name"),
        ),
        @html.button(id="switch", "Open synthetic document"),
        @html.button(id="undo", "Undo my edit"),
        @html.button(id="redo", "Redo"),
        @html.button(id="retry", "Retry"),
        @html.button(id="export", "Export draft"),
      ]),
      @html.p(
        "Synthetic documents only. No account or cloud synchronization. Open this URL in another tab.",
      ),
      @html.div(class="loomark-source-frame", [
        editor.input_view(
          "Text",
          input => admit(editor, input),
          value => @cmd.custom_cmd(_ => composing(value)),
          read_only=true,
          class="loomark-source",
        ),
      ]),
      @html.p(
        id="alignment",
        "Remote selection uses text alignment; repeated-character provenance remains ambiguous.",
      ),
      @html.p(id="diagnostics", ""),
      @html.p(
        "Undo belongs to this tab. Worker restart clears its Undo stack; concurrent-delete Undo may revive text another tab deleted.",
      ),
    ]),
  )
}
