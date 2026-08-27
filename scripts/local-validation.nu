#!/usr/bin/env nu

def fail [message: string] {
  error make { msg: $message }
}

def git-output [arguments: list<string>] {
  let result = (do { ^git ...$arguments } | complete)
  if $result.exit_code != 0 {
    fail ($result.stderr | str trim)
  }
  $result.stdout
}

def parse-name-status []: string -> list<any> {
  let raw = $in
  mut fields = ($raw | split row (char nul))
  if (($fields | length) > 0) and (($fields | last) == "") {
    $fields = ($fields | drop 1)
  }

  mut changes = []
  mut index = 0
  while $index < ($fields | length) {
    let status = ($fields | get $index)
    $index += 1
    if ($status | str starts-with "R") or ($status | str starts-with "C") {
      if ($index + 1) >= ($fields | length) {
        fail "malformed NUL-delimited Git rename record"
      }
      let old_path = ($fields | get $index)
      let new_path = ($fields | get ($index + 1))
      $index += 2
      $changes = ($changes | append { status: $status, old_path: $old_path, new_path: $new_path })
    } else {
      if $index >= ($fields | length) {
        fail "malformed NUL-delimited Git change record"
      }
      let path = ($fields | get $index)
      $index += 1
      let old_path = if $status == "A" { null } else { $path }
      let new_path = if $status == "D" { null } else { $path }
      $changes = ($changes | append { status: $status, old_path: $old_path, new_path: $new_path })
    }
  }
  $changes
}

def staged-changes [] {
  let raw = (git-output ["diff" "--cached" "--name-status" "-z" "--find-renames" "--"])
  $raw | parse-name-status
}

def committed-changes [base: string] {
  git-output ["diff" "--name-status" "-z" "--find-renames" $"($base)...HEAD" "--"]
  | parse-name-status
}

def is-moonbit-source [path: string] {
  ($path | str ends-with ".mbt") or ($path | str ends-with ".mbt.md")
}

def is-test-source [path: string] {
  let blackbox = ($path | str ends-with "_test.mbt")
  let whitebox = ($path | str ends-with "_wbtest.mbt")
  let benchmark = ($path | str ends-with "_benchmark.mbt")
  $blackbox or $whitebox or $benchmark
}

def is-generated-interface [path: string] {
  $path | str ends-with ".mbti"
}

def is-package-manifest [path: string] {
  let name = ($path | path basename)
  $name == "moon.pkg" or $name == "moon.pkg.json"
}

def is-module-manifest [path: string] {
  let name = ($path | path basename)
  $name in ["moon.mod" "moon.mod.json"]
}

def is-workspace-manifest [path: string] {
  let name = ($path | path basename)
  $name in ["moon.work" "moon.work.json"]
}

def report-workspace-manifests [changes: list<any>] {
  let paths = (
    $changes
    | each {|change| change-paths $change }
    | flatten
    | where {|path| is-workspace-manifest $path }
    | uniq
    | sort
  )
  if ($paths | is-not-empty) {
    print --stderr $"MoonBit workspace validation is deferred to GitHub CI: ($paths | str join ', ')"
  }
}

def report-removed-module-manifests [changes: list<any>] {
  let paths = (
    $changes
    | get old_path
    | compact
    | where {|path| (is-module-manifest $path) and not ($path | path exists) }
    | uniq
    | sort
  )
  if ($paths | is-not-empty) {
    print --stderr $"removed MoonBit module validation is deferred to GitHub CI: ($paths | str join ', ')"
  }
}

def parent-directory [path: string] {
  let directory = ($path | path dirname)
  if $directory == "" { "." } else { $directory }
}

def owner-for-path [root: string, path: string, manifests: list<string>] {
  let absolute_root = ($root | path expand)
  mut current = ($absolute_root | path join ($path | path dirname) | path expand)
  loop {
    let current_path = $current
    let owns_path = ($manifests | any {|manifest| ($current_path | path join $manifest) | path exists })
    if $owns_path {
      let relative = ($current | path relative-to $absolute_root)
      return (if $relative == "" { "." } else { $relative })
    }
    if $current == $absolute_root {
      return null
    }
    let parent = ($current | path dirname)
    if $parent == $current {
      return null
    }
    $current = $parent
  }
}

def package-for-path [root: string, path: string] {
  owner-for-path $root $path ["moon.pkg" "moon.pkg.json"]
}

def module-for-package [root: string, package: string] {
  let package_manifest = if $package == "." { "moon.pkg" } else { $"($package)/moon.pkg" }
  owner-for-path $root $package_manifest ["moon.mod" "moon.mod.json"]
}

def change-paths [change: record] {
  [$change.old_path $change.new_path]
  | compact
}

def module-targets [changes: list<any>] {
  $changes
  | each {|change| change-paths $change }
  | flatten
  | where {|path| (is-module-manifest $path) and ($path | path exists) }
  | each {|path| parent-directory $path }
  | uniq
  | sort
}

def packages-in-module [root: string, module: string] {
  let absolute_root = ($root | path expand)
  let module_root = if $module == "." {
    $absolute_root
  } else {
    $absolute_root | path join $module
  }
  [
    (glob ($module_root | path join "**/moon.pkg"))
    (glob ($module_root | path join "**/moon.pkg.json"))
  ]
  | flatten
  | each {|manifest|
      let relative = (
        $manifest
        | path dirname
        | path relative-to $absolute_root
        | into string
      )
      let package = if $relative == "" { "." } else { $relative }
      if (module-for-package $root $package) == $module { $package } else { null }
    }
  | compact
  | uniq
  | sort
}

def combine-package-and-module-targets [root: string, packages: list<any>, modules: list<any>] {
  let uncovered_packages = (
    $packages
    | where {|package|
        let owner = (module-for-package $root $package)
        not ($modules | any {|module| $module == $owner })
      }
  )
  let module_packages = (
    $modules
    | each {|module| packages-in-module $root $module }
    | flatten
  )
  [$uncovered_packages $module_packages]
  | flatten
  | uniq
  | sort
}

def affected-info-packages [root: string, changes: list<any>] {
  let direct_packages = (
    $changes
    | each {|change|
        change-paths $change
        | where {|path|
            let ordinary_source = ((is-moonbit-source $path) and not (is-test-source $path))
            let package_manifest = (is-package-manifest $path)
            $ordinary_source or $package_manifest or (is-generated-interface $path)
          }
        | each {|path| package-for-path $root $path }
      }
    | flatten
    | compact
  )
  combine-package-and-module-targets $root $direct_packages (module-targets $changes)
}

def affected-validation-packages [root: string, changes: list<any>] {
  let direct_packages = (
    $changes
    | each {|change|
        change-paths $change
        | where {|path|
            (is-moonbit-source $path) or (is-package-manifest $path) or (is-generated-interface $path)
          }
        | each {|path| package-for-path $root $path }
      }
    | flatten
    | compact
  )
  combine-package-and-module-targets $root $direct_packages (module-targets $changes)
}

def module-test-target [root: string, package: string] {
  let module = (module-for-package $root $package)
  if $module == null {
    fail $"cannot resolve module for package ($package)"
  }
  let directory = if $module == "." {
    $root
  } else {
    $root | path join $module
  }
  let absolute_package = if $package == "." {
    $root
  } else {
    $root | path join $package
  }
  let relative_package = (
    $absolute_package
    | path expand
    | path relative-to ($directory | path expand)
    | into string
  )
  {
    directory: $directory
    package: (if $relative_package == "" { "." } else { $relative_package })
  }
}

def clean-worktree [] {
  let status = (git-output ["status" "--porcelain=v1" "--untracked-files=all" "--ignore-submodules=none"])
  if ($status | is-not-empty) {
    fail $"worktree is not clean:\n($status)"
  }
}

def resolve-base [base: string] {
  let sha = (git-output ["rev-parse" "--verify" $"($base)^{commit}"] | str trim)
  let ancestor = (do { ^git merge-base --is-ancestor $sha HEAD } | complete)
  if $ancestor.exit_code != 0 {
    fail $"HEAD does not contain base ($base) (($sha)\)"
  }
  $sha
}

def prepare-commit [] {
  let root = (git-output ["rev-parse" "--show-toplevel"] | str trim)
  cd $root
  let changes = (staged-changes)
  report-workspace-manifests $changes
  report-removed-module-manifests $changes
  let format_paths = (
    $changes
    | get new_path
    | compact
    | where {|path| (is-moonbit-source $path) and ($path | path exists) }
    | uniq
    | sort
  )
  if ($format_paths | is-not-empty) {
    ^moon fmt ...$format_paths
  }

  let packages = (affected-info-packages $root $changes)
  if ($packages | is-not-empty) {
    ^moon info ...$packages
  }
}

def validate-push [base: string] {
  let root = (git-output ["rev-parse" "--show-toplevel"] | str trim)
  cd $root
  clean-worktree
  let base_sha = (resolve-base $base)
  let head = (git-output ["rev-parse" "HEAD"] | str trim)
  let changes = (committed-changes $base_sha)
  report-workspace-manifests $changes
  report-removed-module-manifests $changes
  let packages = (affected-validation-packages $root $changes)
  let strict_checker = ($root | path join "scripts/check-strict.sh")
  for package in $packages {
    ^$strict_checker $package
    let test_target = (module-test-target $root $package)
    do {
      cd $test_target.directory
      ^moon test --release $test_target.package
    }
  }
  ^git diff --check $"($base_sha)...($head)"
  clean-worktree
  let final_head = (git-output ["rev-parse" "HEAD"] | str trim)
  if $final_head != $head {
    fail $"HEAD changed during pre-push validation from ($head) to ($final_head)"
  }
  let final_base_sha = (git-output ["rev-parse" "--verify" $"($base)^{commit}"] | str trim)
  if $final_base_sha != $base_sha {
    fail $"($base) changed during pre-push validation from ($base_sha) to ($final_base_sha)"
  }
}

def main [operation: string, --base: string = "origin/main"] {
  match $operation {
    "prepare-commit" => { prepare-commit }
    "validate-push" => { validate-push $base }
    _ => { fail $"unknown local validation operation: ($operation)" }
  }
}
