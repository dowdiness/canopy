#!/usr/bin/env nu

# Guard the single MoonBit registry bootstrap boundary. Registry refresh is an
# environment/bootstrap concern; build, test, benchmark, deploy, and release
# operations consume the state prepared by setup-moonbit instead of refreshing
# it themselves.

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

def require-line [text: string expected: string message: string] {
  let count = ($text | lines | where {|line| $line == $expected } | length)
  if $count != 1 {
    fail $message
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

def main [] {
  let root = ($env.FILE_PWD | path dirname | path expand)
  let action_path = ($root | path join ".github/actions/setup-moonbit/action.yml")
  let just_path = ($root | path join "justfile")
  if not ($action_path | path exists) { fail "setup action is missing" }
  if not ($just_path | path exists) { fail "justfile is missing" }

  let action = (read-file $action_path)
  let justfile = (read-file $just_path)

  require-line $action "      id: moonbit-registry-cache" "setup action lacks the stable registry cache id"
  require-line $action "      uses: hustcer/setup-moonbit@9199da0ab63ea0c0bab1dc15f03d76e17ed4f75f" "MoonBit setup action is not pinned to the approved full SHA"
  require-line $action "      uses: actions/cache@caa296126883cff596d87d8935842f9db880ef25" "registry cache action is not pinned to the approved full SHA"
  require-text $action "key: moonbit-registry-v2-${{ runner.os }}-${{ runner.arch }}-toolchain-0.10.4+ade96c819-core-0.10.4+ade96c819-${{ hashFiles('moon.work', '**/moon.mod', '**/moon.mod.json') }}" "registry cache key does not encode schema, platform, toolchain, core, and manifests"
  require-text $action "moonbit-registry-v2-${{ runner.os }}-${{ runner.arch }}-toolchain-0.10.4+ade96c819-core-0.10.4+ade96c819-" "registry cache restore key is not scoped to schema/platform/toolchain/core"
  for path in ["~/.moon/registry/index" "~/.moon/registry/cache" "~/.moon/registry/symbols"] {
    require-text $action $"  ($path)" $"registry cache path is missing: ($path)"
  }
  require-line $action "      if: steps.moonbit-registry-cache.outputs.cache-hit != 'true'" "bootstrap does not require an exact cache hit"

  let cache_line = ($action | lines | enumerate | where item == "      id: moonbit-registry-cache" | get index | first)
  let bootstrap_line = ($action | lines | enumerate | where item == "    - name: Bootstrap MoonBit registry" | get index | first)
  if $cache_line >= $bootstrap_line { fail "registry bootstrap must follow the registry cache step" }
  let bootstrap_runs = ($action | lines | where {|line| $line == '      run: "$GITHUB_WORKSPACE/scripts/moon-update.sh"' } | length)
  if $bootstrap_runs != 1 { fail "setup action must bootstrap the registry through the retry wrapper exactly once" }

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
      "scripts/check-moon-update-wrapped.nu:"
      "scripts/test-moon-registry-bootstrap.nu:"
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
      "justfile:"
      "scripts/check-moon-update-wrapped.nu:"
      "scripts/moon-update.sh:"
      "scripts/test-moon-update-wrapper.sh:"
      "scripts/test-moon-registry-bootstrap.nu:"
    ])
  if not ($wrapper_refreshes | is-empty) {
    $wrapper_refreshes | print -e
    fail "registry refresh remains outside setup-moonbit or the explicit local/test boundary"
  }

  let other_refreshes = (without-prefixes
    (git-grep $root 'update-moon-deps\.sh|just update|moon-update:')
    [
      "scripts/check-moon-update-wrapped.nu:"
      "scripts/moon-update.sh:"
      "scripts/test-moon-registry-bootstrap.nu:"
    ])
  if not ($other_refreshes | is-empty) {
    $other_refreshes | print -e
    fail "obsolete or operation-owned registry refresh wiring remains"
  }

  let obsolete = ($root | path join "scripts/update-moon-deps.sh")
  if ($obsolete | path exists) { fail "obsolete update-moon-deps.sh still exists" }
  check-submodules $root

  let manifest_check = (^nu ($root | path join "scripts/check-moon-registry-manifests.nu") | complete)
  if $manifest_check.exit_code != 0 {
    print -e $manifest_check.stderr
    exit $manifest_check.exit_code
  }
  print $manifest_check.stdout
  print "ok: MoonBit registry bootstrap wiring passes"
}
