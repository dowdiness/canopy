#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root/apps/loomark"
NEW_MOON_MOD=0 moon build prototypes/document-lead-rabbita --target js
cd "$root"

url="http://127.0.0.1:4174/apps/loomark/prototypes/document-lead-rabbita/index.html"
printf 'PROTOTYPE — open %s\n' "$url"
exec python3 -m http.server 4174 --bind 127.0.0.1
