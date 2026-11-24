// The Document index as the app hosts it: its cards are the Recent documents
// entries, and choosing one is a Document switch in the Editor behind it.

///|
/// What a URL fragment names, parsed once. Any other fragment, such as a
/// heading anchor followed in Preview, names nothing and leaves the screen.
priv enum IndexRoute {
  /// The Document index itself: no fragment, or `#/`.
  IndexPage
  NewFromIndex
  /// The document whose key the fragment holds.
  CardFromIndex(@documents.Key)
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
  } else if path.has_prefix("/d/") {
    @documents.Key::parse(path.view(start_offset=3).to_owned()).map(key => {
      CardFromIndex(key)
    })
  } else {
    None
  }
}

///|
fn document_href(key : @documents.Key) -> String {
  "#/d/\{key}"
}

///|
/// The screen Loomark starts on: the document a startup URL names, otherwise
/// the Document index.
fn startup_screen(url : @url.Url?) -> Screen {
  match url.bind(index_route) {
    Some(CardFromIndex(key)) => Requested(key)
    _ => Browsing({ opening: None, card_deletion: None, })
  }
}

///|
/// An index with nothing listed yet.
fn empty_index() -> @document_index.DocumentIndex[@documents.Key] {
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
  recent_document_seeds(editing, remote)
}

///|
/// Every document as the Document index lists it, most recently changed
/// first.
fn index_seeds(
  model : Model,
  editing : EditingDocument,
  opening : Opening?,
) -> Array[@document_index.Seed[@documents.Key]] {
  listed_documents(model, editing)
  .map(seed => {
    let key = seed.docid()
    @document_index.Seed::{
      key,
      href: document_href(key),
      text: seed.source(),
      status: seed.status(),
      deletion: seed.deletion(),
      loading: opening is Some({ card: Some(card), .. }) && card == key,
    }
  })
  .to_array()
}

///|
/// Whether the Document index lists the document of `key`, as one a URL names
/// may have been deleted since.
fn is_listed(
  model : Model,
  editing : EditingDocument,
  key : @documents.Key,
) -> Bool {
  listed_documents(model, editing).iter().any(seed => seed.docid() == key)
}

///|
/// What the screen does with a message before `reduce` sees it.
priv enum Browse {
  Handled(Model, @rabbita.Cmd)
  /// `msg`, or the opening intent a link stands for, goes on to `reduce`.
  Forward(Model, Msg)
}

///|
/// The index as the screen in front. Every `Browsing` screen is made here,
/// and the Editor comes to the front only through `enter_editor`, which
/// covers the index; `Leaving` and its way back to `Writing` keep it covered.
/// So the index is in front exactly while the screen is `Browsing`.
fn with_browsing(model : Model, browsing : Browsing) -> Model {
  { ..model, index: model.index.shown(), screen: Browsing(browsing), }
}

///|
/// The Editor comes to the front with its document, keeping the index behind
/// it. `entry` says how the document's history entry comes to exist.
fn enter_editor(
  model : Model,
  editing : EditingDocument,
  entry : Entry,
) -> (Model, @rabbita.Cmd) {
  let named = editing.activation.key
  let href = document_href(named)
  let (notes, history) = match entry {
    Pushed => (HistoryBack, @nav.replace_url(href))
    ToPush => (HistoryBack, @nav.push_url(href))
    Startup => (IndexEntry, @cmd.none)
  }
  (
    {
      ..model,
      index: model.index.covered(),
      screen: Writing({ notes, named, }),
    },
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
  let model = with_browsing(model, { opening: None, card_deletion: None, })
  let seeds = index_seeds(model, editing, None)
  {
    ..model,
    index: model.index.returned_from(seeds[:], key=editing.activation.key),
  }
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
        Some(CardFromIndex(key)) if key != editing.activation.key &&
          is_listed(model, editing, key) =>
          Forward(model, DocumentSelected(key))
        Some(CardFromIndex(_) | NewFromIndex) | None =>
          Handled(model, @cmd.none)
      }
    (Writing({ notes: HistoryBack, .. }), NotesRequested) =>
      Handled(model, @nav.back())
    (Writing({ notes: IndexEntry, .. }), NotesRequested) =>
      Handled(model, @nav.push_url("#/"))
    // Forward again before composition ended keeps the Editor in front.
    (Leaving, UrlChanged(url)) if index_route(url) is Some(CardFromIndex(key)) &&
      key == editing.activation.key =>
      Handled(
        {
          ..model,
          screen: Writing({ notes: HistoryBack, named: editing.activation.key, }),
        },
        @cmd.none,
      )
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
        Some(CardFromIndex(key)) if is_listed(model, editing, key) =>
          select_while_browsing(model, browsing, editing, key, Pushed)
        Some(CardFromIndex(_) | IndexPage) | None => Handled(model, @cmd.none)
      }
    DocumentSelected(key) =>
      select_while_browsing(model, browsing, editing, key, ToPush)
    CreateRequested | ExampleSelected(_, _) | ImportFilesSelected(_) =>
      open_while_browsing(model, browsing, editing, msg, None, ToPush)
    IndexDeleteRequested(key) =>
      Forward(
        with_browsing(model, { ..browsing, card_deletion: Some(key), }),
        DeleteRequested(key),
      )
    DeleteRequested(_) =>
      Forward(with_browsing(model, { ..browsing, card_deletion: None, }), msg)
    // Cancelling returns focus to the card's trash button, which asked.
    DeleteCancelled if browsing.card_deletion is Some(key) &&
      editing.deletion is DeleteConfirmation(_) =>
      Handled(
        with_browsing(
          { ..model, page: Editing({ ..editing, deletion: NoDeletion, }), },
          { ..browsing, card_deletion: None, },
        ),
        @browser.focus_after_render(@document_index.card_delete_dom_id(key)),
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
/// The screen in front once `model` has changed: the Editor once a document
/// chosen while browsing has opened; the index once Back waited for
/// composition to end; otherwise the screen as it is, with the index listing
/// what the Editor holds now and the URL naming the Editor's document.
///
/// The document a startup URL names is chosen as if from the index, so
/// `Forward` passes on the choice it needs. An empty repository opens on the
/// index too, with Welcome as its first card.
fn settle_screen(model : Model) -> Browse {
  match (model.screen, model.page) {
    (Requested(key), Editing(editing)) => {
      // Listed first, so returning finds the cards already in place.
      let model = {
        ..model,
        index: model.index.listing(index_seeds(model, editing, None)[:]),
      }
      let browsing = { opening: None, card_deletion: None, }
      if is_listed(model, editing, key) {
        select_while_browsing(
          with_browsing(model, browsing),
          browsing,
          editing,
          key,
          Startup,
        )
      } else {
        // A document that no longer exists opens the index, without a notice.
        Handled(with_browsing(model, browsing), @nav.replace_url("#/"))
      }
    }
    (Browsing({ opening: Some(opening), .. }), Editing(editing)) if editing.activation.generation >
      opening.generation => {
      let (model, command) = enter_editor(model, editing, opening.entry)
      Handled(model, command)
    }
    (Browsing(browsing), Editing(editing)) => {
      let seeds = index_seeds(model, editing, browsing.opening)
      match browsing.card_deletion {
        // The document deleted from its card is gone; focus takes its place.
        Some(key) if !seeds.iter().any(seed => seed.key == key) => {
          let (index, command) = model.index.removed(
            seeds[:],
            key~,
            announcement="Document deleted",
          )
          Handled(
            with_browsing({ ..model, index, }, {
              ..browsing,
              card_deletion: None,
            }),
            command,
          )
        }
        _ =>
          Handled({ ..model, index: model.index.listing(seeds[:]), }, @cmd.none)
      }
    }
    (Leaving, Editing(editing)) if !editing.documents.is_composing(
        editing.activation.key,
      ) => Handled(return_to_index(model, editing), @cmd.none)
    (Writing(writing), Editing(editing)) if writing.named !=
      editing.activation.key => {
      let named = editing.activation.key
      Handled(
        { ..model, screen: Writing({ ..writing, named, }), },
        @nav.replace_url(document_href(named)),
      )
    }
    _ => Handled(model, @cmd.none)
  }
}
