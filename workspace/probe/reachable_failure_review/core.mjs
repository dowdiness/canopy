// PROTOTYPE — pure model of the ReachableFailure agent-review report boundary.

function copyFailure(failure) {
  return {
    name: failure.name,
    location: failure.location === null ? null : { ...failure.location },
    witness: [...failure.witness],
  };
}

function failureKey(failure) {
  if (failure.location === null) return `?:${failure.name}`;
  return `${failure.location.start}:${failure.location.end}:${failure.name}`;
}

function remapPosition(position, edits) {
  let shift = 0;
  for (const edit of edits) {
    if (position < edit.start) break;
    if (position < edit.start + edit.delete_len) return edit.start + shift;
    shift += edit.inserted.length - edit.delete_len;
  }
  return position + shift;
}

function remapFailures(failures, edits) {
  return failures.map((failure) => {
    if (failure.location === null) return copyFailure(failure);
    return {
      name: failure.name,
      location: {
        start: remapPosition(failure.location.start, edits),
        end: remapPosition(failure.location.end, edits),
      },
      witness: [...failure.witness],
    };
  });
}

function diff(before, after) {
  const beforeKeys = new Set(before.map(failureKey));
  const afterKeys = new Set(after.map(failureKey));
  return {
    newly_reachable: after
      .filter((failure) => !beforeKeys.has(failureKey(failure)))
      .map(copyFailure),
    resolved: before
      .filter((failure) => !afterKeys.has(failureKey(failure)))
      .map(copyFailure),
  };
}

export function buildReachableFailureReview({
  attribution,
  applied_edits,
  before,
  after,
}) {
  const detachedEdits = applied_edits.map((edit) => ({ ...edit }));
  return {
    attribution: { ...attribution },
    applied_edits: detachedEdits,
    failure_diff: diff(remapFailures(before, detachedEdits), after),
  };
}

const failure = (name, start, end, witness) => ({
  name,
  location: { start, end },
  witness,
});

export const scenarios = [
  {
    key: "1",
    title: "Rename binder: introduces x",
    before_source: "let x = 1\nx",
    after_source: "let y = 1\nx",
    attribution: {
      producer: "agent:demo",
      edit_id: "rename-binder-1",
      summary: "Rename binder x to y",
    },
    applied_edits: [{ start: 4, delete_len: 1, inserted: "y" }],
    before: [],
    after: [failure("x", 10, 11, ["scope:module-root"])],
  },
  {
    key: "2",
    title: "Rename reference: resolves y",
    before_source: "(x) => y",
    after_source: "(x) => x",
    attribution: {
      producer: "agent:demo",
      edit_id: "rename-reference-1",
      summary: "Rename reference y to x",
    },
    applied_edits: [{ start: 7, delete_len: 1, inserted: "x" }],
    before: [failure("y", 7, 8, ["scope:lambda", "scope:root"])],
    after: [],
  },
  {
    key: "3",
    title: "Position-only shift: stays empty",
    before_source: "(x) => y",
    after_source: "let w = 0\n(x) => y",
    attribution: {
      producer: "agent:demo",
      edit_id: "prefix-only-1",
      summary: "Insert unrelated binding before expression",
    },
    applied_edits: [{ start: 0, delete_len: 0, inserted: "let w = 0\n" }],
    before: [failure("y", 7, 8, ["scope:lambda", "scope:root"])],
    after: [failure("y", 17, 18, ["scope:lambda", "scope:root"])],
  },
  {
    key: "4",
    title: "Identical rebuild: stays empty",
    before_source: "(x) => y",
    after_source: "(x) => y",
    attribution: {
      producer: "agent:demo",
      edit_id: "rebuild-only-1",
      summary: "Rebuild unchanged source",
    },
    applied_edits: [],
    before: [failure("y", 7, 8, ["scope:lambda", "scope:root"])],
    after: [failure("y", 7, 8, ["scope:lambda", "scope:root"])],
  },
];

export function evaluateScenario(scenario) {
  return buildReachableFailureReview({
    attribution: scenario.attribution,
    applied_edits: scenario.applied_edits,
    before: scenario.before,
    after: scenario.after,
  });
}
