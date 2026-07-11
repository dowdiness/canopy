#!/bin/bash

# Stop hook: catches ownership-dodging, premature stopping, and
# permission-seeking behavior. When triggered, blocks the assistant
# from stopping and forces continuation.
#
# Adapted from Ben Vanik's stop-phrase-guard.sh:
# https://gist.github.com/benvanik/ee00bd1b6c9154d6545c63e06a317080
#
# Context: anthropics/claude-code#42796

set -euo pipefail

INPUT=$(cat)

# Prevent infinite loops: if the hook already fired once this turn,
# let the assistant stop.
HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
if [[ "$HOOK_ACTIVE" == "true" ]]; then
  exit 0
fi

MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')
if [[ -z "$MESSAGE" ]]; then
  exit 0
fi

# Strip markdown code blocks and inline code to avoid false positives
# when the assistant is describing/quoting patterns rather than using them.
MESSAGE=$(echo "$MESSAGE" | sed '/^```/,/^```/d' | sed 's/`[^`]*`//g' | sed 's/"[^"]*"//g')

# Each violation: "grep_pattern|correction_rule"
# Patterns are checked case-insensitively. First match wins.

VIOLATIONS=(
  # Ownership dodging — all builds/tests are green upstream
  # Require failure-context words (issue/bug/error/problem/failure) alongside "pre-existing"
  # to avoid false positives on factual descriptions like "pre-existing file"
  "pre-existing issue|NOTHING IS PRE-EXISTING. If something fails, YOUR work caused it. Investigate and fix."
  "pre-existing bug|NOTHING IS PRE-EXISTING. If something fails, YOUR work caused it. Investigate and fix."
  "pre-existing error|NOTHING IS PRE-EXISTING. If something fails, YOUR work caused it. Investigate and fix."
  "pre-existing problem|NOTHING IS PRE-EXISTING. If something fails, YOUR work caused it. Investigate and fix."
  "pre-existing failure|NOTHING IS PRE-EXISTING. If something fails, YOUR work caused it. Investigate and fix."
  "not from my changes|NOTHING IS PRE-EXISTING. You own every change. Investigate the failure."
  "not my change|NOTHING IS PRE-EXISTING. You own every change. Investigate the failure."
  "not caused by my|NOTHING IS PRE-EXISTING. You own every change. Investigate the failure."
  "not introduced by my|NOTHING IS PRE-EXISTING. You own every change. Investigate the failure."
  "already existed before|NOTHING IS PRE-EXISTING. If you found it broken, fix it or explain exactly what is wrong."
  "before my changes|NOTHING IS PRE-EXISTING. There is no 'before your changes.'"
  "unrelated to my changes|NOTHING IS PRE-EXISTING. If it is broken, fix it."
  "an existing issue|NOTHING IS PRE-EXISTING. Investigate and fix."
  "existing bug|NOTHING IS PRE-EXISTING. Investigate and fix."

  # Known limitation dodging
  "known limitation|Investigate whether it is fixable. Fix it or explain the specific technical reason it cannot be fixed."
  "future work|Fix it now or describe exactly what the fix requires — not as a TODO."
  "left as an exercise|Do the work."

  # Session-length quitting
  "good place to stop|Is the task done? If not, continue working."
  "good stopping point|Is the task done? If not, continue working."
  "natural stopping|Is the task done? If not, continue working."
  "logical stopping|Is the task done? If not, continue working."
  "continue in a new session|Sessions are unlimited. Continue working."
  "getting long|Sessions are unlimited. Continue working."

  # Permission-seeking mid-task
  "should I continue|Do not ask. If the task is not done, continue. The user will interrupt if needed."
  "shall I continue|Do not ask. Continue working until the task is complete."
  "shall I proceed|Do not ask. Proceed."
  "would you like me to continue|Do not ask. Continue."
  "want me to keep going|Do not ask. Keep going."
  "want me to continue|Do not ask. Continue."
  "should I keep going|Do not ask. Keep going."
  "pick this up later|There is no 'later.' Continue working now."
  "come back to this|There is no 'coming back.' Continue working now."
  "pause here|Do not pause. The task is not done. Continue."
  "stop here for now|Do not stop. The task is not done. Continue."
  "wrap up for now|Do not wrap up. The task is not done. Continue."

  # "Simplest fix" mentality — the 642% signal from the issue
  "the simplest approach|Evaluate correctness, not simplicity. Is this the RIGHT fix?"
  "the simplest fix|Evaluate correctness, not simplicity. Is this the RIGHT fix?"
  "simplest solution|Evaluate correctness, not simplicity. Is this the RIGHT fix?"
)

for entry in "${VIOLATIONS[@]}"; do
  pattern="${entry%%|*}"
  correction="${entry#*|}"

  if echo "$MESSAGE" | grep -iq "$pattern"; then
    jq -n --arg reason "STOP HOOK: $correction" '{
      decision: "block",
      reason: $reason
    }'
    exit 0
  fi
done

exit 0
