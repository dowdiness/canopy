#!/usr/bin/env bash

# Bash 3.2 treats declared-but-empty arrays as unbound under `set -u`.
# Keep the CLI usable with the macOS system Bash while retaining fail-fast and
# pipeline error propagation.
set -eo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
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

target_module_root() {
  local target="$1"
  local current
  current="$(cd "$target" && pwd -P)"

  while [ "$current" = "$project_root" ] || [[ "$current" == "$project_root/"* ]]; do
    if [ -f "$current/moon.mod" ] || [ -f "$current/moon.mod.json" ]; then
      printf '%s\n' "$current"
      return 0
    fi
    [ "$current" != "$project_root" ] || break
    current="$(dirname "$current")"
  done

  die "target is not inside a MoonBit module: $target"
}

module_is_root_workspace_member() {
  local module_root="$1"
  local relative_module="${module_root#"$project_root"/}"
  [ "$module_root" != "$project_root" ] || return 0
  [ -f "$project_root/moon.work" ] || return 1
  grep -Fq "\"./$relative_module\"" "$project_root/moon.work"
}

run_target_check() {
  local target="$1"
  local module_root
  local absolute_target
  local package_path
  module_root="$(target_module_root "$target")"

  if module_is_root_workspace_member "$module_root"; then
    NEW_MOON_MOD=0 "$project_root/scripts/check-strict.sh" "$target"
    return
  fi

  absolute_target="$(cd "$target" && pwd -P)"
  package_path="${absolute_target#"$module_root"/}"
  [ "$absolute_target" != "$module_root" ] || package_path="."
  (
    cd "$module_root"
    # Match the standalone-module CI policy: diagnostics from the module under
    # test remain gating while known transitive vendored diagnostics are
    # filtered by their repository paths.
    # shellcheck source=vendored-check-common.sh
    source "$project_root/scripts/vendored-check-common.sh"
    local module_path="${module_root#"$project_root"/}"
    case "$module_path" in
      deps/*)
        NEW_MOON_MOD=0 run_moon_check_with_vendored_filter \
          "--keep=$module_path" --deny-warn --warn-list=-20-82-83 "$package_path"
        ;;
      *)
        NEW_MOON_MOD=0 run_moon_check_with_vendored_filter \
          "--keep=$module_path" --deny-warn --warn-list=-20 "$package_path"
        ;;
    esac
  )
}

run_target_test() {
  local target="$1"
  local module_root
  local absolute_target
  local package_path
  module_root="$(target_module_root "$target")"

  if module_is_root_workspace_member "$module_root"; then
    NEW_MOON_MOD=0 moon test --release "$target"
    return
  fi

  absolute_target="$(cd "$target" && pwd -P)"
  package_path="${absolute_target#"$module_root"/}"
  [ "$absolute_target" != "$module_root" ] || package_path="."
  (
    cd "$module_root"
    NEW_MOON_MOD=0 moon test --release "$package_path"
  )
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
    target_module_root "$target" >/dev/null
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
  add_phase "dependencies.registry-bootstrap-wiring"
  add_phase "dependencies.agent-doc-links"
  add_phase "dependencies.documentation-lifecycle"
  add_phase "dependencies.export-manifest"
  add_phase "dependencies.update-wrapper-test"
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
  add_phase "typescript.ffi-consumers" "$base_ref"
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
      nu "$project_root/scripts/check-submodule-reachability.nu"
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
    dependencies.registry-bootstrap-wiring)
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
      # `git ls-files` spans standalone proof modules as well as the root
      # workspace. Run `moon info` from each package's nearest module root so
      # a package is never resolved against an unrelated parent module.
      local module_roots=()
      local module_packages=()
      local package_file
      local package_dir
      local search_dir
      local parent_dir
      local module_root
      local package_relative
      local module_index
      local existing_index
      while IFS= read -r -d '' package_file; do
        if [[ "$package_file" == */* ]]; then
          package_dir="${package_file%/*}"
        else
          package_dir="."
        fi

        search_dir="$project_root/$package_dir"
        while :; do
          if [ -f "$search_dir/moon.mod" ] || [ -f "$search_dir/moon.mod.json" ]; then
            break
          fi
          parent_dir="${search_dir%/*}"
          if [ "$parent_dir" = "$search_dir" ] || [ "$search_dir" = "$project_root" ]; then
            die "could not find a MoonBit module manifest for package $package_dir"
          fi
          search_dir="$parent_dir"
        done

        module_root="${search_dir#"$project_root"/}"
        if [ "$module_root" = "$search_dir" ]; then
          module_root="."
        fi
        if [ "$package_dir" = "$module_root" ]; then
          package_relative="."
        else
          package_relative="${package_dir#"$module_root"/}"
        fi

        module_index=-1
        existing_index=0
        for existing_index in "${!module_roots[@]}"; do
          if [ "${module_roots[$existing_index]}" = "$module_root" ]; then
            module_index="$existing_index"
            break
          fi
        done
        if [ "$module_index" -lt 0 ]; then
          module_roots+=("$module_root")
          module_packages+=("$package_relative")
        else
          module_packages[$module_index]="${module_packages[$module_index]}|$package_relative"
        fi
      done < <(
        git ls-files -z -- \
          'moon.pkg' 'moon.pkg.json' '*/moon.pkg' '*/moon.pkg.json'
      )

      local package_args=()
      local module_root_dir
      if [ "${#module_roots[@]}" -gt 0 ]; then
        for module_index in "${!module_roots[@]}"; do
          IFS='|' read -r -a package_args <<< "${module_packages[$module_index]}"
          module_root_dir="$project_root/${module_roots[$module_index]}"
          (
            cd "$module_root_dir"
            NEW_MOON_MOD=0 moon info "${package_args[@]}"
          )
        done
      fi

      # A base branch can carry source changes whose generated interface was
      # not refreshed yet. Keep this gate focused on drift introduced by the
      # candidate branch: restore only generated interfaces whose package has
      # no diff in base...HEAD, and fail for candidate-owned package drift.
      local generated_interfaces
      local generated_interface
      local generated_package
      generated_interfaces="$(git diff --name-only -- '*.mbti')"
      while IFS= read -r generated_interface; do
        [ -n "$generated_interface" ] || continue
        if [[ "$generated_interface" == */* ]]; then
          generated_package="${generated_interface%/*}"
        else
          generated_package="."
        fi
        if ! git diff --quiet "$base_ref...HEAD" -- "$generated_package"; then
          die "moon info changed a generated interface for candidate-owned package $generated_package; commit the generated interface and rerun validation"
        fi
        git checkout -- "$generated_interface"
      done <<EOF
$generated_interfaces
EOF
      assert_clean_worktree
      ;;
    target.check)
      run_target_check "$argument"
      ;;
    target.test)
      run_target_test "$argument"
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
    typescript.ffi-consumers)
      ./scripts/check-ffi-consumers.sh "$argument"
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
