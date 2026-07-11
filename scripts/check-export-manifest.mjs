#!/usr/bin/env node
// Compare the declared FFI export manifest (examples/ideal/export-manifest.json)
// against the three hand-maintained live layers of the lambda app seam:
//
//   1. ffi/lambda/moon.pkg            — JS "exports" array of the FFI package
//   2. examples/ideal/main/moon.pkg   — JS "exports" array of the app package
//   3. examples/ideal/main/crdt_reexport.mbt — `pub fn` wrapper definitions
//
// Parallel-run contract (S4 PR2): the live files remain authoritative; this
// check reports symbol-level discrepancies in each direction (manifest-only,
// moon.pkg-only, wrapper-only) so an author knows exactly which symbol is
// missing from which layer. It never rewrites or generates any of the files.
//
// Exit code 0 = all layers agree with the manifest; 1 = discrepancies found.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const MANIFEST_PATH = "examples/ideal/export-manifest.json";

function read(rel) {
  return readFileSync(join(repoRoot, rel), "utf8");
}

// Parse the JS "exports" string array out of a moon.pkg options(link:) block.
// moon.pkg is not JSON, so locate the `"exports": [` bracket and collect the
// quoted names up to the matching `]`. `//` line comments are stripped first
// so a commented-out entry is correctly treated as removed (export names are
// [A-Za-z0-9_] only, so `//` can never occur inside a quoted name).
function parseMoonPkgExports(rel) {
  const src = read(rel).replace(/\/\/.*$/gm, "");
  const start = src.indexOf('"exports"');
  if (start === -1) {
    throw new Error(`${rel}: no "exports" array found`);
  }
  const open = src.indexOf("[", start);
  const close = src.indexOf("]", open);
  if (open === -1 || close === -1) {
    throw new Error(`${rel}: malformed "exports" array`);
  }
  const names = [...src.slice(open + 1, close).matchAll(/"([A-Za-z0-9_]+)"/g)]
    .map((m) => m[1]);
  if (names.length === 0) {
    throw new Error(`${rel}: "exports" array parsed to zero symbols`);
  }
  return names;
}

// Parse `pub fn <name>` definitions out of the wrapper .mbt file.
function parseWrapperFns(rel) {
  const src = read(rel);
  const names = [...src.matchAll(/^pub fn ([A-Za-z0-9_]+)/gm)].map((m) => m[1]);
  if (names.length === 0) {
    throw new Error(`${rel}: parsed zero \`pub fn\` wrappers`);
  }
  return names;
}

function diffSets(label, declared, declaredName, live, liveName) {
  const declaredSet = new Set(declared);
  const liveSet = new Set(live);
  const onlyDeclared = declared.filter((s) => !liveSet.has(s));
  const onlyLive = live.filter((s) => !declaredSet.has(s));
  let failed = false;
  for (const s of onlyDeclared) {
    console.error(`FAIL [${label}] ${s}: in ${declaredName} but missing from ${liveName}`);
    failed = true;
  }
  for (const s of onlyLive) {
    console.error(`FAIL [${label}] ${s}: in ${liveName} but missing from ${declaredName}`);
    failed = true;
  }
  return failed;
}

function dupes(names) {
  const seen = new Set();
  return names.filter((s) => (seen.has(s) ? true : (seen.add(s), false)));
}

const manifest = JSON.parse(read(MANIFEST_PATH));
const ffiLive = parseMoonPkgExports(manifest.ffi_package);
const appLive = parseMoonPkgExports(manifest.app_package);
const wrapperLive = parseWrapperFns(manifest.wrapper_file);

let failed = false;

for (const [name, list] of [
  [`${MANIFEST_PATH} ffi_exports`, manifest.ffi_exports],
  [`${MANIFEST_PATH} app_reexports`, manifest.app_reexports],
  [manifest.ffi_package, ffiLive],
  [manifest.app_package, appLive],
  [manifest.wrapper_file, wrapperLive],
]) {
  for (const s of dupes(list)) {
    console.error(`FAIL [duplicate] ${s}: listed more than once in ${name}`);
    failed = true;
  }
}

failed = diffSets(
  "manifest<->ffi moon.pkg",
  manifest.ffi_exports, "manifest ffi_exports",
  ffiLive, manifest.ffi_package,
) || failed;
failed = diffSets(
  "manifest<->app moon.pkg",
  manifest.app_reexports, "manifest app_reexports",
  appLive, manifest.app_package,
) || failed;
failed = diffSets(
  "manifest<->wrapper",
  manifest.app_reexports, "manifest app_reexports",
  wrapperLive, manifest.wrapper_file,
) || failed;

// Seam invariant: every app re-export must exist in the FFI export surface,
// otherwise the wrapper would call a symbol the FFI package never exposes.
const ffiSet = new Set(manifest.ffi_exports);
for (const s of manifest.app_reexports) {
  if (!ffiSet.has(s)) {
    console.error(`FAIL [seam] ${s}: in manifest app_reexports but not in manifest ffi_exports`);
    failed = true;
  }
}

if (failed) {
  console.error(
    "\nexport-manifest check FAILED. Fix the live file if the symbol is a real" +
    " discrepancy, or update examples/ideal/export-manifest.json if the seam" +
    " intentionally changed. Do not weaken this check.",
  );
  process.exit(1);
}

console.log(
  `export-manifest check OK: ${manifest.ffi_exports.length} ffi exports, ` +
  `${manifest.app_reexports.length} app re-exports, 3 layers consistent.`,
);
