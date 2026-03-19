///|
extern "js" fn js_mount_editor() -> Unit =
  #| function() {
  #|   // The canopy-editor custom element should already be in the DOM
  #|   // Find it and call mount() with the CRDT module
  #|   // This is a placeholder - real implementation needs the CRDT handle
  #|   console.log('mount_editor called');
  #| }

///|
extern "js" fn js_reconcile_editor() -> Unit =
  #| function() {
  #|   var el = document.querySelector('canopy-editor');
  #|   if (el && el.projNode !== undefined) {
  #|     el.projNode = '';
  #|   }
  #| }
