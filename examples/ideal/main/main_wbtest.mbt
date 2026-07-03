// Whitebox tests for update helpers.

///|
fn test_actions() -> Array[@lambda_edits.Action] {
  @lambda_edits.get_actions_for_node(
    @ast.Term::Unit,
    @lambda_edits.NodeContext::new(),
  )
}

///|
fn test_action_by_id(id : String) -> @lambda_edits.Action {
  test_actions().iter().find_first(fn(action) { action.id == id }).unwrap()
}

///|
fn test_overlay_context() -> @lambda_edits.ActionContext {
  {
    node_id: @canopy_core.NodeId::from_int(1),
    kind: @ast.Term::Unit,
    is_let_binding: false,
    binding_node_id: None,
    binding_def_index: None,
    module_node_id: None,
  }
}

///|
fn test_overlay_state(mode : OverlayMode) -> OverlayState {
  let actions = test_actions()
  {
    mode,
    actions,
    kind: @ast.Term::Unit,
    error: None,
    anchor_top: 0,
    anchor_left: 0,
    menu: @menu.Model::new(
      id="ideal-action-overlay-menu-test",
      item_count=actions.length(),
    ),
  }
}

///|
fn test_parent_emit() -> @rabbita.Emit[Msg] {
  let (emit, _) : (@rabbita.Emit[Msg], @rabbita.Cell) = @rabbita.simple_cell_with_emit(
    model=0,
    update=fn(_ : Msg, count) { count },
    view=fn(_, _) { @html.nothing },
  )
  emit
}

///|
fn test_overlay_runtime(token : Int) -> ActionOverlayRuntime {
  let state = test_overlay_state(MainMenu)
  let (emit, cell) = create_overlay_cell(test_parent_emit(), token, state)
  { cell, emit, token }
}

///|
test "overlay update dispatches main menu mnemonic action" {
  let delete_action = test_action_by_id("delete")
  let result = test_overlay_state(MainMenu).update(KeyPressed("d"))
  match result.effect {
    ExecuteAction(action, choice~, name~) => {
      inspect(action.id, content="delete")
      inspect(choice, content="")
      inspect(name, content="")
    }
    _ => inspect("unexpected", content="ExecuteAction")
  }
  match result.state.mode {
    MainMenu => inspect("main", content="main")
    _ => inspect("unexpected", content="MainMenu")
  }
  inspect(delete_action.id, content="delete")
}

///|
test "overlay update dispatches valid submenu numbered choice" {
  let wrap_bop_action = test_action_by_id("wrap_bop")
  let result = test_overlay_state(Submenu(wrap_bop_action)).update(
    Menu(@menu.Activate(0)),
  )
  match result.effect {
    ExecuteAction(action, choice~, name~) => {
      inspect(action.id, content="wrap_bop")
      inspect(choice, content="Plus")
      inspect(name, content="")
    }
    _ => inspect("unexpected", content="ExecuteAction")
  }
}

///|
test "overlay update recovers invalid submenu key to focused main menu" {
  let wrap_bop_action = test_action_by_id("wrap_bop")
  let result = test_overlay_state(Submenu(wrap_bop_action)).update(
    KeyPressed("z"),
  )
  match result.state.mode {
    MainMenu => inspect("main", content="main")
    _ => inspect("unexpected", content="MainMenu")
  }
  match result.effect {
    FocusMenu => inspect("focus", content="focus")
    _ => inspect("unexpected", content="FocusMenu")
  }
  inspect(result.state.error is None, content="true")
}

///|
test "overlay public key event preserves submenu invalid-key recovery" {
  let wrap_bop_action = test_action_by_id("wrap_bop")
  let result = test_overlay_state(Submenu(wrap_bop_action)).update(
    OverlayKeyPressed("z").to_overlay_msg(),
  )
  match result.state.mode {
    MainMenu => inspect("main", content="main")
    _ => inspect("unexpected", content="MainMenu")
  }
  match result.effect {
    FocusMenu => inspect("focus", content="focus")
    _ => inspect("unexpected", content="FocusMenu")
  }
}

///|
test "overlay update keeps empty name submit in prompt with error" {
  let wrap_lambda_action = test_action_by_id("wrap_lambda")
  let state = test_overlay_state(NamePrompt(wrap_lambda_action, value="stale"))
  let input_result = state.update(NameInput(""))
  let result = input_result.state.update(NameSubmit)
  match result.effect {
    NoOverlayEffect => inspect("none", content="none")
    _ => inspect("unexpected", content="NoOverlayEffect")
  }
  match result.state.mode {
    NamePrompt(action, value~) => {
      inspect(action.id, content="wrap_lambda")
      inspect(value, content="")
    }
    _ => inspect("unexpected", content="NamePrompt")
  }
  inspect(result.state.error is Some(EmptyName), content="true")
}

///|
test "overlay update whitespace input does not clear error" {
  let wrap_lambda_action = test_action_by_id("wrap_lambda")
  let state_with_error = test_overlay_state(
      NamePrompt(wrap_lambda_action, value=""),
    ).update(NameSubmit).state
  inspect(state_with_error.error is Some(EmptyName), content="true")
  let result = state_with_error.update(NameInput(" "))
  inspect(result.state.error is Some(EmptyName), content="true")
}

///|
test "overlay update non-empty input clears error" {
  let wrap_lambda_action = test_action_by_id("wrap_lambda")
  let state_with_error = test_overlay_state(
      NamePrompt(wrap_lambda_action, value=""),
    ).update(NameSubmit).state
  let result = state_with_error.update(NameInput("x"))
  inspect(result.state.error is None, content="true")
}

///|
test "overlay update name cancel closes overlay" {
  let wrap_lambda_action = test_action_by_id("wrap_lambda")
  let result = test_overlay_state(NamePrompt(wrap_lambda_action, value="x")).update(
    NameCancel,
  )
  match result.effect {
    CloseOverlay => inspect("close", content="close")
    _ => inspect("unexpected", content="CloseOverlay")
  }
}

///|
test "overlay outputs only match their originating runtime token" {
  let runtime = test_overlay_runtime(7)
  let host = ActionOverlayHost::empty().mount(test_overlay_context(), runtime)
  let action = test_action_by_id("delete")
  let matching = OverlayOutput::ExecuteAction(
    token=7,
    action,
    choice="",
    name="",
  )
  let stale = OverlayOutput::ExecuteAction(token=8, action, choice="", name="")
  inspect(host.active_for_output(matching) is Some(_), content="true")
  inspect(host.active_for_output(stale) is None, content="true")
}

///|
test "overlay close outputs only match their originating runtime token" {
  let host = ActionOverlayHost::empty().mount(
    test_overlay_context(),
    test_overlay_runtime(7),
  )
  inspect(
    host.active_for_output(OverlayOutput::CloseOverlay(token=7)) is Some(_),
    content="true",
  )
  inspect(
    host.active_for_output(OverlayOutput::CloseOverlay(token=8)) is None,
    content="true",
  )
}

///|
test "mount sets context on host" {
  let ctx = test_overlay_context()
  let host = ActionOverlayHost::empty().mount(ctx, test_overlay_runtime(7))
  inspect(host.active is Some(_), content="true")
}

///|
test "parse_node_id valid" {
  inspect(parse_node_id("42") is Some(_), content="true")
}

///|
test "parse_node_id invalid returns None" {
  inspect(parse_node_id("abc") is None, content="true")
  inspect(parse_node_id("") is None, content="true")
}

///|
test "event_detail_node_id extracts nodeId from object detail" {
  inspect(event_detail_node_id("{\"nodeId\":\"42\"}"), content="42")
}

///|
test "event_detail_node_id accepts string detail fallback" {
  inspect(event_detail_node_id("42"), content="42")
}

///|
test "event_detail_node_id rejects unrelated detail" {
  inspect(event_detail_node_id("{\"other\":\"42\"}"), content="")
}

///|
test "event_detail_status extracts status from object detail" {
  inspect(
    event_detail_status("{\"status\":\"connected\"}"),
    content="connected",
  )
}

///|
test "event_detail_status accepts string detail fallback" {
  inspect(event_detail_status("error"), content="error")
}

///|
test "event_detail_status rejects unrelated detail" {
  inspect(event_detail_status("{\"other\":\"connected\"}"), content="")
}

///|
test "event_detail_structural_edit extracts op and nodeId" {
  let (op, node_id) = event_detail_structural_edit(
    "{\"op\":\"Drop\",\"nodeId\":\"7\"}",
  )
  inspect(op, content="Drop")
  inspect(node_id, content="7")
}

///|
test "event_detail_structural_edit rejects incomplete detail" {
  let (op, node_id) = event_detail_structural_edit("{\"op\":\"Drop\"}")
  inspect(op, content="Drop")
  inspect(node_id, content="")
}

///|
test "event_detail_structural_edit rejects non-object detail" {
  let (op, node_id) = event_detail_structural_edit("Drop")
  inspect(op, content="")
  inspect(node_id, content="")
}

///|
test "event target selector is centralized" {
  inspect(EditorHost.selector(), content="#canopy-editor")
  inspect(TextEditor.selector(), content="#canopy-text-editor")
}

///|
test "event names are centralized" {
  inspect(ActionOverlayOpen.event_type(), content="action-overlay-open")
  inspect(ActionKey.event_type(), content="action-key")
  inspect(ExternalCrdtChange.event_type(), content="external-crdt-changed")
  inspect(LongPress.event_type(), content="long-press")
  inspect(NodeSelected.event_type(), content="node-selected")
  inspect(RequestUndo.event_type(), content="request-undo")
  inspect(RequestRedo.event_type(), content="request-redo")
  inspect(StructuralEditApplied.event_type(), content="structural-edit-applied")
  inspect(SyncStatus.event_type(), content="sync-status")
}

///|
test "dom event subscription error message includes context" {
  inspect(
    dom_event_subscription_error_message(
      EditorHost,
      ActionKey,
      "document is unavailable",
    ),
    content="[canopy] failed to install DOM event subscription target=editor-host event=action-key: document is unavailable",
  )
}

// ── OverlayError typed-error tests ───────────────────────────────────────────

///|
test "overlay error: SetError(BuildActionFailed) stores typed variant" {
  let result = test_overlay_state(MainMenu).update(
    SetError(BuildActionFailed("bad op")),
  )
  inspect(
    result.state.error is Some(BuildActionFailed("bad op")),
    content="true",
  )
  match result.effect {
    NoOverlayEffect => ()
    _ => inspect("unexpected", content="NoOverlayEffect")
  }
}

///|
test "overlay error: SetError(ApplyActionFailed) stores typed variant" {
  let result = test_overlay_state(MainMenu).update(
    SetError(ApplyActionFailed("apply failed")),
  )
  inspect(
    result.state.error is Some(ApplyActionFailed("apply failed")),
    content="true",
  )
}

///|
test "overlay error: cleared on name prompt open" {
  let wrap_lambda_action = test_action_by_id("wrap_lambda")
  let state_with_error = test_overlay_state(MainMenu).update(
      SetError(EmptyName),
    ).state
  let result = state_with_error.update(ShowNamePrompt(wrap_lambda_action))
  inspect(result.state.error is None, content="true")
  inspect(result.state.mode is NamePrompt(_, ..), content="true")
}

///|
test "overlay error: cleared on submenu open" {
  let wrap_bop_action = test_action_by_id("wrap_bop")
  let state_with_error = test_overlay_state(MainMenu).update(
      SetError(EmptyName),
    ).state
  let choices = state_with_error.submenu_choices(wrap_bop_action)
  let result = state_with_error.open_submenu(wrap_bop_action, choices.length())
  inspect(result.state.error is None, content="true")
  inspect(result.state.mode is Submenu(_), content="true")
}

///|
test "overlay error: cleared on main menu reset (close_submenu)" {
  let wrap_bop_action = test_action_by_id("wrap_bop")
  let state_with_error = test_overlay_state(Submenu(wrap_bop_action)).update(
      SetError(ApplyActionFailed("stale")),
    ).state
  let result = state_with_error.close_submenu()
  inspect(result.state.error is None, content="true")
  inspect(result.state.mode is MainMenu, content="true")
}

///|
test "format_overlay_error: EmptyName" {
  inspect(format_overlay_error(EmptyName), content="Enter a name to continue")
}

///|
test "format_overlay_error: BuildActionFailed carries message" {
  inspect(
    format_overlay_error(BuildActionFailed("bad op")),
    content="Build failed: bad op",
  )
}

///|
test "format_overlay_error: ApplyActionFailed carries message" {
  inspect(
    format_overlay_error(ApplyActionFailed("apply failed")),
    content="Apply failed: apply failed",
  )
}
