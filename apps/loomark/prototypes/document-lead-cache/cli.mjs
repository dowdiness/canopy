#!/usr/bin/env node
// PROTOTYPE — throwaway terminal shell around the pure lifecycle model.

import { createInterface } from "node:readline";
import { stdin as input, stdout as output } from "node:process";
import { initialState, reduce } from "./model.mjs";

const bold = "\x1b[1m";
const dim = "\x1b[2m";
const reset = "\x1b[0m";
const rl = createInterface({ input, output });
const startupViewport = process.argv.includes("--wide") ? "wide" : "narrow";
let state = initialState(startupViewport);

function field(name, value) {
  return `${bold}${name.padEnd(18)}${reset} ${value}`;
}

function render() {
  console.clear();
  console.log(`${bold}PROTOTYPE — Loomark Document-lead cache lifecycle${reset}`);
  console.log(`${dim}A state-model simulation, not proof of Rabbita runtime behavior.${reset}\n`);
  console.log(field("viewport", state.viewport));
  console.log(field("visible", String(state.visible)));
  console.log(field("presentation", state.visible
    ? state.viewport === "wide" ? "fixed pane" : "fullscreen overlay"
    : state.viewport === "wide" ? "collapsed rail" : "editor only"));
  console.log(field("selected", state.selectedId ?? "—"));
  console.log(field("mounted rows", [...state.mountedRows].join(", ") || "—"));
  console.log(field("cached keys", [...state.cache.keys()].join(", ") || "—"));
  console.log(field("extractions", state.counters.extractions));
  console.log(field("pure disposals", state.counters.pureDisposals));
  console.log(field("row builds", state.counters.rowBuilds));
  console.log(field("row disposals", state.counters.rowDisposals));
  console.log(`\n${bold}Documents${reset}`);
  for (const document of state.documents) {
    const cached = state.cache.get(document.id);
    const dirty = document.inRecent && cached?.revision !== document.leadRevision;
    console.log(
      `${document.id === state.selectedId ? ">" : " "} ${document.id}` +
      `  current=${document.currentRevision}` +
      `  quiet=${document.leadRevision ?? "—"}` +
      `  cached=${cached?.revision ?? "—"}` +
      `  ${dirty ? "DIRTY" : "clean"}` +
      `  ${document.inRecent ? "recent" : "not-listed"}`,
    );
    if (cached) console.log(`    ${dim}lead: ${cached.lead.primary}${reset}`);
  }
  console.log(`\n${bold}Last observation${reset}\n${state.lastObservation}`);
  console.log(`\n${bold}Commands${reset}`);
  console.log(`${bold}o${reset} open   ${bold}c${reset} close   ${bold}v${reset} toggle   ${bold}r${reset} resize`);
  console.log(`${bold}s ID${reset} select   ${bold}a ID${reset} add   ${bold}d ID${reset} delete`);
  console.log(`${bold}e ID TEXT${reset} edit (write \\n for a line break)   ${bold}q ID${reset} quiet elapsed`);
  console.log(`${bold}reset${reset} reset   ${bold}x${reset} exit`);
}

function parse(line) {
  const [command, id, ...rest] = line.trim().split(" ");
  switch (command) {
    case "o": return { type: "open" };
    case "c": return { type: "close" };
    case "v": return { type: "toggle" };
    case "r": return { type: "resize" };
    case "s": return { type: "select", id };
    case "a": return { type: "add", id };
    case "d": return { type: "delete", id };
    case "e": return { type: "edit", id, text: rest.join(" ").replaceAll("\\n", "\n") };
    case "q": return { type: "quiet", id };
    default: return { type: command || "unknown" };
  }
}

render();
rl.setPrompt("\n> ");
rl.prompt();
for await (const line of rl) {
  if (line.trim() === "x") break;
  state = line.trim() === "reset"
    ? initialState(startupViewport)
    : reduce(state, parse(line));
  render();
  rl.prompt();
}

rl.close();
console.clear();
console.log("Prototype closed.");
