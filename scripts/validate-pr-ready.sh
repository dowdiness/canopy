#!/usr/bin/env bash

# Bash 3.2 treats declared-but-empty arrays as unbound under `set -u`.
# Keep the CLI usable with the macOS system Bash while retaining fail-fast and
# pipeline error propagation.
set -eo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(dirname "$script_dir")"
base_ref="origin/main"
base_was_set=0
mode="validate"
no_target_reason=""
targets=()
target_policy_was_set=0

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/validate-pr-ready.sh [--base REF] --target PATH [--target PATH ...]
  ./scripts/validate-pr-ready.sh [--base REF] --no-target REASON
  ./scripts/validate-pr-ready.sh --list [--base REF] (--target PATH [...] | --no-target REASON)
  ./scripts/validate-pr-ready.sh --verify-evidence

Options:
  --base REF          Local base ref that must be contained in HEAD
                      (default: origin/main; fetch it before validation).
  --target PATH       Affected MoonBit package path. Repeatable.
  --no-target REASON  Explain why no targeted MoonBit loop applies.
  --list              Print the deterministic validation plan without running it.
                      The same target policy as a real run is required.
  --verify-evidence   Verify that the last successful validation still matches
                      the current clean HEAD, base ref, and recorded target scope.
  -h, --help          Show this help.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_value() {
  local option="$1"
  local value="${2:-}"

  if [ -z "$value" ]; then
    die "$option requires a non-empty value"
  fi
  case "$value" in
    *$'\n'*) die "$option values must fit on one line" ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base)
      require_value "$1" "${2:-}"
      base_ref="$2"
      base_was_set=1
      shift 2
      ;;
    --target)
      require_value "$1" "${2:-}"
      targets+=("$2")
      target_policy_was_set=1
      shift 2
      ;;
    --no-target)
      require_value "$1" "${2:-}"
      no_target_reason="$2"
      target_policy_was_set=1
      shift 2
      ;;
    --list)
      [ "$mode" = "validate" ] || die "choose only one operating mode"
      mode="list"
      shift
      ;;
    --verify-evidence)
      [ "$mode" = "validate" ] || die "choose only one operating mode"
      mode="verify"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

cd "$project_root"

assert_target_policy() {
  if [ "${#targets[@]}" -gt 0 ] && [ -n "$no_target_reason" ]; then
    die "use --target or --no-target, not both"
  fi
  if [ "${#targets[@]}" -eq 0 ] && [ -z "$no_target_reason" ]; then
    die "provide --target or --no-target; the latter requires an explicit reason"
  fi
}

assert_targets_are_packages() {
  local target
  local previous
  local seen_targets=()

  for target in "${targets[@]}"; do
    [ -d "$target" ] || die "target path does not exist: $target"
    if [ ! -f "$target/moon.pkg" ] && [ ! -f "$target/moon.pkg.json" ]; then
      die "target is not a MoonBit package directory: $target"
    fi
    for previous in "${seen_targets[@]}"; do
      if [ "$previous" = "$target" ]; then
        die "duplicate target: $target"
      fi
    done
    seen_targets+=("$target")
  done
}

evidence_path() {
  printf '%s\n' "$project_root/_build/.canopy-pr-ready"
}

assert_clean_worktree() {
  local status
  status="$(git status --porcelain=v1 --untracked-files=all --ignore-submodules=none)"
  if [ -n "$status" ]; then
    echo "error: worktree is not clean; commit or remove these changes before validation:" >&2
    echo "$status" >&2
    exit 1
  fi
}

verify_evidence() {
  local path
  local recorded_head=""
  local recorded_base_ref=""
  local recorded_base=""
  local recorded_no_target=""
  local recorded_targets=()
  local key
  local value

  assert_clean_worktree
  path="$(evidence_path)"
  [ -f "$path" ] || die "PR-ready evidence is missing; run full validation first"

  while IFS='=' read -r key value; do
    case "$key" in
      head) recorded_head="$value" ;;
      base-ref) recorded_base_ref="$value" ;;
      base) recorded_base="$value" ;;
      target) recorded_targets+=("$value") ;;
      no-target) recorded_no_target="$value" ;;
    esac
  done <"$path"

  [ -n "$recorded_head" ] || die "PR-ready evidence is malformed"
  [ -n "$recorded_base_ref" ] || die "PR-ready evidence is malformed"
  [ -n "$recorded_base" ] || die "PR-ready evidence is malformed"
  if [ "${#recorded_targets[@]}" -gt 0 ] && [ -n "$recorded_no_target" ]; then
    die "PR-ready evidence is malformed"
  fi
  if [ "${#recorded_targets[@]}" -eq 0 ] && [ -z "$recorded_no_target" ]; then
    die "PR-ready evidence is malformed"
  fi

  local current_head
  current_head="$(git rev-parse HEAD)"
  if [ "$current_head" != "$recorded_head" ]; then
    die "PR-ready evidence is stale: HEAD changed from $recorded_head to $current_head"
  fi

  local current_base
  current_base="$(git rev-parse --verify --quiet "$recorded_base_ref^{commit}")" ||
    die "PR-ready evidence is stale: base ref $recorded_base_ref no longer resolves"
  if [ "$current_base" != "$recorded_base" ]; then
    die "PR-ready evidence is stale: $recorded_base_ref changed from $recorded_base to $current_base"
  fi

  git merge-base --is-ancestor "$recorded_base" HEAD ||
    die "PR-ready evidence is stale: HEAD does not contain recorded base $recorded_base"

  echo "validated-head=$recorded_head"
  echo "validated-base=$recorded_base"
  echo "validated-base-ref=$recorded_base_ref"
  if [ "${#recorded_targets[@]}" -gt 0 ]; then
    local recorded_target
    for recorded_target in "${recorded_targets[@]}"; do
      echo "validated-target=$recorded_target"
    done
  else
    echo "validated-no-target=$recorded_no_target"
  fi
}

if [ "$mode" = "verify" ]; then
  if [ "$base_was_set" -eq 1 ] || [ "$target_policy_was_set" -eq 1 ]; then
    die "--verify-evidence does not accept --base, --target, or --no-target"
  fi
  verify_evidence
  exit 0
fi

assert_target_policy
assert_targets_are_packages

phase_ids=()
phase_args=()

add_phase() {
  phase_ids+=("$1")
  phase_args+=("${2:-}")
}

build_plan() {
  add_phase "preflight.clean"
  add_phase "preflight.base" "$base_ref"
  add_phase "preflight.submodules"
  add_phase "dependencies.check-deps"
  add_phase "dependencies.shared-substrate"
  add_phase "dependencies.egw-resolver-identity"
  add_phase "dependencies.moon-update-wrapper"
  add_phase "dependencies.agent-doc-links"
  add_phase "dependencies.documentation-lifecycle"
  add_phase "dependencies.export-manifest"
  add_phase "dependencies.update-wrapper-test"
  add_phase "dependencies.sync"
  add_phase "format.canopy"
  add_phase "interfaces.canopy"

  if [ "${#targets[@]}" -gt 0 ]; then
    local target
    for target in "${targets[@]}"; do
      add_phase "target.check" "$target"
      add_phase "target.test" "$target"
    done
  else
    add_phase "target.skipped" "$no_target_reason"
  fi

  add_phase "suite.check"
  add_phase "suite.manifest-compat"
  add_phase "suite.test"
  add_phase "suite.build"
  add_phase "build.js"
  add_phase "diff.whitespace" "$base_ref...HEAD"
  add_phase "evidence.record"
}

format_phase() {
  local index="$1"
  local id="${phase_ids[$index]}"
  local argument="${phase_args[$index]}"

  if [ -n "$argument" ]; then
    printf '%02d %s %s\n' "$((index + 1))" "$id" "$argument"
  else
    printf '%02d %s\n' "$((index + 1))" "$id"
  fi
}

print_plan() {
  local index
  for ((index = 0; index < ${#phase_ids[@]}; index += 1)); do
    format_phase "$index"
  done
}

build_plan

if [ "$mode" = "list" ]; then
  print_plan
  exit 0
fi

start_head=""
start_base=""

run_phase() {
  local id="$1"
  local argument="$2"

  case "$id" in
    preflight.clean)
      assert_clean_worktree
      rm -f "$(evidence_path)"
      ;;
    preflight.base)
      start_head="$(git rev-parse HEAD)"
      start_base="$(git rev-parse --verify --quiet "$base_ref^{commit}")" ||
        die "base ref $base_ref does not resolve; fetch it before validation"
      git merge-base --is-ancestor "$start_base" "$start_head" ||
        die "HEAD does not contain base $base_ref ($start_base); sync or rebase first"
      ;;
    preflight.submodules)
      local submodule_status
      local line
      submodule_status="$(git submodule status --recursive)"
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "${line:0:1}" in
          -) die "submodule is not initialized: $line" ;;
          +) die "submodule does not match its recorded gitlink: $line" ;;
          U) die "submodule has a merge conflict: $line" ;;
        esac
      done <<<"$submodule_status"
      # Variables in this body are intentionally expanded inside each submodule.
      # shellcheck disable=SC2016
      git submodule foreach --quiet --recursive '
        if ! git fetch --quiet --prune origin; then
          echo "error: could not fetch submodule origin: $displaypath" >&2
          exit 1
        fi
        if [ -z "$(git for-each-ref --format="%(refname)" --contains HEAD refs/remotes/origin)" ]; then
          sha="$(git rev-parse HEAD)"
          if ! git fetch --quiet --no-tags --refetch origin "$sha"; then
            echo "error: submodule commit is not fetchable from origin: $displaypath" >&2
            echo "push the commit to the configured origin before the parent PR" >&2
            exit 1
          fi
        fi
      ' || die "submodule remote reachability check failed"
      ;;
    dependencies.check-deps)
      ./scripts/check-deps.sh
      ;;
    dependencies.shared-substrate)
      ./scripts/check-shared-substrate.sh
      ;;
    dependencies.egw-resolver-identity)
      ./scripts/check-egw-resolver-identity.sh
      ;;
    dependencies.moon-update-wrapper)
      ./scripts/check-moon-update-wrapped.sh
      ;;
    dependencies.agent-doc-links)
      bash ./scripts/check-agent-doc-links.sh
      ;;
    dependencies.documentation-lifecycle)
      ./scripts/check-documentation-lifecycle.sh
      ;;
    dependencies.export-manifest)
      node ./scripts/check-export-manifest.mjs
      ;;
    dependencies.update-wrapper-test)
      ./scripts/test-moon-update-wrapper.sh
      ;;
    dependencies.sync)
      ./scripts/update-moon-deps.sh
      assert_clean_worktree
      ;;
    format.canopy)
      local moon_sources=()
      local source_file
      while IFS= read -r -d '' source_file; do
        moon_sources+=("$source_file")
      done < <(git ls-files -z -- '*.mbt' '*.mbt.md')
      if [ "${#moon_sources[@]}" -gt 0 ]; then
        NEW_MOON_MOD=0 moon fmt --check "${moon_sources[@]}"
      fi
      ;;
    interfaces.canopy)
      local package_dirs=()
      local package_file
      local package_dir
      local existing_dir
      local already_seen
      while IFS= read -r -d '' package_file; do
        if [[ "$package_file" == */* ]]; then
          package_dir="${package_file%/*}"
        else
          package_dir="."
        fi
        already_seen=0
        for existing_dir in "${package_dirs[@]}"; do
          if [ "$existing_dir" = "$package_dir" ]; then
            already_seen=1
            break
          fi
        done
        if [ "$already_seen" -eq 0 ]; then
          package_dirs+=("$package_dir")
        fi
      done < <(
        git ls-files -z -- \
          'moon.pkg' 'moon.pkg.json' '*/moon.pkg' '*/moon.pkg.json'
      )
      if [ "${#package_dirs[@]}" -gt 0 ]; then
        NEW_MOON_MOD=0 moon info --frozen "${package_dirs[@]}"
      fi
      assert_clean_worktree
      ;;
    target.check)
      ./scripts/check-strict.sh "$argument"
      ;;
    target.test)
      NEW_MOON_MOD=0 moon test --release "$argument"
      ;;
    target.skipped)
      :
      ;;
    suite.check)
      ./scripts/check-strict.sh
      ;;
    suite.manifest-compat)
      ./scripts/check-moonbit-pkg-compat.sh
      ;;
    suite.test)
      ./scripts/check-test-baseline.sh 7 moon test --release
      ;;
    suite.build)
      NEW_MOON_MOD=0 moon build --release
      ;;
    build.js)
      ./scripts/build-js.sh
      ;;
    diff.whitespace)
      git diff --check "$base_ref...HEAD"
      ;;
    evidence.record)
      assert_clean_worktree
      local end_head
      local end_base
      end_head="$(git rev-parse HEAD)"
      end_base="$(git rev-parse --verify --quiet "$base_ref^{commit}")" ||
        die "base ref $base_ref stopped resolving during validation"
      if [ "$end_head" != "$start_head" ]; then
        die "HEAD changed during validation from $start_head to $end_head; rerun the full gate"
      fi
      if [ "$end_base" != "$start_base" ]; then
        die "$base_ref changed during validation from $start_base to $end_base; rerun the full gate"
      fi

      local evidence_file
      evidence_file="$(evidence_path)"
      mkdir -p "$(dirname "$evidence_file")"
      {
        printf 'head=%s\n' "$start_head"
        printf 'base-ref=%s\n' "$base_ref"
        printf 'base=%s\n' "$start_base"
        if [ "${#targets[@]}" -gt 0 ]; then
          local target
          for target in "${targets[@]}"; do
            printf 'target=%s\n' "$target"
          done
        else
          printf 'no-target=%s\n' "$no_target_reason"
        fi
      } >"$evidence_file"
      ;;
    *)
      die "unknown validation phase: $id"
      ;;
  esac
}

for ((phase_index = 0; phase_index < ${#phase_ids[@]}; phase_index += 1)); do
  phase_line="$(format_phase "$phase_index")"
  echo
  echo "==> $phase_line"
  run_phase "${phase_ids[$phase_index]}" "${phase_args[$phase_index]}"
done

echo
echo "PR-ready validation passed."
verify_evidence
