#!/usr/bin/env nu

# Generate interfaces from each package's nearest MoonBit module root and keep
# the PR-ready gate focused on candidate-owned generated drift.

def fail [message: string] {
  print -e $"error: ($message)"
  exit 1
}

def git-result [root: string args: list<string>] {
  let result = (^git -C $root ...$args | complete)
  if $result.exit_code != 0 {
    let detail = ($result.stderr | str trim)
    fail (if ($detail | is-empty) {
      $"git command failed: git ($args | str join ' ')"
    } else {
      $detail
    })
  }
  $result.stdout
}

def module-root [root: string package_dir: string] {
  let current = ($root | path join $package_dir | path expand)
  if (($current | path join "moon.mod" | path exists) or ($current | path join "moon.mod.json" | path exists)) {
    return $current
  }
  let parent = ($current | path dirname)
  if ($parent == $current or $current == $root) {
    fail $"could not find a MoonBit module manifest for package ($package_dir)"
  }
  module-root $root ($parent | path relative-to $root)
}

def package-record [root: string package_file: string] {
  let package_dir = ($package_file | path dirname)
  let module_dir = (module-root $root $package_dir)
  let package_relative = (($root | path join $package_dir) | path relative-to $module_dir)
  {
    module_root: ($module_dir | path relative-to $root)
    package: (if ($package_relative | is-empty) { "." } else { $package_relative })
  }
}

def package-files [root: string] {
  let output = (git-result $root ["ls-files" "-z" "--" "moon.pkg" "moon.pkg.json" "*/moon.pkg" "*/moon.pkg.json"])
  $output
  | split row (char nul)
  | where {|path| not ($path | is-empty) }
}

def run-module-info [root: string module_root: string packages: list<string>] {
  let module_dir = if $module_root == "." { $root } else { $root | path join $module_root }
  let result = (do --env {
    cd $module_dir
    ^moon info ...$packages | complete
  })
  if $result.exit_code != 0 {
    print -e $result.stdout
    print -e $result.stderr
    exit $result.exit_code
  }
}

def restore-base-interface-drift [root: string base_ref: string] {
  let changed = (git-result $root ["diff" "--name-only" "--" "*.mbti"] | lines)
  $changed | each {|generated_interface|
    if ($generated_interface | is-empty) { return }
    let package_dir = ($generated_interface | path dirname)
    let candidate_diff = (^git -C $root diff --quiet $"($base_ref)...HEAD" -- $package_dir | complete)
    if $candidate_diff.exit_code == 1 {
      fail $"moon info changed a generated interface for candidate-owned package ($package_dir); commit the generated interface and rerun validation"
    } else if $candidate_diff.exit_code != 0 {
      fail ($candidate_diff.stderr | str trim)
    }
    let restored = (^git -C $root restore --worktree -- $generated_interface | complete)
    if $restored.exit_code != 0 {
      fail ($restored.stderr | str trim)
    }
  }
}

def main [--base: string = "origin/main"] {
  $env.NEW_MOON_MOD = "0"
  let root = ($env.FILE_PWD | path dirname | path expand)
  let packages = (package-files $root | each {|path| package-record $root $path })
  let groups = ($packages | group-by module_root)
  $groups | transpose module_root entries | each {|group|
    let package_names = ($group.entries | get package | uniq)
    run-module-info $root $group.module_root $package_names
  }
  restore-base-interface-drift $root $base
  null
}
