///|
/// Run after rendering so activation has mounted and initialized its textarea.
/// Preview keeps keyboard users at the selected mode control instead.
extern "js" fn focus_editor() =
  #| () => {
  #|   const root = document.getElementById('loomark-root');
  #|   const editor = root?.querySelector('textarea');
  #|   if (!editor || editor.disabled || editor.closest('[inert]')) return;
  #|   const target = editor.getClientRects().length
  #|     ? editor
  #|     : root.querySelector('[role="tab"][aria-selected="true"]');
  #|   target?.focus({ preventScroll: true });
  #| }

///|
extern "js" fn focus_more_actions() =
  #| () => document.getElementById('loomark-more-actions')?.focus({ preventScroll: true })

///|
extern "js" fn focus_delete_action(lifecycle_key : String) =
  #| key => {
  #|   const target = document.getElementById('loomark-delete-' + key);
  #|   if (target?.getClientRects().length && !target.closest('[inert]')) {
  #|     target.focus({ preventScroll: true });
  #|   }
  #| }
