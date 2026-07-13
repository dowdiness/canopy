# Generative UI Browser Failure and Recovery Design

## Goal

Close the browser-level evidence gap around the existing Generative UI candidate/session commit boundary without adding a live provider, a second lifecycle controller, or test-only FFI lifecycle semantics.

## Scope

This slice covers browser-observable behavior through the existing exported JSX session APIs:

- invalid candidate rejection before candidate rendering;
- stale base-revision rejection;
- real DOM apply failure through a controlled page-DOM fault;
- dirty-session recovery through the next successful candidate render;
- preservation of committed revision and mounted UI across failed candidates;
- deterministic replay from a fresh session;
- preservation of the existing host-owned filter, selection, detail, and focus state while candidate operations fail and recover.

Cancellation and late candidate chunks remain cognition-only evidence. The existing browser Stop button cancels the separate JSX-prefix demonstration loop, while `jsx_session_replay_candidate_json` performs one synchronous whole replay and cannot interleave cancellation. The browser suite will not count prefix-stream stop behavior as candidate lifecycle evidence.

Dry-run failure remains covered by the existing pure/session contract tests. The public browser boundary does not expose internal `DryRunModel` state, and this slice will not add a corruption or forced-dry-run FFI hook.

## Architecture

`examples/web/src/genui.js` remains the host shell. It may expose a thin underscored observability surface for browser tests that only calls existing functions and reports current session state:

- replay a candidate through the existing `jsx_session_replay_candidate_json` export;
- replay at an explicitly supplied base revision for stale-revision tests;
- dispose/reset the existing session through the existing disposal path;
- read the current session revision and handle without owning commit policy.

No lifecycle transitions, validation, revision decisions, recovery logic, or candidate construction policy move into JavaScript. `lib/cognition` and `ffi/jsx` remain authoritative.

DOM apply failure is induced only in Playwright by temporarily replacing the test page root's `appendChild`/`insertBefore` operation with a throwing wrapper. The existing `catch_js` and `DomApplyError` path must observe the failure. The test restores the DOM method before invoking the next real render; no production fault-injection API is added.

## Browser scenarios

1. **Invalid candidate:** establish a committed session, submit a candidate containing a forbidden `raw_html` node, assert `CandidateValidationError`, unchanged revision, unchanged committed preview, and no candidate marker in the preview.
2. **Stale base revision:** establish a committed session, invoke the existing replay export with an older base revision, assert `BaseRevisionMismatch`, unchanged revision, and unchanged preview.
3. **DOM apply failure:** establish a committed candidate session, fault the real preview root's insertion method, submit a valid candidate, assert `DomApplyError`, unchanged revision, and candidate not reported committed.
4. **Recovery:** restore the insertion method, submit the same valid candidate using the current revision, assert success, revision advancement exactly once, and a repaired candidate preview.
5. **Host state preservation:** before failure/recovery, set a filter, select a row, focus the selected row, and assert all host-owned state remains unchanged after both failures and successful candidate recovery.
6. **Deterministic replay:** dispose/reset the session, replay the same valid candidate twice from fresh sessions, and compare success, revision, mounted-node count, and normalized preview markup.

## Safety metrics

The browser suite includes a reproducible measurement test with fixed sample
counts:

- five valid candidate replays from fresh sessions for latency samples;
- three invalid candidates and three stale-base candidates for rejection counts;
- one forced DOM apply failure followed by one successful repair for repair
  count;
- two fresh replays of the same candidate for deterministic comparison.

The test attaches raw JSON containing every `performance.now()` duration,
attempt/result counts, state snapshots, repair count, and
`performance.memory` availability/values when Chromium exposes that API. The
denominators are explicit in the JSON rather than inferred from aggregate
test timing.

The browser run records zero counts for:

- stale candidate commits;
- host state-loss events;
- falsely committed failed DOM applies;
- deterministic replay mismatches.

The cognition test suite separately records cancelled-generation commits and
late-generation acceptance as zero. Those values are not presented as browser
measurements because the browser candidate API is synchronous whole-replay.

Latency, rejection rate, repair count, and browser heap usage are reported from
the attached measurement JSON. Unsupported heap measurements are recorded as
unavailable rather than inferred.

## Non-goals

- no Gemini or other live provider;
- no new lifecycle implementation in JavaScript;
- no browser cancellation controller for the synchronous whole-replay API;
- no dry-run corruption hook;
- no visible demo failure controls;
- no renderer-neutral API;
- no changes to committed UI or revision policy.
