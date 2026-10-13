///|
extern "js" fn consume_authentication_error() -> Bool =
  #| () => {
  #|   const url = new URL(window.location.href);
  #|   if (!url.searchParams.has("error")) return false;
  #|   url.searchParams.delete("error");
  #|   url.searchParams.delete("error_description");
  #|   window.history.replaceState(window.history.state, "", url.href);
  #|   return true;
  #| }

///|
extern "js" fn load_url(url : String) =
  #| url => window.location.assign(url)

///|
extern "js" fn listen_for_page_restore(callback : () -> Unit) -> () -> Unit =
  #| callback => {
  #|   const listener = event => { if (event.persisted) callback(); };
  #|   window.addEventListener("pageshow", listener);
  #|   return () => window.removeEventListener("pageshow", listener);
  #| }

///|
priv suberror PageRestoreSubscription {
  OnRestore(@cmd.Cmd)
}

///|
fn page_restore_subscription(command : @cmd.Cmd) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.page-restored",
    @sub.Scope::Local,
    PageRestoreSubscription::OnRestore(command),
    (payload, scheduler) => {
      guard payload is PageRestoreSubscription::OnRestore(command) else {
        return None
      }
      let mut command = command
      let stop = listen_for_page_restore(() => scheduler.queue_command(command))
      Some({
        unload: _ => stop(),
        update_tagger: next => {
          guard next is PageRestoreSubscription::OnRestore(next) else { return }
          command = next
        },
      })
    },
  )
}

///|
fn account_controls_input(model : Model) -> AccountControlsInput {
  {
    session: model.sync().session(),
    sign_in: model.sign_in.view(sign_in_readiness(model)),
  }
}
