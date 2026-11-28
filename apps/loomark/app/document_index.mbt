// The Document index as the app hosts it: its cards are the Recent documents
// entries, and choosing one is a Document switch in the Editor behind it.

///|
/// What a URL fragment names, parsed once. Any other fragment, such as a
/// heading anchor followed in Preview, names nothing and leaves the screen.
priv enum IndexRoute {
  /// The Document index itself: no fragment, or `#/`.
  IndexPage
  NewFromIndex
  /// Today's daily note, found or created when followed.
  TodayFromIndex
  /// Resume in front of the cards.
  ResumePage
  /// The document whose key the fragment holds.
  CardFromIndex(@documents.Key)
}

///|
fn index_route(url : @url.Url) -> IndexRoute? {
  let fragment = url.fragment.unwrap_or("")
  let path = if fragment.has_prefix("#") {
    fragment.exact_view(start=1).to_owned()
  } else {
    fragment
  }
  if path == "" || path == "/" {
    Some(IndexPage)
  } else if path == "/new" {
    Some(NewFromIndex)
  } else if path == "/today" {
    Some(TodayFromIndex)
  } else if path == "/resume" {
    Some(ResumePage)
  } else if path.has_prefix("/d/") {
    @documents.Key::parse(path.exact_view(start=3).to_owned()).map(key => {
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
    route =>
      Browsing({
        opening: None,
        card_deletion: None,
        resuming: route is Some(ResumePage),
      })
  }
}

///|
/// An index with nothing listed yet.
fn empty_index() -> @document_index.DocumentIndex[@documents.Key] {
  @document_index.DocumentIndex(
    [][:],
    new_href="#/new",
    today_href="#/today",
    resume_href="#/resume",
  )
}

///|
/// The Recent documents entries, with documents being deleted kept in place.
fn listed_documents(
  model : Model,
  editing : EditingDocument,
) -> Array[
  (@source_repository.IndexKey, @recent_documents.Seed[@documents.Key]),
] {
  let remote = remote_document_seeds(
    remote_documents(model.sync()),
    document_membership(model.page),
  )
  listed_rows(editing, remote)
}

///|
/// Every document as the Document index lists it, most recently changed
/// first.
fn index_seeds(
  model : Model,
  editing : EditingDocument,
  opening : Opening?,
) -> Array[@document_index.Seed[@documents.Key]] {
  listed_documents(model, editing).map(row => {
    let (@source_repository.IndexKey(changed_at, _), seed) = row
    let key = seed.docid()
    @document_index.Seed::{
      key,
      href: document_href(key),
      text: seed.source(),
      changed_at: changed_at.value(),
      status: seed.status(),
      deletion: seed.deletion(),
      loading: opening is Some({ card: Some(card), .. }) && card == key,
    }
  })
}

///|
/// Whether the Document index lists the document of `key`, as one a URL names
/// may have been deleted since.
fn is_listed(
  model : Model,
  editing : EditingDocument,
  key : @documents.Key,
) -> Bool {
  listed_documents(model, editing).iter().any(row => row.1.docid() == key)
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
  choice : @resume_view.Choice[@documents.Key]?,
) -> (Model, @rabbita.Cmd) {
  let named = editing.activation.key
  let href = document_href(named)
  let (notes, history) = match entry {
    Pushed => (HistoryBack, @nav.replace_url(href))
    ToPush => (HistoryBack, @nav.push_url(href))
    Startup => (IndexEntry, @cmd.none)
  }
  // A range is selected only in the exact text it was taken from.
  let reveal = match choice {
    Some(choice) if choice.key == named &&
      editing.documents.text(named) == Some(choice.source) =>
      select_after_render(choice.start, choice.end)
    _ => @cmd.none
  }
  (
    {
      ..model,
      index: model.index.covered(),
      screen: Writing({ notes, named, chosen: choice.map(choice => choice.id), }),
    },
    @cmd.batch([history, focus_editor_after_render(editing.mode), reveal]),
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
  choice : @resume_view.Choice[@documents.Key]?,
) -> Browse {
  let opening = {
    generation: editing.activation.generation,
    card,
    entry,
    choice,
  }
  Forward(with_browsing(model, { ..browsing, opening: Some(opening), }), msg)
}

///|
/// The index in front again after the Editor held `editing`'s document;
/// with `resuming`, Resume in front of it, focusing the `chosen` entry.
fn return_to_index(
  model : Model,
  editing : EditingDocument,
  resuming : Bool,
  chosen : String?,
) -> (Model, @rabbita.Cmd) {
  let model = with_browsing(model, {
    opening: None,
    card_deletion: None,
    resuming,
  })
  let seeds = index_seeds(model, editing, None)
  if resuming {
    let focus = match chosen {
      Some(id) => @browser.focus_after_render(id)
      None => @cmd.none
    }
    ({ ..model, index: model.index.listing(seeds[:]), }, focus)
  } else {
    (
      {
        ..model,
        index: model.index.returned_from(seeds[:], key=editing.activation.key),
      },
      @cmd.none,
    )
  }
}

///|
fn browse(model : Model, msg : Msg, emit : @rabbita.Emit[Msg]) -> Browse {
  if msg is IndexMsg(event) {
    let (index, command) = model.index.update(event)
    return Handled({ ..model, index, }, command)
  }
  guard model.page is Editing(editing) else { return Forward(model, msg) }
  match (model.screen, msg) {
    (Browsing(browsing), msg) =>
      browse_index(model, browsing, editing, msg, emit)
    (Writing(writing), UrlChanged(url)) =>
      match index_route(url) {
        Some(IndexPage | ResumePage as route) => {
          let resuming = route is ResumePage
          if editing.documents.is_composing(editing.activation.key) {
            Handled({ ..model, screen: Leaving(resuming~), }, @cmd.none)
          } else {
            let (model, command) = return_to_index(
              model,
              editing,
              resuming,
              writing.chosen,
            )
            Handled(model, command)
          }
        }
        Some(CardFromIndex(key)) if key != editing.activation.key &&
          is_listed(model, editing, key) =>
          Forward(model, DocumentSelected(key))
        Some(CardFromIndex(_) | NewFromIndex | TodayFromIndex) | None =>
          Handled(model, @cmd.none)
      }
    (Writing({ notes: HistoryBack, .. }), NotesRequested) =>
      Handled(model, @nav.back())
    (Writing({ notes: IndexEntry, .. }), NotesRequested) =>
      Handled(model, @nav.push_url("#/"))
    // Forward again before composition ended keeps the Editor in front.
    (Leaving(_), UrlChanged(url)) if index_route(url)
      is Some(CardFromIndex(key)) &&
      key == editing.activation.key =>
      Handled(
        {
          ..model,
          screen: Writing({
            notes: HistoryBack,
            named: editing.activation.key,
            chosen: None,
          }),
        },
        @cmd.none,
      )
    (
      _,
      UrlRequested(_)
      | UrlChanged(_)
      | IndexDeleteRequested(_)
      | NotesRequested
      | TodayDated(_)
      | EntryChosen(_),
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
  emit : @rabbita.Emit[Msg],
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
            None,
          )
        Some(CardFromIndex(key)) if is_listed(model, editing, key) =>
          select_while_browsing(model, browsing, editing, key, Pushed, None)
        // The date is read when Today is followed, on the device clock.
        Some(TodayFromIndex) =>
          Handled(
            model,
            @cmd.custom_cmd(scheduler => {
              scheduler.add(emit(TodayDated(@browser.local_date())))
            }),
          )
        Some(ResumePage) =>
          Handled(
            with_browsing(model, { ..browsing, resuming: true, }),
            @cmd.none,
          )
        Some(IndexPage) =>
          Handled(
            with_browsing(model, { ..browsing, resuming: false, }),
            @cmd.none,
          )
        Some(CardFromIndex(_)) | None => Handled(model, @cmd.none)
      }
    TodayDated(date) =>
      match @daily_note.today(local_documents(model, editing)[:], date) {
        Existing(key) =>
          select_while_browsing(model, browsing, editing, key, Pushed, None)
        New(text) =>
          open_while_browsing(
            model,
            browsing,
            editing,
            ExampleSelected(editing.activation, text),
            None,
            Pushed,
            None,
          )
      }
    EntryChosen(choice) =>
      select_while_browsing(
        model,
        browsing,
        editing,
        choice.key,
        ToPush,
        Some(choice),
      )
    DocumentSelected(key) =>
      select_while_browsing(model, browsing, editing, key, ToPush, None)
    CreateRequested | ExampleSelected(_, _) | ImportFilesSelected(_) =>
      open_while_browsing(model, browsing, editing, msg, None, ToPush, None)
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
  choice : @resume_view.Choice[@documents.Key]?,
) -> Browse {
  if key == editing.activation.key {
    let (model, command) = enter_editor(model, editing, entry, choice)
    Handled(model, command)
  } else {
    open_while_browsing(
      model,
      browsing,
      editing,
      DocumentSelected(key),
      Some(key),
      entry,
      choice,
    )
  }
}

///|
/// Documents whose text is held on this device, most recently changed
/// first, as `(key, text)`.
fn local_documents(
  model : Model,
  editing : EditingDocument,
) -> Array[(@documents.Key, String)] {
  listed_documents(model, editing).filter_map(row => {
    let key = row.1.docid()
    editing.documents.text(key).map(text => (key, text))
  })
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
      let browsing = { opening: None, card_deletion: None, resuming: false, }
      if is_listed(model, editing, key) {
        select_while_browsing(
          with_browsing(model, browsing),
          browsing,
          editing,
          key,
          Startup,
          None,
        )
      } else {
        // A document that no longer exists opens the index, without a notice.
        Handled(with_browsing(model, browsing), @nav.replace_url("#/"))
      }
    }
    (Browsing({ opening: Some(opening), .. }), Editing(editing)) if editing.activation.generation >
      opening.generation => {
      let (model, command) = enter_editor(
        model,
        editing,
        opening.entry,
        opening.choice,
      )
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
    (Leaving(resuming~), Editing(editing)) if !editing.documents.is_composing(
        editing.activation.key,
      ) => {
      let (model, command) = return_to_index(model, editing, resuming, None)
      Handled(model, command)
    }
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
