# Task 1 Report

## Files changed
- `ffi/jsx/generative_ui_replay_adapter.mbt` - extracted one shared decode/validate boundary and one opaque validated-candidate session transaction while preserving replay behavior.
- `ffi/jsx/session_contract_wbtest.mbt` - added regression coverage for precedence, diagnostics, lifecycle outcomes, invalid replay result fields, and the validated-candidate transaction boundary.

## Reuse check
### Project APIs checked/reused
- Reused `decode_candidate_json` for candidate JSON decoding.
- Reused `decode_capabilities_json` for capability JSON decoding.
- Reused `@cognition.GenerativeUiCandidate::validate` for semantic validation.
- Reused `jsx_session_commit_candidate` as the only session-side candidate commit path.
- Reused lifecycle transitions via `@cognition.GenerativeUiLifecycle::dispatch` and existing event/transition enums.
- Reused existing result rendering through `render_result_json` and existing `SessionResultJson` decoding.
- Async driver intentionally not involved: this refactor starts after replay has already assembled the complete candidate source and only moves decode/validate/session-commit boundaries.

### Core APIs checked/reused/rejected
- Checked/reused `Result` for the private decode/validate boundary return shape.
- Checked/reused `Json` and existing JSON decode flow; rejected any second parser/decoder.
- Checked/reused `Array::map` for diagnostic string rendering.
- Checked/reused `Option` and tuple payloads for existing error/result conventions.
- Rejected introducing a new public type, new decoder, or alternate session transaction abstraction because existing tuple/result conventions already matched the required private boundary.

### New helpers
- `decode_validated_candidate` - private shared replay decode/capability/validation boundary returning either opaque validated candidate or existing error payload pieces.
- `commit_validated_candidate_transaction` - private session transaction consuming only an already validated `GenerativeUiCandidate`.
- `session_test_validating_lifecycle` - white-box fixture that reaches the validating lifecycle phase without decoding JSON.
- `session_test_empty_capabilities_json` - tiny test fixture for empty capabilities JSON.
- `session_test_replay_result` - tiny helper for replay result parsing in tests.

### Remaining imperative code
- Existing lifecycle input replay loop, candidate lowering, capability lowering, and session DOM/dry-run internals remain imperative because this task was a behavior-preserving boundary extraction, not a renderer/lifecycle redesign.

## RED failure evidence
1. Reproduced RED in an isolated detached worktree at parent commit `012d88e2` with the final Task 1 white-box test file and no production implementation changes.
2. Corrected focused failure command:
   - `moon test ffi/jsx/session_contract_wbtest.mbt`
   - Result: exit 1 with `commit_validated_candidate_transaction is unbound` at test lines 1154, 1186, and 1220.
   - This proves the focused file selection compiled all 42 Task 1 contracts and failed specifically because the private boundary was absent.

## Verification commands and results
1. `NEW_MOON_MOD=0 moon check`
   - Before implementation after test edit: failed as expected with missing `commit_validated_candidate_transaction` boundary.
2. `NEW_MOON_MOD=0 moon check`
   - After implementing adapter extraction: passed with only pre-existing repository warnings.
3. `moon test ffi/jsx/session_contract_wbtest.mbt`
   - Passed: `Total tests: 42, passed: 42, failed: 0.`
4. `moon test ffi/jsx`
   - Passed after review fix: `Total tests: 57, passed: 57, failed: 0.`
5. `moon info && moon fmt`
   - Completed successfully during Task 1 implementation.
6. `git diff -- ffi/jsx/pkg.generated.mbti`
   - No diff; public interface unchanged.
7. `NEW_MOON_MOD=0 moon check`
   - Re-run after `moon fmt`: passed with only pre-existing warnings.
8. Review-fix evidence
   - Added mounted-id/revision assertions for invalid capability and semantic replay failures.
   - Added transaction regression proving corrupted `session.dry_run_model` is ignored by validated candidate replay because candidate commits always remount from `DryRunModel::empty`.

## Commit SHA
- Task 1 implementation commit: `213f163867cbe96f506382c45020d0c98d724691`

## Self-review
- Reviewed committed diff via `git show --stat --oneline --format=fuller HEAD` after the Task 1 commit.
- Verified replay still routes through the original decode helpers and `GenerativeUiCandidate::validate` exactly once.
- Verified the new private transaction accepts only a validated candidate and never decodes/revalidates JSON.
- Verified error precedence stayed candidate decode -> capability decode -> semantic validation -> lifecycle/session transaction.
- Verified no public API or `pkg.generated.mbti` change.

## Concerns
- A real `DryRunError` through `commit_validated_candidate_transaction` is structurally unreachable without changing production behavior: `jsx_session_commit_candidate` always plans candidate renders with `must_remount=true`, and `commit_projection` therefore dry-runs candidates from `DryRunModel::empty` rather than `session.dry_run_model`. The added regression now locks that invariant in place instead.