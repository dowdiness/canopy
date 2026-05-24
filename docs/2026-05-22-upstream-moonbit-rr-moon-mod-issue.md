# Filed: upstream MoonBit issues for `rr_moon_mod` migration regressions

Both issues filed against `moonbitlang/moon` on 2026-05-22.

**Filed as:**
- Issue A → [moon#1716](https://github.com/moonbitlang/moon/issues/1716) — `rr_moon_mod` migration drops path-deps with no opt-out
- Issue B → [moon#1717](https://github.com/moonbitlang/moon/issues/1717) — `moon fmt` emits invalid byte-escapes for non-ASCII `description`

**Related artifacts:**
- Local memory: `project_rr_moon_mod_migration.md`
- Canopy PR #322 — partial fix (Buffer + .pkg alias deprecations), ready to ship with note about moon#1716
- Canopy PR #320 — blocked on moon#1716

---

## Issue A — `rr_moon_mod` migration drops path-deps with no opt-out

_GitHub subject line_ &nbsp; `moon 0.1.20260522` — forced `rr_moon_mod` migration drops path-deps with no opt-out

`moon 0.1.20260522` hard-enables `rr_moon_mod`. `moon fmt` then rewrites `moon.mod.json` to TOML `moon.mod`. The rewrite drops the `path` field from every dep. The new `import {}` block has no path-dep syntax. `moon check` fails on the migrated file. I couldn't find an opt-out.

## Actual behavior

`moon fmt` rewrites:

```json
{ "deps": { "dowdiness/loom": { "path": "./loom/loom", "version": "0.1.0" } } }
```

to:

```toml
import { "dowdiness/loom", }
```

`moon check` then fails:

```
moon.mod only supports versioned registry dependencies in `import`, found `dowdiness/loom`
```

A versioned form (`"dowdiness/loom@0.1.0"`) only resolves if the target is also listed in `moon.work` `members`. The migration tool doesn't promote path-deps into `moon.work`. I also tried inline-table forms on `import {}` (`{ path = "..." }`, `path "..."`) and the lexer rejected all of them.

**Cross-repo path-deps have no fix.** Before loom#149, `loom/loom/moon.mod.json`
reached into canopy's `lib/` from inside a git submodule:

```json
"dowdiness/text_change": { "path": "../../lib/text-change" }
```

`moon.work` can't list a path owned by another repo's workspace, so workspace-promotion doesn't help.

**No opt-out.** None of these disabled `rr_moon_mod`:

```sh
moon -Z=!rr_moon_mod fmt          # Unknown feature
moon -Z=-rr_moon_mod fmt          # Unknown feature
MOON_UNSTABLE="" moon version --all       # still enabled
MOON_UNSTABLE="wasi_link" moon version --all   # still enabled
```

The CDN at `cli.moonbitlang.com/binaries/<version>/...` only serves `latest` and `nightly`. Every versioned URL I tried — `0.1.20260522`, `0.1.20260512`, `stable`, `bleeding` — returns HTTP 403. Pinning to the last working release is not an option.

## Expected Behavior

Add a TOML syntax for path-deps in `import`, e.g.

```toml
import {
  "dowdiness/loom@0.1.0" { path = "./loom/loom" },
}
```

The legacy `moon.mod.json` loader already understands path-deps. This unblocks both same-repo and cross-repo path-deps.

The migration tool should preserve `path` rather than drop it silently. Until the syntax lands, `rr_moon_mod` needs an opt-out. Default it to off, or expose a `--unstable-feature=no-rr_moon_mod` / `MOON_UNSTABLE` switch. Archiving older CDN builds would also unblock pinning as a temporary workaround.

## Steps to Reproduce

Triggers every time on any module with a path-dep:

```sh
mkdir repro && cd repro
moon work init
cat > moon.mod.json <<'EOF'
{
  "name": "test/proj",
  "version": "0.1.0",
  "deps": {
    "moonbitlang/x": { "path": "../x", "version": "0.4.0" }
  }
}
EOF
moon fmt        # drops the path field
moon check      # fails on the resulting import
```

## Environment

Operating System: Linux (WSL2, kernel 6.6.87.2-microsoft-standard-WSL2)

```
moon 0.1.20260522 (84aa893 2026-05-22) ~/.moon/bin/moon
moonc v0.9.3+3d4544a9e (2026-05-22) ~/.moon/bin/moonc
moonrun 0.1.20260522 (84aa893 2026-05-22) ~/.moon/bin/moonrun

Feature flags enabled: rr_moon_mod,rr_moon_pkg
```

## Checklist

- [x] (Optional) My case is minimal enough to be reproducible.

---

## Issue B — `moon fmt` emits invalid byte-escapes for non-ASCII `description`

_GitHub subject line_ &nbsp; `moon 0.1.20260522` — `moon fmt` produces invalid TOML byte-escapes for non-ASCII characters in `description`

`moon fmt` encodes non-ASCII chars in `description` as decimal byte escapes. An em-dash becomes `\226\128\148`. The TOML lexer then rejects the file `moon fmt` just wrote. This blocks the `moon.mod.json` → TOML migration for any project with non-ASCII text in `description`.

## Actual behavior

`description` with a U+2014 em-dash:

```json
"description": "Canopy — projectional editor"
```

is migrated to:

```toml
description = "Canopy \226\128\148 projectional editor"
```

Those escapes are the raw UTF-8 bytes of U+2014 (`0xE2 0x80 0x94`) in decimal. The lexer then rejects the file:

```
Error: Failed to calculate build plan
Caused by:
    1: failed to load `moon.mod`
    2: Lexing error at 711..806
```

I only verified U+2014, but the encoding path looks generic — Japanese, accented Latin, and emoji should all fail the same way.

## Expected Behavior

Emit non-ASCII chars as raw UTF-8. That's valid in TOML basic strings. If escapes are needed, the right form is `\uXXXX` for the Unicode codepoint. The current decimal byte-escapes target the raw UTF-8 bytes, which the lexer can't parse.

## Steps to Reproduce

```sh
mkdir repro && cd repro
moon work init
cat > moon.mod.json <<'EOF'
{
  "name": "test/proj",
  "version": "0.1.0",
  "description": "Repro — non-ASCII description"
}
EOF
moon fmt        # produces \226\128\148 byte escapes
moon check      # lexing error on the migrated file
```

Workaround: replace the em-dash with ASCII (`--`) in the source before migration.

## Environment

Operating System: Linux (WSL2, kernel 6.6.87.2-microsoft-standard-WSL2)

```
moon 0.1.20260522 (84aa893 2026-05-22) ~/.moon/bin/moon
moonc v0.9.3+3d4544a9e (2026-05-22) ~/.moon/bin/moonc
moonrun 0.1.20260522 (84aa893 2026-05-22) ~/.moon/bin/moonrun

Feature flags enabled: rr_moon_mod,rr_moon_pkg
```

## Checklist

- [x] (Optional) My case is minimal enough to be reproducible.
