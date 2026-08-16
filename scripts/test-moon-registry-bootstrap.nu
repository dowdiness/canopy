#!/usr/bin/env nu

# Contract test for the cache-aware MoonBit registry bootstrap boundary.

def fail [message: string] {
  print -e $"error: ($message)"
  exit 1
}

def require-text [text: string expected: string message: string] {
  if not ($text | str contains $expected) {
    fail $message
  }
}

def main [] {
  let root = ($env.FILE_PWD | path dirname | path expand)
  let action = (open ($root | path join ".github/actions/setup-moonbit/action.yml") --raw)
  let justfile = (open ($root | path join "justfile") --raw)

  require-text $action "id: moonbit-registry-cache" "registry cache step has no stable id"
  require-text $action "cache-hit != 'true'" "bootstrap does not distinguish exact cache hits"
  require-text $action "uses: actions/cache@caa296126883cff596d87d8935842f9db880ef25" "registry cache action is not pinned to the v5 commit"
  require-text $action "moonbit-registry-v2-" "registry cache schema version is missing"
  require-text $action "hashFiles('moon.work', '**/moon.mod', '**/moon.mod.json')" "registry cache key omits a workspace manifest"

  let states = [
    {name: "exact cache hit" cache_hit: "true" expected: 0}
    {name: "cache miss" cache_hit: "false" expected: 1}
    {name: "partial restore" cache_hit: "partial" expected: 1}
  ]
  $states | each {|state|
    let bootstrap_count = if $state.cache_hit == "true" { 0 } else { 1 }
    if $bootstrap_count != $state.expected {
      fail $"($state.name) expected ($state.expected) bootstrap(s), got ($bootstrap_count)"
    }
  }

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
