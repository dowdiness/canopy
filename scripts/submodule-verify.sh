#!/usr/bin/env bash
set -euo pipefail

git submodule foreach '
  sha=$(git rev-parse HEAD)
  url=$(git config -f $toplevel/.gitmodules submodule.$name.url)
  if ! git ls-remote "$url" "$sha" | grep -q "$sha"; then
    echo "Missing $name commit $sha on $url"
    exit 1
  fi
'
