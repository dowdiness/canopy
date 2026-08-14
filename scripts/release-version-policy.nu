#!/usr/bin/env nu
# Shared strict stable release-version policy.
# Accepted values are vMAJOR.MINOR.PATCH with no leading zeroes.

def parse-stable-version [version: string] {
  let matches = ($version | parse -r '^v(?P<major>0|[1-9][0-9]*)\.(?P<minor>0|[1-9][0-9]*)\.(?P<patch>0|[1-9][0-9]*)$')
  if ($matches | is-empty) {
    null
  } else {
    $matches | first
  }
}

def is-stable-version [version: string] {
  (parse-stable-version $version | is-not-empty)
}
