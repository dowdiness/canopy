## Summary

<!-- 1-3 bullet points: what changed and why -->

-

## UI and review evidence

<!-- Complete for UI or visual changes; otherwise write N/A. `.impeccable.md` is the canonical design source. -->

- [ ] Visible-label removal preserves accessible names, visible focus, and the keyboard path
- [ ] Interactive bounds, pointer feedback, and viewport reflow were checked in the rendered UI
- [ ] Any claimed Canopy rule cites its repository source; external guidance, recommendations, and preferences are labeled as such

## Reuse check

<!-- Required when adding new functions, methods, helpers, or types. Skip only for pure docs/config changes. -->
<!-- Include project APIs and actual MoonBit core APIs for the data shape involved
     (Map/Set/String/StringView/Bytes/Buffer/Option/Result/cmp/math/Array/Iter, etc.).
     Do not satisfy this by listing only Iter/Array unless the change is purely collection iteration. -->

Existing APIs considered:

| API | Location | Reused? | Reason if not |
|-----|----------|---------|---------------|
| | | | |

New helpers added (if any):

<!-- list any new helper names here and explain why each doesn't duplicate an existing API -->

## Test plan

<!-- Prefer behavior, state, and explicit readiness signals. Avoid fixed waits and brittle pixel assertions unless the exact value is an intended contract. -->

- [ ] `NEW_MOON_MOD=0 moon check` passes
- [ ] `NEW_MOON_MOD=0 moon test` passes
- [ ] `git diff *.mbti` reviewed for unintended API surface changes
- [ ] JS rebuild run if web is affected (`cd examples/web && npm run build`)

## Validation

```bash
NEW_MOON_MOD=0 moon check && NEW_MOON_MOD=0 moon test
```
