#!/usr/bin/env nu

# Verify that every registry dependency has an explicit version.
#
# The walk intentionally includes initialized submodules. Local path
# dependencies are exempt because their source is supplied by the checkout.

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

def main [] {
  let root = ($env.FILE_PWD | path dirname | path expand)
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
    print -e "registry manifest contract failed: no registry dependencies were found"
    exit 1
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
