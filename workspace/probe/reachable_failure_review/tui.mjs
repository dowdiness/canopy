#!/usr/bin/env node

// PROTOTYPE — thin terminal shell over core.mjs.

import readline from "node:readline";
import { evaluateScenario, scenarios } from "./core.mjs";

const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";
const RESET = "\x1b[0m";

let selected = scenarios[0];

function formatFailure(failure) {
  const location = failure.location
    ? `${failure.location.start}..${failure.location.end}`
    : "unknown";
  return `${failure.name} @ ${location} via [${failure.witness.join(", ")}]`;
}

function formatFailureList(failures) {
  if (failures.length === 0) return `${DIM}(none)${RESET}`;
  return failures.map((failure) => `- ${formatFailure(failure)}`).join("\n");
}

function render() {
  const report = evaluateScenario(selected);
  console.clear();
  console.log(`${BOLD}PROTOTYPE — ReachableFailure review boundary${RESET}`);
  console.log(
    `${DIM}Accepted: opt-in Lambda companion wrapper owns before/apply/after.${RESET}\n`,
  );
  console.log(`${BOLD}Chosen seam${RESET}`);
  console.log("lang/lambda/companion::review_lambda_tree_edit (proposed sibling wrapper)");
  console.log(`${DIM}SyncEditor, protocol/FFI, and examples/ideal remain unchanged.${RESET}\n`);

  console.log(`${BOLD}Scenario${RESET}`);
  console.log(selected.title);
  console.log(`${DIM}before:${RESET} ${JSON.stringify(selected.before_source)}`);
  console.log(`${DIM}after: ${RESET} ${JSON.stringify(selected.after_source)}\n`);

  console.log(`${BOLD}Detached review value${RESET}`);
  console.log(`producer: ${report.attribution.producer}`);
  console.log(`edit_id:  ${report.attribution.edit_id}`);
  console.log(`summary:  ${report.attribution.summary}`);
  console.log(`applied:  ${JSON.stringify(report.applied_edits)}`);
  console.log("newly_reachable:");
  console.log(formatFailureList(report.failure_diff.newly_reachable));
  console.log("resolved:");
  console.log(formatFailureList(report.failure_diff.resolved));

  console.log(`\n${BOLD}Boundary invariants${RESET}`);
  console.log("- report output contains no NodeId or DeclId");
  console.log("- remapping and diffing are deterministic and I/O-free");
  console.log("- host owns publication; AnalysisProjection and protocol do not");

  console.log(`\n${BOLD}[1]${RESET} binder rename  ${BOLD}[2]${RESET} resolve failure  ${BOLD}[3]${RESET} shift only  ${BOLD}[4]${RESET} rebuild  ${BOLD}[q]${RESET} quit`);
}

function selectByKey(key) {
  const next = scenarios.find((scenario) => scenario.key === key);
  if (next) selected = next;
}

readline.emitKeypressEvents(process.stdin);
if (process.stdin.isTTY) process.stdin.setRawMode(true);

process.stdin.on("keypress", (_text, key) => {
  if (key.name === "q" || (key.ctrl && key.name === "c")) {
    if (process.stdin.isTTY) process.stdin.setRawMode(false);
    console.clear();
    process.exit(0);
  }
  selectByKey(key.name);
  render();
});

render();
