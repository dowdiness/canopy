#!/usr/bin/env nu

# Contract test for the cache-aware MoonBit registry bootstrap boundaries.

def fail [message: string] {
  print -e $"error: ($message)"
  exit 1
}

def field [value name: string] {
  $value | get -o $name | default ""
}

def yaml-file [path: string] {
  try {
    open $path --raw | from yaml
  } catch {|err|
    fail $"could not parse YAML at ($path): ($err.msg)"
  }
}

def find-step [steps name: string] {
  let matches = ($steps | where {|step| (field $step "name") == $name })
  if ($matches | length) != 1 {
    fail $"expected exactly one step named '($name)'"
  }
  $matches | first
}

def require-equal [actual expected message: string] {
  if $actual != $expected {
    fail $"($message): got ($actual)"
  }
}

def require-text [text: string expected: string message: string] {
  if not ($text | str contains $expected) {
    fail $message
  }
}

def require-bootstrap-before-build [root: string relative_path: string] {
  let path = ($root | path join $relative_path)
  let text = (open $path --raw)
  let lines = ($text | lines)
  let bootstrap_lines = ($lines | enumerate | where {|row| $row.item | str contains "scripts/moon-update.sh" })
  if ($bootstrap_lines | length) != 1 {
    fail $"($relative_path) must call scripts/moon-update.sh exactly once"
  }
  let build_lines = ($lines | enumerate | where {|row| $row.item | str contains "moon build" })
  if ($build_lines | is-empty) {
    fail $"($relative_path) has no MoonBit build to guard"
  }
  if (($bootstrap_lines | get index | first) >= ($build_lines | get index | first)) {
    fail $"($relative_path) must bootstrap the registry before its first MoonBit build"
  }
}

def main [] {
  let root = ($env.FILE_PWD | path dirname | path expand)
  let action_path = ($root | path join ".github/actions/setup-moonbit/action.yml")
  let action = (open $action_path --raw)
  let action_doc = (yaml-file $action_path)
  let justfile = (open ($root | path join "justfile") --raw)
  let benchmark_path = ($root | path join ".github/workflows/benchmark.yml")
  let benchmark_doc = (yaml-file $benchmark_path)

  require-text $action "id: moonbit-registry-cache" "registry cache step has no stable id"
  require-text $action "cache-hit != 'true'" "bootstrap does not distinguish exact cache hits"
  require-text $action "uses: actions/cache@caa296126883cff596d87d8935842f9db880ef25" "registry cache action is not pinned to the approved full SHA"
  require-text $action "moonbit-registry-v2-" "registry cache schema version is missing"
  require-text $action "hashFiles('moon.work', '**/moon.mod', '**/moon.mod.json')" "registry cache key omits a workspace manifest"

  let action_steps = ($action_doc | get runs | get steps)
  let cache_step = (find-step $action_steps "Cache MoonBit registry state")
  let bootstrap_step = (find-step $action_steps "Bootstrap MoonBit registry")
  require-equal (field $cache_step "id") "moonbit-registry-cache" "registry cache step id changed"
  require-equal (field $bootstrap_step "if") "steps.moonbit-registry-cache.outputs.cache-hit != 'true'" "bootstrap condition changed"
  require-equal (field $bootstrap_step "run") "$GITHUB_WORKSPACE/scripts/moon-update.sh" "bootstrap command changed"
  let cache_key = (field (field $cache_step "with") "key")
  require-text $cache_key "moonbit-registry-v2-" "registry cache key has no schema version"
  require-text $cache_key "runner.os" "registry cache key omits the operating system"
  require-text $cache_key "runner.arch" "registry cache key omits the architecture"
  require-text $cache_key "toolchain-0.10.4+ade96c819-core-0.10.4+ade96c819" "registry cache key omits the pinned toolchain/core pair"
  require-text $cache_key "hashFiles('moon.work', '**/moon.mod', '**/moon.mod.json')" "registry cache key omits workspace manifests"

  let benchmark_jobs = ($benchmark_doc | get jobs)
  let benchmark_pr = ($benchmark_jobs | get "benchmark-pr")
  let benchmark_base = ($benchmark_jobs | get "benchmark-base")
  let benchmark_comparison = ($benchmark_jobs | get "benchmark-comparison")
  require-equal (field (field $benchmark_pr "outputs") "complete") "${{ steps.pr-result.outputs.complete }}" "PR benchmark completion output changed"
  require-equal (field (field $benchmark_base "outputs") "complete") "${{ steps.base-result.outputs.complete }}" "base benchmark completion output changed"

  let base_checkout = (find-step (field $benchmark_base "steps") "Checkout base branch")
  require-equal (field (field $base_checkout "with") "ref") "${{ github.event.pull_request.base.sha || github.event.repository.default_branch }}" "base benchmark must check out the event's immutable base SHA"
  let base_setup = (find-step (field $benchmark_base "steps") "Set up MoonBit")
  require-equal (field $base_setup "uses") "$/.github/actions/setup-moonbit" "base benchmark must use the running PR workflow's setup action"
  let base_cache = (find-step (field $benchmark_base "steps") "Restore base benchmark cache")
  let base_cache_key = (field (field $base_cache "with") "key")
  require-text $base_cache_key "benchmark-base-v7-bootstrap-v2-benchmark-v2-" "base benchmark cache key lacks setup/benchmark schema"

  let pr_benchmark = (find-step (field $benchmark_pr "steps") "Run PR benchmarks")
  let base_benchmark = (find-step (field $benchmark_base "steps") "Run base benchmarks")
  for benchmark in [$pr_benchmark $base_benchmark] {
    let run = (field $benchmark "run")
    require-text $run "complete=true" "benchmark success does not record completion"
    require-text $run "complete=false" "benchmark failure does not record incompletion"
    require-text $run "exit 1" "benchmark failure is not surfaced to the comparison gate"
  }

  let pr_result = (find-step (field $benchmark_pr "steps") "Record PR benchmark result")
  let base_result = (find-step (field $benchmark_base "steps") "Record base benchmark result")
  require-equal (field $pr_result "id") "pr-result" "PR benchmark result step id changed"
  require-equal (field $base_result "id") "base-result" "base benchmark result step id changed"

  require-equal (field $benchmark_comparison "if") "always()" "benchmark comparison must run to diagnose failed dependencies"
  let comparison_steps = (field $benchmark_comparison "steps")
  for name in ["Download PR benchmark results" "Download base benchmark results"] {
    let download = (find-step $comparison_steps $name)
    require-equal (field $download "continue-on-error") true $"($name) must preserve diagnostics when an upstream benchmark fails"
  }
  let compare = (find-step $comparison_steps "Compare results")
  let compare_run = (field $compare "run")
  require-text $compare_run "needs.benchmark-pr.outputs.complete" "comparison does not require a complete PR benchmark"
  require-text $compare_run "needs.benchmark-base.outputs.complete" "comparison does not require a complete base benchmark"
  require-text $compare_run "exit 1" "comparison is not fail-closed"
  let comment = (find-step $comparison_steps "Post comment to PR")
  require-text (field $comment "if") "always()" "failed benchmark diagnostics are not posted"
  let comparison_upload = (find-step $comparison_steps "Upload benchmark comparison")
  require-text (field $comparison_upload "if") "always()" "failed benchmark diagnostics are not uploaded"

  require-bootstrap-before-build $root "apps/web/scripts/build-deploy.sh"
  require-bootstrap-before-build $root "apps/ideal/scripts/build-deploy.sh"

  if not ($justfile | lines | any {|line| ($line | str trim) == "registry-refresh:" }) {
    fail "just registry-refresh recipe is missing"
  }
  let refresh_calls = ($justfile | lines | where {|line| $line | str contains 'bash "{{ moon_update }}"' } | length)
  if $refresh_calls != 1 {
    fail "just registry-refresh must call the retry wrapper exactly once"
  }

  let guard = (^nu ($root | path join "scripts/check-moon-update-wrapped.nu") | complete)
  if $guard.exit_code != 0 {
    print -e $guard.stderr
    exit $guard.exit_code
  }
  print $guard.stdout

  let manifests = (^nu ($root | path join "scripts/check-moon-registry-manifests.nu") | complete)
  if $manifests.exit_code != 0 {
    print -e $manifests.stderr
    exit $manifests.exit_code
  }
  print $manifests.stdout
  print "ok: MoonBit registry bootstrap contract passes"
}
