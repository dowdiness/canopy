// Shared browser timing hooks used by the Canopy editor's optional
// set_text_and_record phase probe.

///|
extern "js" fn js_perf_detail_enabled() -> Bool =
  #| () => Boolean(globalThis.__canopy_bridge?.perfCurrent?.profileTextEdit)

///|
extern "js" fn js_perf_detail_begin(name : String) -> Unit =
  #| function(name) {
  #|   var perf = globalThis.__canopy_bridge?.perfCurrent;
  #|   if (!perf || !perf.spans || !perf.profileTextEdit) return;
  #|   if (!perf._starts) perf._starts = {};
  #|   perf._starts[name] = performance.now();
  #| }

///|
extern "js" fn js_perf_detail_end(name : String) -> Unit =
  #| function(name) {
  #|   var perf = globalThis.__canopy_bridge?.perfCurrent;
  #|   if (!perf || !perf.spans || !perf.profileTextEdit || !perf._starts) return;
  #|   var start = perf._starts[name];
  #|   if (typeof start !== 'number') return;
  #|   perf.spans[name] = (perf.spans[name] || 0) + performance.now() - start;
  #|   delete perf._starts[name];
  #| }
