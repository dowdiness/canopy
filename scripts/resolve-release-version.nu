#!/usr/bin/env nu
# Resolve one release version for the supported release events.
# Policy: stable SemVer with a v prefix (vMAJOR.MINOR.PATCH), without leading
# zeroes. This is intentionally narrower than the v*.*.* workflow trigger.

const SCRIPT_DIR = (path self | path dirname)
source ($SCRIPT_DIR | path join "release-version-policy.nu")

def invalid [message: string] {
  print -e $"error: ($message)"
  exit 1
}

def validate-version [version: string] {
  if not (is-stable-version $version) {
    invalid $"invalid release version '($version)'; expected vMAJOR.MINOR.PATCH"
  }
  $version
}

def main [event_name?: string ref_type?: string ref_name?: string input_version?: string] {
  let event_name = ($event_name | default "")
  let ref_type = ($ref_type | default "")
  let ref_name = ($ref_name | default "")
  let input_version = ($input_version | default "")
  let candidate = match $event_name {
    "workflow_dispatch" => {
      if ($input_version | is-empty) {
        invalid "workflow_dispatch requires a non-empty version input"
      }
      $input_version
    }
    "push" => {
      if $ref_type != "tag" {
        invalid $"push event must reference a tag, got ref type '($ref_type)'"
      }
      $ref_name
    }
    _ => {
      invalid $"unsupported release event '($event_name)'"
    }
  }

  validate-version $candidate
}
