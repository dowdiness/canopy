#!/usr/bin/env nu
# Migrate the legacy .githooks setting and install Lefthook.

def normalize-origin [origin: string] {
  if ($origin | str starts-with "file:") {
    $origin | str substring 5.. | path expand
  } else {
    ""
  }
}

def main [] {
  let root_result = (^git rev-parse --show-toplevel | complete)
  if $root_result.exit_code != 0 {
    print -e "error: failed to locate the repository root"
    if ($root_result.stderr | is-not-empty) {
      print -e $root_result.stderr
    }
    exit $root_result.exit_code
  }
  let root = ($root_result.stdout | str trim)
  if ($root | is-empty) {
    print -e "error: Git returned an empty repository root"
    exit 1
  }
  cd $root

  let config_result = (^git rev-parse --git-path config | complete)
  if $config_result.exit_code != 0 {
    print -e "error: failed to locate this repository's Git config"
    if ($config_result.stderr | is-not-empty) {
      print -e $config_result.stderr
    }
    exit $config_result.exit_code
  }
  let config_output = ($config_result.stdout | str trim)
  if ($config_output | is-empty) {
    print -e "error: Git returned an empty repository config path"
    exit 1
  }
  let config_path = ($config_output | path expand)
  let legacy_path = ($root | path join ".githooks" | path expand)

  # Read the complete effective value set in one call. With --null, Git emits
  # scope, origin, and value as three NUL-delimited fields per record.
  let configured = (^git config --includes --show-origin --show-scope --null --get-all core.hooksPath | complete)
  if $configured.exit_code != 0 and $configured.exit_code != 1 {
    print -e "error: failed to inspect effective core.hooksPath configuration"
    if ($configured.stderr | is-not-empty) {
      print -e $configured.stderr
    }
    exit $configured.exit_code
  }
  if $configured.exit_code == 1 and (($configured.stdout | is-not-empty) or ($configured.stderr | is-not-empty)) {
    print -e "error: Git failed while inspecting effective core.hooksPath configuration"
    if ($configured.stderr | is-not-empty) {
      print -e $configured.stderr
    }
    exit $configured.exit_code
  }
  if $configured.exit_code == 0 and ($configured.stdout | is-empty) {
    print -e "error: Git returned no data for an existing core.hooksPath configuration"
    exit 1
  }

  let entries = if $configured.exit_code == 1 {
    []
  } else {
    let raw_fields = ($configured.stdout | split row (char nul) | collect)
    let fields = if ($raw_fields | is-empty) {
      []
    } else if (($raw_fields | last) == "") {
      $raw_fields | drop
    } else {
      $raw_fields
    }
    if (($fields | length) mod 3 != 0) {
      print -e "error: Git returned malformed NUL-delimited core.hooksPath configuration"
      exit 1
    }
    $fields | chunks 3 | collect | each {|row| {
      scope: $row.0
      origin: $row.1
      value: $row.2
    }} | collect
  }

  let inspected = $entries | each {|entry| {
    scope: $entry.scope
    origin: $entry.origin
    value: $entry.value
    origin_path: (normalize-origin $entry.origin)
    value_path: ($entry.value | path expand)
  }} | collect
  let removable = $inspected | where {|entry|
    ($entry.scope == "local") and ($entry.origin_path == $config_path) and ($entry.value_path == $legacy_path)
  } | collect
  let unsafe = $inspected | where {|entry|
    not (($entry.scope == "local") and ($entry.origin_path == $config_path) and ($entry.value_path == $legacy_path))
  } | collect

  if ($unsafe | is-not-empty) {
    print -e "error: refusing to replace effective core.hooksPath configuration"
    for entry in $unsafe {
      print -e $"  scope=($entry.scope) origin=($entry.origin) value=($entry.value)"
    }
    print -e "Only direct local .githooks values from this repository's own Git config may be removed automatically."
    exit 1
  }

  let removed_values = $removable | each {|entry| $entry.value } | collect

  # Validate Lefthook before changing Git configuration.
  let validated = (^lefthook validate | complete)
  if $validated.exit_code != 0 {
    print -e "error: Lefthook validation failed"
    if ($validated.stderr | is-not-empty) {
      print -e $validated.stderr
    }
    if ($validated.stdout | is-not-empty) {
      print -e $validated.stdout
    }
    exit $validated.exit_code
  }
  if ($validated.stdout | is-not-empty) {
    print $validated.stdout
  }

  if ($removed_values | is-not-empty) {
    let unset = (^git config --local --unset-all core.hooksPath | complete)
    if $unset.exit_code != 0 {
      print -e "error: failed to remove the direct local legacy core.hooksPath"
      if ($unset.stderr | is-not-empty) {
        print -e $unset.stderr
      }
      exit $unset.exit_code
    }
    print $"Removed legacy local core.hooksPath=($removed_values | str join ', ')"
  }

  let installed = (^lefthook install | complete)
  if $installed.exit_code != 0 {
    if ($removed_values | is-not-empty) {
      let restore_results = ($removed_values | each {|value|
        let restored = (^git config --local --add core.hooksPath $value | complete)
        { value: $value, result: $restored }
      } | collect)
      let restore_failures = $restore_results | where {|item| $item.result.exit_code != 0 } | collect
      if ($restore_failures | is-empty) {
        print -e "error: Lefthook installation failed; restored the previous local core.hooksPath"
      } else {
        print -e "error: Lefthook installation failed; restoration of the previous local core.hooksPath was incomplete"
        for failure in $restore_failures {
          print -e $"  failed to restore value=($failure.value), exit status=($failure.result.exit_code)"
          if ($failure.result.stderr | is-not-empty) {
            print -e $failure.result.stderr
          }
        }
      }
    } else {
      print -e "error: Lefthook installation failed"
    }
    if ($installed.stderr | is-not-empty) {
      print -e $installed.stderr
    }
    if ($installed.stdout | is-not-empty) {
      print -e $installed.stdout
    }
    exit $installed.exit_code
  }
  if ($installed.stdout | is-not-empty) {
    print $installed.stdout
  }
}
