#!/usr/bin/env nu

# Verify the MoonBit registry bootstrap contract in one place.
#
# This command owns three related boundaries:
#   * registry-cache/bootstrap wiring and approved refresh call sites
#   * explicit versions for registry dependencies
#   * benchmark and self-contained deploy bootstrap contracts
#
# Registry refresh itself remains implemented by moon-update.sh. Build, test,
# benchmark, deploy, and release operations consume the prepared environment.

const command_pathspecs = [
  "*.yml"
  "*.yaml"
  "*.sh"
  "*.bash"
  "*.zsh"
  "*.nu"
  "justfile"
  "Taskfile*"
  ".claude/settings.json"
  ".cursor/install.sh"
]

const skip_dirs = [
  ".git"
  ".mooncakes"
  "_build"
  "node_modules"
  "dist"
  ".vite"
  ".playwright"
  "playwright-report"
  "test-results"
]

def fail [message: string] {
  print -e $"error: ($message)"
  exit 1
}

def read-file [path: string] {
  try {
    open $path --raw
  } catch {|err|
    fail $"could not read ($path): ($err.msg)"
  }
}

def require-text [text: string expected: string message: string] {
  if not ($text | str contains $expected) {
    fail $message
  }
}

def git-grep [root: string pattern: string] {
  let result = (^git -C $root grep -nE $pattern -- ...$command_pathspecs | complete)
  if $result.exit_code == 0 {
    $result.stdout
  } else if $result.exit_code == 1 {
    ""
  } else {
    fail ($result.stderr | str trim)
  }
}

def without-prefixes [text: string prefixes: list<string>] {
  $text
  | lines
  | where {|line| not ($prefixes | any {|prefix| $line | str starts-with $prefix }) }
}

def check-submodules [root: string] {
  let result = (^git -C $root submodule status --recursive | complete)
  if $result.exit_code != 0 {
    fail $"could not inspect submodule initialization state: ($result.stderr | str trim)"
  }
  $result.stdout | lines | each {|line|
    if ($line | is-empty) {
      return
    }
    let marker = ($line | str substring 0..0)
    if $marker == "-" {
      fail $"submodule is not initialized: ($line)"
    } else if $marker == "+" {
      fail $"submodule does not match its recorded gitlink: ($line)"
    } else if $marker == "U" {
      fail $"submodule has a merge conflict: ($line)"
    }
  }
}

def issue [path: string dependency: string reason: string] {
  {
    path: $path
    dependency: $dependency
    reason: $reason
  }
}

def versioned [name: string spec: any] {
  let kind = ($spec | describe)
  if ($kind == "string") {
    not ($spec | str trim | is-empty)
  } else if ($kind | str starts-with "record") {
    let version = ($spec.version? | default "")
    ($version | describe) == "string" and (not ($version | str trim | is-empty))
  } else if ($name | str contains "@") {
    let version = ($name | split row "@" | last | str trim)
    not ($version | is-empty)
  } else {
    false
  }
}

def inspect-json [path: string root: string] {
  let relative = ($path | path relative-to $root)
  let data = (try {
    open $path --raw | from json
  } catch {|err|
    return {
      count: 0
      issues: [(issue $relative "<manifest>" $"invalid JSON: ($err.msg)")]
    }
  })
  let dependencies = ($data.deps? | default {})
  if not (($dependencies | describe) | str starts-with "record") {
    return {
      count: 0
      issues: [(issue $relative "<deps>" "must be an object")]
    }
  }

  let checked = ($dependencies
    | transpose dependency spec
    | each {|entry|
      let spec = $entry.spec
      let local = (($spec | describe) | str starts-with "record") and (($spec.path? | default null) != null)
      if $local {
        null
      } else {
        {
          count: 1
          issue: (if (versioned $entry.dependency $spec) {
            null
          } else {
            issue $relative $entry.dependency "registry dependency has no explicit version"
          })
        }
      }
    }
    | where {|entry| $entry != null })
  {
    count: (if ($checked | is-empty) { 0 } else { $checked | get count | math sum })
    issues: ($checked | get issue | where {|entry| $entry != null })
  }
}

def inspect-toml [path: string root: string] {
  let relative = ($path | path relative-to $root)
  let text = (try {
    open $path --raw | str replace -a -r '#[^\n]*' ''
  } catch {|err|
    return {
      count: 0
      issues: [(issue $relative "<manifest>" $err.msg)]
    }
  })
  let lines = ($text | lines)
  let import_start = {|line| ($line | str trim) == "import {" }
  let import_end = {|line| ($line | str trim) == "}" }
  if not ($lines | any $import_start) {
    return { count: 0 issues: [] }
  }
  let body = ($lines | skip until $import_start | skip 1 | take until $import_end | str join "\n")
  let pattern = '^\s*"(?P<name>[^"@]+)(?:@(?P<version>[^"}]+))?"\s*(?:=\s*\{(?P<inline>[^}]*)\})?\s*,?\s*$'
  let imports = ($body | lines | parse -r $pattern)
  let checked = ($imports
    | each {|entry|
      let inline = ($entry.inline | default "")
      if ($inline | str contains "path =") {
        null
      } else {
        {
          count: 1
          issue: (if (($entry.version | default "") | str trim | is-empty) {
            issue $relative $entry.name "registry dependency has no explicit version"
          } else {
            null
          })
        }
      }
    }
    | where {|entry| $entry != null })
  {
    count: (if ($checked | is-empty) { 0 } else { $checked | get count | math sum })
    issues: ($checked | get issue | where {|entry| $entry != null })
  }
}

def manifest-paths [root: string] {
  let excludes = ($skip_dirs | each {|name| $"**/($name)/**"})
  let toml = (glob ($root | path join "**/moon.mod") --exclude $excludes)
  let json = (glob ($root | path join "**/moon.mod.json") --exclude $excludes)
  [$toml $json] | flatten | sort
}

def check-manifests [root: string] {
  let results = (manifest-paths $root | each {|path|
    if ($path | str ends-with ".json") {
      inspect-json $path $root
    } else {
      inspect-toml $path $root
    }
  })
  let issues = ($results | each {|result| $result.issues } | flatten)
  let count = (if ($results | is-empty) { 0 } else { $results | get count | math sum })
  if ($count == 0) {
    fail "registry manifest contract failed: no registry dependencies were found"
  }
  if not ($issues | is-empty) {
    print -e "registry manifest contract failed:"
    $issues | each {|entry|
      print -e $"  ($entry.path): ($entry.dependency): ($entry.reason)"
    }
    exit 1
  }
  print $"ok: ($count) registry dependencies have explicit versions"
}

def check-wiring [root: string action_doc: any justfile: string] {
  let action_steps = ($action_doc | get runs | get steps)
  let moonbit_step = (find-step $action_steps "Install MoonBit")
  let cache_step = (find-step $action_steps "Cache MoonBit registry state")
  let bootstrap_step = (find-step $action_steps "Bootstrap MoonBit registry")

  require-equal (field $moonbit_step "uses") "hustcer/setup-moonbit@9199da0ab63ea0c0bab1dc15f03d76e17ed4f75f" "MoonBit setup action pin changed"
  require-equal (field $cache_step "id") "moonbit-registry-cache" "registry cache step id changed"
  require-equal (field $cache_step "uses") "actions/cache@caa296126883cff596d87d8935842f9db880ef25" "registry cache action pin changed"
  require-equal (field $bootstrap_step "if") "steps.moonbit-registry-cache.outputs.cache-hit != 'true'" "bootstrap condition changed"
  require-equal (field $bootstrap_step "run") "$GITHUB_WORKSPACE/scripts/moon-update.sh" "bootstrap command changed"

  let cache_with = (field $cache_step "with")
  let cache_key = (field $cache_with "key")
  let restore_keys = (field $cache_with "restore-keys")
  let cache_paths = (field $cache_with "path")
  require-text $cache_key "moonbit-registry-v2-${{ runner.os }}-${{ runner.arch }}-toolchain-0.10.4+ade96c819-core-0.10.4+ade96c819-${{ hashFiles('moon.work', '**/moon.mod', '**/moon.mod.json') }}" "registry cache key does not encode schema, platform, toolchain, core, and manifests"
  require-text $restore_keys "moonbit-registry-v2-${{ runner.os }}-${{ runner.arch }}-toolchain-0.10.4+ade96c819-core-0.10.4+ade96c819-" "registry cache restore key is not scoped to schema/platform/toolchain/core"
  for path in ["~/.moon/registry/index" "~/.moon/registry/cache" "~/.moon/registry/symbols"] {
    require-text $cache_paths $path $"registry cache path is missing: ($path)"
  }

  let install_index = ($action_steps | enumerate | where {|row| (field $row.item "name") == "Install MoonBit" } | get index | first)
  let cache_index = ($action_steps | enumerate | where {|row| (field $row.item "name") == "Cache MoonBit registry state" } | get index | first)
  let bootstrap_index = ($action_steps | enumerate | where {|row| (field $row.item "name") == "Bootstrap MoonBit registry" } | get index | first)
  if $install_index >= $cache_index or $cache_index >= $bootstrap_index {
    fail "MoonBit setup steps must be ordered: install, cache, bootstrap"
  }

  let registry_refresh_lines = ($justfile | lines | where {|line| $line == "registry-refresh:" } | length)
  if $registry_refresh_lines != 1 { fail "just registry-refresh must be defined exactly once" }
  if ($justfile | lines | any {|line| ($line | str trim) == "update:" }) {
    fail "ambiguous update recipe remains in justfile"
  }
  let refresh_calls = ($justfile | lines | where {|line| $line | str contains 'bash "{{ moon_update }}"' } | length)
  if $refresh_calls != 1 { fail "just registry-refresh must call the retry wrapper exactly once" }

  let bare_refreshes = (without-prefixes
    (git-grep $root '(^|[[:space:];|({])moon update([[:space:];&|)}]|$)')
    [
      "scripts/check-moon-registry-bootstrap.nu:"
      "scripts/moon-update.sh:"
    ])
  if not ($bare_refreshes | is-empty) {
    $bare_refreshes | print -e
    fail "bare registry refresh remains outside scripts/moon-update.sh"
  }

  let wrapper_refreshes = (without-prefixes
    (git-grep $root '(\$GITHUB_WORKSPACE|\$SCRIPT_DIR|\$REPO_ROOT|\$root_dir)[^[:space:]]*moon-update\.sh|(^|[[:space:];|({])(\./)?scripts/moon-update\.sh')
    [
      ".cursor/install.sh:"
      ".github/actions/setup-moonbit/action.yml:"
      "apps/web/scripts/build-deploy.sh:"
      "apps/ideal/scripts/build-deploy.sh:"
      "justfile:"
      "scripts/check-moon-registry-bootstrap.nu:"
      "scripts/moon-update.sh:"
      "scripts/test-moon-update-wrapper.sh:"
    ])
  if not ($wrapper_refreshes | is-empty) {
    $wrapper_refreshes | print -e
    fail "registry refresh remains outside an approved environment or local/test boundary"
  }

  let other_refreshes = (without-prefixes
    (git-grep $root 'update-moon-deps\.sh|just update|moon-update:')
    [
      "scripts/check-moon-registry-bootstrap.nu:"
      "scripts/moon-update.sh:"
    ])
  if not ($other_refreshes | is-empty) {
    $other_refreshes | print -e
    fail "obsolete or operation-owned registry refresh wiring remains"
  }

  let obsolete = ($root | path join "scripts/update-moon-deps.sh")
  if ($obsolete | path exists) { fail "obsolete update-moon-deps.sh still exists" }
  check-submodules $root
}

def yaml-file [path: string] {
  try {
    open $path --raw | from yaml
  } catch {|err|
    fail $"could not parse YAML at ($path): ($err.msg)"
  }
}

def field [value name: string] {
  $value | get -o $name | default ""
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

def check-benchmark-and-deploy [root: string benchmark_doc: any] {
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
}

def main [] {
  let root = ($env.FILE_PWD | path dirname | path expand)
  let action_path = ($root | path join ".github/actions/setup-moonbit/action.yml")
  let benchmark_path = ($root | path join ".github/workflows/benchmark.yml")
  let just_path = ($root | path join "justfile")
  if not ($action_path | path exists) { fail "setup action is missing" }
  if not ($benchmark_path | path exists) { fail "benchmark workflow is missing" }
  if not ($just_path | path exists) { fail "justfile is missing" }

  let action_doc = (yaml-file $action_path)
  let justfile = (read-file $just_path)
  let benchmark_doc = (yaml-file $benchmark_path)

  check-wiring $root $action_doc $justfile
  check-benchmark-and-deploy $root $benchmark_doc
  check-manifests $root
  print "ok: MoonBit registry bootstrap contract passes"
}
