#!/usr/bin/env nu
# Migrate the legacy .githooks setting and install Lefthook.

def main [] {
  let root = (^git rev-parse --show-toplevel | str trim)
  let configured = (^git config --local --get-all core.hooksPath | complete)
  if $configured.exit_code != 0 and $configured.exit_code != 1 {
    print -e "error: failed to inspect local core.hooksPath"
    print -e $configured.stderr
    exit $configured.exit_code
  }
  let configured_paths = if $configured.exit_code == 0 {
    $configured.stdout | lines | where {|path| ($path | str trim) | is-not-empty }
  } else {
    []
  }
  let global_configured = (^git config --global --get-all core.hooksPath | complete)
  if $global_configured.exit_code != 0 and $global_configured.exit_code != 1 {
    print -e "error: failed to inspect global core.hooksPath"
    print -e $global_configured.stderr
    exit $global_configured.exit_code
  }
  let global_paths = if $global_configured.exit_code == 0 {
    $global_configured.stdout | lines | where {|path| ($path | str trim) | is-not-empty }
  } else {
    []
  }
  if ($global_paths | is-not-empty) {
    print -e $"error: refusing to install while global core.hooksPath=($global_paths | str join ', ') is configured"
    print -e "Review the existing Git hook configuration first."
    exit 1
  }

  let legacy_path = ($root | path join ".githooks")
  let non_legacy = $configured_paths | where {|path|
    let normalized = ($path | str trim | path expand)
    $normalized != $legacy_path
  }

  if ($non_legacy | is-not-empty) {
    print -e $"error: refusing to replace local core.hooksPath=($non_legacy | str join ', ')"
    print -e "Review the existing Git hook configuration first."
    exit 1
  }

  # Validate Lefthook before changing Git configuration. This keeps a failed
  # install from leaving a legacy checkout without its existing hook path.
  ^lefthook validate

  if ($configured_paths | is-not-empty) {
    let unset = (^git config --local --unset-all core.hooksPath | complete)
    if $unset.exit_code != 0 {
      print -e "error: failed to remove the legacy local core.hooksPath"
      print -e $unset.stderr
      exit $unset.exit_code
    }
    print $"Removed legacy local core.hooksPath=($configured_paths | str join ', ')"
  }

  let installed = (^lefthook install | complete)
  if $installed.exit_code != 0 {
    for path in $configured_paths {
      ^git config --local --add core.hooksPath ($path | str trim)
    }
    print -e "error: Lefthook installation failed; restored the previous local core.hooksPath"
    print -e $installed.stderr
    exit $installed.exit_code
  }
  print $installed.stdout
}
