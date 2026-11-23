// The Document index as the app hosts it: its cards are the Recent documents
// entries, and choosing one is a Document switch in the Editor behind it.

///|
/// What a URL fragment names, parsed once. Any other fragment, such as a
/// heading anchor followed in Preview, names nothing and leaves the screen.
priv enum IndexRoute {
  /// The Document index itself: no fragment, or `#/`.
  IndexPage
  NewFromIndex
  /// The document of this lifecycle key.
  CardFromIndex(String)
}

///|
fn index_route(url : @url.Url) -> IndexRoute? {
  let fragment = url.fragment.unwrap_or("")
  let path = if fragment.has_prefix("#") {
    fragment.view(start_offset=1).to_owned()
  } else {
    fragment
  }
  if path == "" || path == "/" {
    Some(IndexPage)
  } else if path == "/new" {
    Some(NewFromIndex)
  } else if path.has_prefix("/d/") && path.length() > 3 {
    Some(CardFromIndex(path.view(start_offset=3).to_owned()))
  } else {
    None
  }
}

///|
fn document_href(lifecycle : String) -> String {
  "#/d/" + lifecycle
}

///|
/// The screen Loomark starts on: the document a startup URL names, otherwise
/// the Document index.
fn startup_screen(url : @url.Url?) -> Screen {
  match url.bind(index_route) {
    Some(CardFromIndex(lifecycle)) => Requested(lifecycle)
    _ => Browsing({ opening: None, card_deletion: None, })
  }
}

///|
/// An index with nothing listed yet.
fn empty_index() -> @document_index.DocumentIndex {
  @document_index.DocumentIndex([][:], new_href="#/new")
}

///|
/// The Recent documents entries, with documents being deleted kept in place.
fn listed_documents(
  model : Model,
  editing : EditingDocument,
) -> @vector.Vector[@recent_documents.Seed[@documents.Key]] {
  let remote = remote_document_seeds(
    remote_documents(model.sync()),
    document_membership(model.page),
  )
  recent_document_seeds(editing, remote, keep_pending=true)
}

///|
/// Every document as the Document index lists it, most recently changed
/// first.
fn index_seeds(
  model : Model,
  editing : EditingDocument,
  opening : Opening?,
) -> Array[@document_index.Seed] {
  listed_documents(model, editing)
  .map(seed => {
    let key = seed.docid()
    let lifecycle = key.lifecycle_key()
    @document_index.Seed::{
      key: lifecycle,
      href: document_href(lifecycle),
      text: seed.source(),
      status: seed.status(),
      deletion: seed.deletion(),
      loading: opening is Some({ card: Some(card), .. }) && card == key,
    }
  })
  .to_array()
}

///|
/// The listed document a card's lifecycle key names.
fn listed_key(
  model : Model,
  editing : EditingDocument,
  lifecycle : String,
) -> @documents.Key? {
  listed_documents(model, editing)
  .iter()
  .find_first(seed => seed.docid().lifecycle_key() == lifecycle)
  .map(seed => seed.docid())
}

///|
/// What the screen does with a message before `reduce` sees it.
priv enum Browse {
  Handled(Model, @rabbita.Cmd)
  /// `msg`, or the opening intent a link stands for, goes on to `reduce`.
  Forward(Model, Msg)
}

///|
fn with_browsing(model : Model, browsing : Browsing) -> Model {
  { ..model, screen: Browsing(browsing), }
}

///|
/// The Editor comes to the front with its document, keeping the index behind
/// it. `entry` says how the document's history entry comes to exist.
fn enter_editor(
  model : Model,
  editing : EditingDocument,
  entry : Entry,
) -> (Model, @rabbita.Cmd) {
  let href = document_href(editing.activation.key.lifecycle_key())
  let (notes, history) = match entry {
    Pushed => (HistoryBack, @nav.replace_url(href))
    ToPush => (HistoryBack, @nav.push_url(href))
    Startup => (IndexEntry, @cmd.none)
  }
  (
    { ..model, screen: Writing(notes), },
    @cmd.batch([history, focus_editor_after_render(editing.mode)]),
  )
}

///|
/// `msg` opens a document; the Editor comes to the front once it has.
fn open_while_browsing(
  model : Model,
  browsing : Browsing,
  editing : EditingDocument,
  msg : Msg,
  card : @documents.Key?,
  entry : Entry,
) -> Browse {
  let opening = { generation: editing.activation.generation, card, entry, }
  Forward(with_browsing(model, { ..browsing, opening: Some(opening), }), msg)
}

///|
/// The index in front again after the Editor held `editing`'s document.
fn return_to_index(model : Model, editing : EditingDocument) -> Model {
  let seeds = index_seeds(model, editing, None)
  let index = model.index.returned_from(
    seeds[:],
    key=editing.activation.key.lifecycle_key(),
  )
  { ..model, index, screen: Browsing({ opening: None, card_deletion: None, }), }
}

///|
fn browse(model : Model, msg : Msg) -> Browse {
  if msg is IndexMsg(event) {
    let (index, command) = model.index.update(event)
    return Handled({ ..model, index, }, command)
  }
  guard model.page is Editing(editing) else { return Forward(model, msg) }
  match (model.screen, msg) {
    (Browsing(browsing), msg) => browse_index(model, browsing, editing, msg)
    (Writing(_), UrlChanged(url)) =>
      match index_route(url) {
        Some(IndexPage) =>
          if editing.documents.is_composing(editing.activation.key) {
            Handled({ ..model, screen: Leaving, }, @cmd.none)
          } else {
            Handled(return_to_index(model, editing), @cmd.none)
          }
        Some(CardFromIndex(lifecycle)) =>
          match listed_key(model, editing, lifecycle) {
            Some(key) if key != editing.activation.key =>
              Forward(model, DocumentSelected(key))
            _ => Handled(model, @cmd.none)
          }
        Some(NewFromIndex) | None => Handled(model, @cmd.none)
      }
    (Writing(HistoryBack), NotesRequested) => Handled(model, @nav.back())
    (Writing(IndexEntry), NotesRequested) => Handled(model, @nav.push_url("#/"))
    // Forward again before composition ended keeps the Editor in front.
    (Leaving, UrlChanged(url)) if index_route(url)
      is Some(CardFromIndex(lifecycle)) &&
      lifecycle == editing.activation.key.lifecycle_key() =>
      Handled({ ..model, screen: Writing(HistoryBack), }, @cmd.none)
    (
      _,
      UrlRequested(_)
      | UrlChanged(_)
      | IndexDeleteRequested(_)
      | NotesRequested,
    ) => Handled(model, @cmd.none)
    _ => Forward(model, msg)
  }
}

///|
fn browse_index(
  model : Model,
  browsing : Browsing,
  editing : EditingDocument,
  msg : Msg,
) -> Browse {
  match msg {
    UrlRequested(Internal(url)) =>
      Handled(model, @nav.push_url("#" + url.fragment.unwrap_or("/")))
    UrlRequested(External(href)) => Handled(model, @nav.load(href))
    UrlChanged(url) =>
      match index_route(url) {
        Some(NewFromIndex) =>
          open_while_browsing(
            model,
            browsing,
            editing,
            CreateRequested,
            None,
            Pushed,
          )
        Some(CardFromIndex(lifecycle)) =>
          match listed_key(model, editing, lifecycle) {
            Some(key) =>
              select_while_browsing(model, browsing, editing, key, Pushed)
            None => Handled(model, @cmd.none)
          }
        Some(IndexPage) | None => Handled(model, @cmd.none)
      }
    DocumentSelected(key) =>
      select_while_browsing(model, browsing, editing, key, ToPush)
    CreateRequested | ExampleSelected(_, _) | ImportFilesSelected(_) =>
      open_while_browsing(model, browsing, editing, msg, None, ToPush)
    IndexDeleteRequested(lifecycle) =>
      match listed_key(model, editing, lifecycle) {
        Some(key) =>
          Forward(
            with_browsing(model, { ..browsing, card_deletion: Some(key), }),
            DeleteRequested(key),
          )
        None => Handled(model, @cmd.none)
      }
    DeleteRequested(_) =>
      Forward(with_browsing(model, { ..browsing, card_deletion: None, }), msg)
    // Cancelling returns focus to the card's trash button, which asked.
    DeleteCancelled if browsing.card_deletion is Some(key) &&
      editing.deletion is DeleteConfirmation(_) =>
      Handled(
        {
          ..model,
          page: Editing({ ..editing, deletion: NoDeletion, }),
          screen: Browsing({ ..browsing, card_deletion: None, }),
        },
        @browser.focus_after_render(
          @document_index.card_delete_dom_id(key.lifecycle_key()),
        ),
      )
    NotesRequested => Handled(model, @cmd.none)
    _ => Forward(model, msg)
  }
}

///|
fn select_while_browsing(
  model : Model,
  browsing : Browsing,
  editing : EditingDocument,
  key : @documents.Key,
  entry : Entry,
) -> Browse {
  if key == editing.activation.key {
    let (model, command) = enter_editor(model, editing, entry)
    Handled(model, command)
  } else {
    open_while_browsing(
      model,
      browsing,
      editing,
      DocumentSelected(key),
      Some(key),
      entry,
    )
  }
}

///|
/// The screen in front after `previous` became `model`: the Editor once a
/// document chosen while browsing has opened, or when the startup URL names
/// a document; the index once Back waited for composition to end; otherwise
/// the index, listing what the Editor holds now. An empty repository opens
/// on the index too, with Welcome as its first card.
fn settle_screen(
  previous : Model,
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  match (model.screen, model.page) {
    (Requested(lifecycle), Editing(editing)) =>
      match listed_key(model, editing, lifecycle) {
        Some(key) => {
          let model = {
            ..model,
            index: model.index.listing(index_seeds(model, editing, None)[:]),
          }
          let (model, command) = enter_editor(model, editing, Startup)
          let select = if key == editing.activation.key {
            @cmd.none
          } else {
            emit(DocumentSelected(key))
          }
          (model, @cmd.batch([command, select]))
        }
        // A document that no longer exists opens the index, without a notice.
        None =>
          (
            with_browsing(model, { opening: None, card_deletion: None, }),
            @nav.replace_url("#/"),
          )
      }
    (Browsing({ opening: Some(opening), .. }), Editing(editing)) if editing.activation.generation >
      opening.generation => enter_editor(model, editing, opening.entry)
    (Browsing(browsing), Editing(editing)) => {
      let seeds = index_seeds(model, editing, browsing.opening)
      match browsing.card_deletion {
        // The document deleted from its card is gone; focus takes its place.
        Some(key) if !seeds.iter().any(seed => seed.key == key.lifecycle_key()) => {
          let (index, command) = model.index.removed(
            seeds[:],
            key=key.lifecycle_key(),
            announcement="Document deleted",
          )
          (
            {
              ..model,
              index,
              screen: Browsing({ ..browsing, card_deletion: None, }),
            },
            command,
          )
        }
        _ => ({ ..model, index: model.index.listing(seeds[:]), }, @cmd.none)
      }
    }
    (Leaving, Editing(editing)) if !editing.documents.is_composing(
        editing.activation.key,
      ) => (return_to_index(model, editing), @cmd.none)
    // The URL names whichever document the Editor holds, replacing its entry
    // on a Document switch.
    (Writing(_), Editing(editing)) if !(previous.screen is Writing(_) &&
      previous.page is Editing(before) &&
      before.activation.key == editing.activation.key) =>
      (
        model,
        @nav.replace_url(document_href(editing.activation.key.lifecycle_key())),
      )
    _ => (model, @cmd.none)
  }
}
