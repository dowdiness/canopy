///|
fn view(
  model : @rabbita.Val[Model],
  emit : @rabbita.Emit[Msg],
  editor : @editor.MarkdownEditor,
) -> @rabbita.Val[@rabbita.Html] {
  let page = model.map(model => model.page)
  let focus_mode = model.map(model => model.focus_mode)
  // Profiles follow the settled Recent documents source, not each keystroke.
  let profile = model
    .map(model => {
      guard model.page is Editing(editing) else { return None }
      editing.documents
      .recent()
      .iter()
      .find_first(item => item.0 == editing.activation.key)
      .map(item => item.1)
    })
    .map(source => source.map(text_profile))
  let japanese = profile.map(profile => profile is Some({ japanese: true, .. }))
  let editor_input : @rabbita.Val[EditorInput?] = model.map2(japanese, (
    model,
    japanese,
  ) => {
    match model.page {
      Editing(editing) =>
        Some({
          activation: editing.activation,
          show_new_document_hint: local_durability(
            editing,
            editing.activation.key,
          )
          is Some(NotStarted),
          disabled: creation_in_progress(editing.creation) ||
          model.sign_in.blocks_editing(),
          read_only: editing.deletion_blocks_document_changes(),
          mode: editing.mode,
          preview: editing.preview,
          japanese,
        })
      Loading(_) | OpeningNew(_, _) | Recovery(_, _) => None
    }
  })

  let compact = page.map(page => {
    match page {
      Loading(compact) => compact
      OpeningNew(opening, _) => opening.compact
      Editing(editing) => editing.compact
      Recovery(_, compact) => compact
    }
  })
  let on_editor : @rabbita.Emit[EditorUiEvent] = emit.map(event => {
    match event {
      InputChanged(generation, input) => Msg::InputChanged(generation, input)
      CompositionStarted(generation) => Msg::CompositionStarted(generation)
      CompositionEnded(generation) => Msg::CompositionEnded(generation)
      ScrollClaimed(pane) => Msg::ScrollClaimed(pane)
    }
  })
  let editor_panes = build_editor_view(editor_input, compact, editor, on_editor)
  let on_sync : @rabbita.Emit[SyncIntent] = emit.map(intent => {
    match intent {
      RetryAccount => Msg::RetryAccount
      StartSync(action) => Msg::StartSync(action)
      AcceptRemote(action) => Msg::AcceptRemote(action)
      RetrySync(action) => Msg::RetrySync(action)
      RetrySelection(action) => Msg::RetrySelection(action)
    }
  })
  let on_account : @rabbita.Emit[AccountIntent] = emit.map(intent => {
    match intent {
      RetryAccount => Msg::RetryAccount
      SignIn(action) => Msg::SignIn(@sign_in.Invoke(action))
      LogoutRequested => Msg::LogoutRequested
    }
  })
  let on_document : @rabbita.Emit[DocumentIntent] = emit.map(intent => {
    match intent {
      CreateRequested => Msg::CreateRequested
      MenuToggled => Msg::MenuToggled
      ImportFilesSelected(files) => Msg::ImportFilesSelected(files)
      ExportRequested => Msg::ExportRequested
      ExampleSelected(activation, text) =>
        Msg::ExampleSelected(activation, text)
    }
  })
  let on_mode = emit.map(mode => ModeSelected(mode))
  let remote_documents = model.map(model => remote_documents(model.sync()))
  let account = model.map(model => account_status(model.sync()))
  let durability = model.map(document_durability)
  let replica_persistence = model.map(document_replica_persistence)
  let document_sync = model.map(document_sync)
  let document_remote = model.map(document_remote_state)
  let document_activity = model.map(document_sync_activity)
  let selection = model.map(selection_activity)
  let account_view = account.view(account => {
    account_status_view(account, on_sync)
  })
  let durability_view = durability.view(durability => {
    local_durability_option_view(durability)
  })
  let replica_persistence_view = replica_persistence.view(persistence => {
    replica_persistence_option_view(persistence)
  })
  let document_sync_view = document_sync.view(sync => {
    document_sync_option_view(sync, on_sync)
  })
  let document_remote_view = document_remote.view(remote => {
    remote_state_option_view(remote, on_sync)
  })
  let document_activity_view = document_activity.view2(durability, (
    activity,
    durability,
  ) => activity_option_view(activity, durability, on_sync))
  let selection_view = selection.view(activity => {
    selection_activity_view(activity, on_sync)
  })
  let sync_status = account_view.view7(
    durability_view, replica_persistence_view, document_sync_view, document_remote_view,
    document_activity_view, selection_view, sync_status_view,
  )
  let sync_attention = document_remote.map3(
    replica_persistence,
    document_activity,
    (remote, persistence, activity) => {
      let attention = sync_attention_view(
        remote, persistence, activity, on_sync,
      )
      (attention, persistence)
    },
  )
  let membership = page.map(document_membership)
  let remote_seeds = remote_documents.map2(membership, remote_document_seeds)
  let recent_seeds = page.map2(remote_seeds, (page, remote) => {
    match page {
      Editing(editing) => recent_document_seeds(editing, remote)
      Loading(_) | OpeningNew(_, _) | Recovery(_, _) => @vector.Vector([])
    }
  })
  let delete_confirmation = page.map(page => {
    match page {
      Editing(editing) =>
        match editing.deletion {
          DeleteConfirmation(id) => Some(id)
          NoDeletion => None
        }
      Loading(_) | OpeningNew(_, _) | Recovery(_, _) => None
    }
  })
  // Resizing must preserve the sidebar state, so it outlives responsive editor branches.
  let sidebar_state = @sidebar.SidebarProviderState::SidebarProviderState(true)
  let recent_documents_view = @recent_documents.build(
    input=recent_seeds,
    lifecycle_key=key => key.lifecycle_key(),
    visible=sidebar_state.visible(),
    can_create=model.map(model => {
      match model.page {
        Editing(editing) =>
          editing.can_activate() && !model.sign_in.blocks_editing()
        _ => false
      }
    }),
    compact~,
    delete_target=delete_confirmation,
    on_intent=@cmd.Emit(intent => {
      match intent {
        Create => emit(CreateRequested)
        Select(id) => emit(DocumentSelected(id))
        RequestDelete(id) => emit(DeleteRequested(id))
        CancelDelete => emit(DeleteCancelled)
        ConfirmDelete(id) => emit(DeleteConfirmed(id))
      }
    }),
    close_after_action=sidebar_state.collapse(),
  )
  let account_input = model.map(account_controls_input)
  let account_controls = account_input.view(input => {
    account_controls(input, on_account)
  })
  let tools_input = model.map(document_tools_input)
  let tools = tools_input.view(input => {
    match input {
      None => @html.nothing
      Some(input) => sidebar_tools(input, sidebar_state.collapse(), on_document)
    }
  })
  let toolbar_input = model.map(toolbar_input)
  let toolbar = toolbar_input.view4(account_controls, sync_status, focus_mode, (
    input,
    account,
    sync_status,
    focus_mode,
  ) => {
    match input {
      None => @html.nothing
      Some(input) =>
        document_toolbar(input, account, sync_status, focus_mode, on_document)
    }
  })
  let mode = page.map(page => {
    match page {
      Editing(editing) => Some(editing.mode)
      _ => None
    }
  })
  let editor_view = mode.view2(editor_panes, (mode, panels) => {
    match mode {
      Some(mode) => mode_content(mode, panels)
      None => @html.nothing
    }
  })
  let characters = profile.map(profile => {
    profile.map(profile => profile.characters)
  })
  let footer = mode.view5(durability, sync_attention, characters, focus_mode, (
    mode,
    durability,
    attention,
    characters,
    focus_mode,
  ) => {
    let (sync_attention, persistence) = attention
    match mode {
      Some(mode) =>
        document_footer(
          mode, durability, persistence, sync_attention, focus_mode, characters,
          on_mode,
        )
      None => @html.nothing
    }
  })
  let phase = page.map(page => {
    match page {
      Loading(_) => LoadingScreen
      OpeningNew(_, creation) =>
        match creation.status {
          InProgress => LoadingScreen
          Failed(_) | Fault(_) => CreationScreen
        }
      Recovery(failure, _) => RecoveryScreen(failure)
      Editing(_) => EditingScreen
    }
  })
  let focus_disabled = model.map(model => {
    match model.page {
      Editing(editing) =>
        !editing.can_activate() ||
        editing.deletion is DeleteConfirmation(_) ||
        model.sign_in.blocks_editing()
      _ => true
    }
  })
  let focus_controls = focus_mode.map2(focus_disabled, (focused, disabled) => {
    (focused, focus_mode_toggle(focused, disabled, emit(FocusModeToggled)))
  })
  let controls = toolbar.map3(footer, focus_controls, (
    toolbar,
    footer,
    focus_controls,
  ) => (toolbar, footer, focus_controls))
  let layout_input = phase.map7(
    compact,
    recent_documents_view.navigation(),
    tools,
    controls,
    editor_view,
    recent_documents_view.dialog(),
    (phase, compact, navigation, tools, controls, editor, dialog) => {
      let (toolbar, footer, focus_controls) = controls
      let (focus_mode, focus_toggle) = focus_controls
      LayoutInput::{
        phase,
        focus_mode,
        focus_toggle,
        compact,
        navigation,
        tools,
        toolbar,
        editor,
        footer,
        dialog,
        creation_action: @rui.button(
          on_click=emit(RetryOpeningNewCreation),
          "Retry creating",
        ),
      }
    },
  )
  @sidebar.sidebar_provider_with_state(
    state=sidebar_state,
    input=layout_input,
    class="loomark-viewport [--rui-sidebar-width:clamp(11rem,24vw,17rem)] [--rui-sidebar-width-icon:2.75rem] max-[720px]:[--rui-sidebar-width:100vw]",
    screen_layout,
  )
}

///|
fn document_tools_input(model : Model) -> DocumentToolsInput? {
  guard model.page is Editing(editing) else { return None }
  Some({
    activation: editing.activation,
    examples_disabled: creation_in_progress(editing.creation) ||
    model.sign_in.blocks_editing(),
    import_disabled: model.sign_in.blocks_editing(),
  })
}

///|
fn toolbar_input(model : Model) -> ToolbarInput? {
  guard model.page is Editing(editing) else { return None }
  Some({
    can_create: editing.can_activate() && !model.sign_in.blocks_editing(),
    menu_open: editing.menu_open,
    import_disabled: model.sign_in.blocks_editing(),
  })
}

///|
fn notices_input(model : Model) -> NoticesInput {
  let lifecycle_error = match model.page {
    Editing(editing) => editing.lifecycle_error
    OpeningNew(opening, _) => opening.lifecycle_error
    _ => None
  }
  guard model.page is Editing(editing) else {
    match model.page {
      OpeningNew(_, creation) =>
        match creation.status {
          Failed(_) =>
            return {
              failure: Some(Create),
              import_failed: false,
              lifecycle_error,
            }
          Fault(message) =>
            return {
              failure: Some(OpeningFault(message)),
              import_failed: false,
              lifecycle_error,
            }
          InProgress =>
            return { failure: None, import_failed: false, lifecycle_error, }
        }
      _ => return { failure: None, import_failed: false, lifecycle_error, }
    }
  }
  let failure : DocumentFailure? = match editing.creation {
    Some(creation) =>
      match creation.status {
        Failed(_) =>
          match creation.intent {
            NewDocument => Some(Create)
            Example(_) => Some(Example)
          }
        InProgress | Fault(_) => None
      }
    None =>
      match editing.documents.delete_status(editing.activation.key) {
        Some(@documents.DeleteStatus::DeleteFailed(failure)) =>
          Some(Delete(failure))
        Some(@documents.DeleteStatus::DeletePersistenceFailed(failure)) =>
          Some(DeletePersistence(failure))
        _ => None
      }
  }
  { failure, import_failed: editing.import_failed, lifecycle_error, }
}
