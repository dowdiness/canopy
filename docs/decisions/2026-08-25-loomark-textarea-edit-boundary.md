# Keep browser textarea editing in Loomark

Status: accepted

Loomark owns one long-lived `TextArea` outside its Rabbita Model. `TextArea` composes Rabbita's typed browser event handlers, interprets each native input sequence synchronously, and emits the shared text-change module's `TextChange`: either an exact UTF-16 `ReplaceRange` or an automatic `ReplaceAll` containing the textarea's current value. This preserves native textarea behavior, keeps Document text as the only editing authority, and avoids complete value reads and source diff on the ordinary path.

## Consequences

Rabbita provides truthful low-level browser bindings: nullable input data and a typed `HTMLTextAreaElement` with the coherent browser text-and-selection capability. Its incorrect unused `InputEvent::data() -> String` is replaced by `InputEvent::get_data() -> @js.Nullable[String]` without a compatibility alias. Genuine optional Web IDL arguments use `@js.Optional`; overloaded methods remain separate; Web IDL string enums remain `String` rather than introducing MoonBit enums.

The shared text-change module owns the `ReplaceRange | ReplaceAll` representation and its application to a String; Loomark does not define another edit type. Its existing public struct is replaced atomically by the enum, without compatibility aliases or deprecated constructors. The module is not independently published, so this repository migration does not change its `0.1.0` version. Canopy's existing `SpanEdit` remains unchanged in this work and requires a separate range-only invariant review before any consolidation.

Loomark owns input-type interpretation, IME sequencing, automatic `ReplaceAll`, Document transition, and Autosave. During IME composition, intermediate `beforeinput` and `input` events do not update Document text or Autosave; `compositionend` emits one change. While the browser owns undo and redo, Loomark reads the resulting complete textarea value and emits `ReplaceAll`; it does not maintain a shadow history that guesses native grouping. If Loomark later owns undo and redo, its known forward and inverse operations emit `ReplaceRange` instead.

Loomark does not store `TextArea`, callbacks, commands, or history in its Model. If `TextArea::initialize` or `TextArea::value` cannot resolve its constructor-owned ID to an `HTMLTextAreaElement`, the command stops with an explicit programming error; the interface does not expose a nullable result or retry.

A future Preview integration advances its long-lived Loom Parser with `Parser::apply_edit` for `ReplaceRange` and `Parser::set_source` for `ReplaceAll`; it does not recreate the Parser or manufacture a whole-document incremental edit. Preview remains outside this implementation change.
