// Shared browser timing hooks used by the Ideal editor's existing phase probe.

///|
extern "js" fn js_perf_begin(name : String) -> Unit =
  #| function(name) {
  #|   var perf = globalThis.__canopy_bridge?.perfCurrent;
  #|   if (!perf || !perf.spans) return;
  #|   if (!perf._starts) perf._starts = {};
  #|   perf._starts[name] = performance.now();
  #| }

///|
extern "js" fn js_perf_end(name : String) -> Unit =
  #| function(name) {
  #|   var perf = globalThis.__canopy_bridge?.perfCurrent;
  #|   if (!perf || !perf.spans || !perf._starts) return;
  #|   var start = perf._starts[name];
  #|   if (typeof start !== 'number') return;
  #|   perf.spans[name] = (perf.spans[name] || 0) + performance.now() - start;
  #|   delete perf._starts[name];
  #| }
