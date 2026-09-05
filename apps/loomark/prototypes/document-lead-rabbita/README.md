# PROTOTYPE: Rabbita document-lead measurement probe

This throwaway browser probe measures the actual Rabbita demand path for the
existing `@document_lead.extract` implementation. The extractor is called only
by the pure `content.map` node in `lead_component`; the existing visibility
switch is its consumer. This is not production UI or a production debounce
protocol.

Run from the repository root:

```sh
just prototype-loomark-document-lead-rabbita
```

## Scenarios

- **Immediate acceptance**: native textarea input updates or creates only the
  keyed `New` source immediately; source A is untouched.
- **Quiet 250ms simulation**: textarea state updates immediately; `New` is
  created or updated only after 250 ms, with no placeholder extraction.
  Delayed events carry the input sequence, so stale events are ignored. This is
  latest-single-input instrumentation, not production cancellation.
- Use the existing **Show/Hide**, **Change A**, status, B, restore, and refresh
  controls to observe the graph independently.

The corpus buttons remain deterministic: `"# ordinary 10KB\n\n" + "ordinary ".repeat(1100)` (about 10KB) and `"# heavy generated ~66KB\n\n" + "heavy ".repeat(11000)` (about 66KB actual bytes). Click a corpus button to
replace textarea text; native input is required to accept it into `New`.

## Browser evidence API

After load, inspect `window.__documentLeadProbe`:

- `inputEvents`, `immediateAccepted`, `quietAccepted`, `extractions`, and
  `pureExtractions`
- `trace`: event/root-update boundaries, extraction timestamps with
  `inDispatch`, row-render records, separate microtask/later-task markers, and
  longtask records
- `longtasks`: `PerformanceObserver` records when supported

Performance marks are `textarea-input-start/end`,
`rabbita-root-update-start/end`, and `document-lead-extract-start/end`.
Extraction counts and `pure extraction runs` distinguish the instrumented pure
extraction path. `inDispatch` is true only during the native handler; task
classification should use the microtask and longtask evidence rather than an
asserted task label. No full input source is written to the lifecycle log.
