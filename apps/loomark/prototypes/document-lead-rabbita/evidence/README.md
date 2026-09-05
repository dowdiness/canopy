# Browser checkpoint — not execution acceptance

This prototype consumes the PR's actual `document_lead.extract` inside the outer
Rabbita keyed projection, not inside a reducer or timer. The prototype branch
merged the design branch to reuse its implementation; it must never be merged
back into production. Quiet is a revision-guarded 250 ms simulation, not the
production Documents quiet lifecycle. Preview is absent, so Preview/TextArea
ordering in the production editor is not proved.

## Observations

Chrome, JS release, no explicit CPU/network throttling. Inputs were synthetic
bubbling `input` events on a native textarea after assigning its value. They are
not trusted keyboard events or a browser latency distribution. The source recipe
was `# New\n\n` followed by 1,400 copies of
`- [ ] task\n\n> quote\n\n```\ncode\n```\n\n` (49,007 ASCII bytes).

- `lead-new-corrected.json`: immediate mode created only New. Dispatch took
  9.2 ms; actual extraction started after the callback returned (`inDispatch`
  false). With Chrome tracing enabled extraction took about 2,931 ms; its
  enclosing observed long task was 4,001 ms. Prototype rendering and tracing
  overhead are included in the enclosing task, not attributed to the parser.
- `lead-quiet-ready.json`: separate untraced run waited for actual extraction
  completion. Dispatch took 3.2 ms. Extraction started about 261 ms after input
  and took about 609 ms; an enclosing long task was 643 ms. Another 206 ms task
  occurred before acceptance. Moving execution later did not remove blocking.
- `lead-reopen-corrected.json`: unchanged reopen performed no extraction; hidden
  quiet input performed no extraction; reopen after changing New extracted one
  key. These are count observations, not a product performance improvement.

`inDispatch=false` proves only that the handler has returned. It does not by
itself prove a different browser task, nor the complete 10 ms input contract.
The timer sentinel's order is not proof of task identity. A trusted-input trace
with explicit task nesting remains required before execution acceptance.

The trace `lead-corrected-trace.json.gz` contains the traced immediate/quiet/reopen
walkthrough (the untraced ready run is separate). `gc-summary.json` counts complete
GC events: 58 MinorGC and 6 MajorGC, maxima about 39 ms and 273 ms. These events
include nested/background activity; do not sum them or assign their entire time
to a single extraction. Trace overhead and prototype DOM rendering make these
exploratory evidence, not an SLA or a causal allocation profile.

## Omission comparison

Open `../omission.html`. Both explicit “Excerpt shortened” and an ellipsis with
an equivalent accessible description were inspected in Chrome's accessibility
tree. The bounded sample content is the only content available to either label;
Empty retains an accessible identity. At 390 px the page had no horizontal
overflow. The sample with 80 retained ASCII characters clipped visually even
though semantic truncation was false: CSS clipping and semantic omission must
remain separate concepts.

This comparison uses static presentation samples, not the MoonBit extractor.
It does not prove grapheme-safe extraction or screen-reader usability. Numeric
budgets, wording, and human preference remain open; neither variant is accepted
as the production default.

## Gate

Semantic acceptance remains pending browser product decisions. Execution
acceptance is withheld: actual large-input main-thread blocking is observable,
while trusted-input task boundaries and representative browser distributions
remain unverified. No Worker, new production timer, Preview reuse, manual cache,
or completion protocol was added.
