///|
using @rabbita {type Html, type Val}

///|
/// The editor exists only while a note or a New document is open.
fn editor_view(editor : Editor, emit : Emit[Msg]) -> Html {
  let (text, name) = match editor {
    Writing(session) => (session.note.text, derived_name(session.note))
    Drafting => ("", "New document")
  }
  @html.section(
    id="editor",
    class="editor",
    attrs=@html.Attrs::build().aria_label("Editor"),
    [
      @html.header(class="bar", [
        @html.a(href="#/", class="back", title="Back to notes (Esc)", [
          @html.span(
            class="back-arrow",
            attrs=@html.Attrs::build().aria_hidden("true"),
            "←",
          ),
          @html.text("Notes"),
        ]),
        @html.span(class="editor-name", name),
      ]),
      @html.textarea(
        id="editor-text",
        value=text,
        placeholder="Start writing…",
        on_input=text => emit(Edited(editor, text)),
        attrs=@html.Attrs::build()
          .aria_label("Document text")
          .spellcheck(false)
          .on_keydown(event => {
            if is_leaving_key(@browser.key_press(event)) {
              emit(EditorLeft)
            } else {
              @cmd.none
            }
          }),
        @html.nothing,
      ),
    ],
  )
}

///|
/// The editor page. Opening it moves focus into its text, from note to note
/// or the New document alike, until it is left.
fn editor_page(editing : Val[Editor?], emit : Emit[Msg]) -> Val[Html] {
  let _ = @rabbita.create_state_with_init(
    init=_ => ((), @browser.focus_after_render("editor-text")),
    update=(_, _ : Unit, _) => ((), @cmd.none),
  )
  editing.view(editor => {
    match editor {
      Some(editor) => editor_view(editor, emit)
      // The branch is disposed as the page leaves the editor.
      None => @html.nothing
    }
  })
}

///|
/// The Document index with the editor over it while a note is open.
fn view(model : Val[Model], emit : Emit[Msg]) -> Val[Html] {
  // Under the editor the index stays laid out but invisible, so its cards
  // slide from where they were when it is shown again.
  let covered = model.map(model => !(model.page is Index))
  let index = @document_index.view(
      model.map(model => model.index),
      on_delete=emit.map(id => DeleteRequested(id)),
      emit.map(msg => IndexMsg(msg)),
    )
    .map2(covered, (index, covered) => {
      @html.div(class=if covered { "index-host covered" } else { "index-host" }, [
        index,
      ])
    })
  let editing = model.map(model => {
    match model.page {
      Editing(editor) => Some(editor)
      Index => None
    }
  })
  // A branch per page, so the editor exists from opening to leaving.
  let editor = editing.switch_by(
    editor => {
      match editor {
        Some(_) => editor_page(editing, emit)
        None => Val::constant(@html.nothing)
      }
    },
    by=editor => if editor is Some(_) { "editor" } else { "index" },
  )
  let confirmation = model
    .map(model => model.deletion)
    .view(deletion => delete_dialog(deletion, emit))
  index.view3(editor, confirmation, (index, editor, confirmation) => {
    @html.div([index, editor, confirmation])
  })
}

///|
/// Escape leaves the editor, except while it confirms an IME composition.
fn is_leaving_key(press : @browser.KeyPress) -> Bool {
  press.key == "Escape" && !press.composing
}

///|
/// The Delete confirmation, kept in the page and shown by `@dialog.show`.
/// Its buttons and Escape send messages in the order they happen, so a
/// request that follows an answer at once is never taken for a stale one.
fn delete_dialog(deletion : Deletion, emit : Emit[Msg]) -> Html {
  let name = match deletion {
    Confirming(note) | Deleting(note) => derived_name(note)
    NoDeletion => ""
  }
  @html.dialog(
    id=DELETE_DIALOG_ID,
    class="confirm",
    on_cancel=emit(DeleteCancelled),
    attrs=@html.Attrs::build()
      .aria_labelledby("delete-document-title")
      .aria_describedby("delete-document-description"),
    [
      @html.h2(id="delete-document-title", "Delete \"\{name}\"?"),
      @html.p(
        id="delete-document-description",
        "This removes the document from this browser.",
      ),
      @html.div(class="confirm-actions", [
        @html.button(
          type_="button",
          class="confirm-cancel",
          on_click=emit(DeleteCancelled),
          "Cancel",
        ),
        @html.button(
          type_="button",
          class="confirm-delete",
          on_click=emit(DeleteConfirmed),
          "Delete document",
        ),
      ]),
    ],
  )
}
