#!/usr/bin/env bash

set -euo pipefail

# Route every `moon update` through the retry wrapper so a transient mooncakes
# CDN 403 (issue #467) auto-recovers instead of reddening CI. Absolute path so
# it survives the `cd` into each submodule below.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
moon_update="$SCRIPT_DIR/moon-update.sh"

"$moon_update"
cd event-graph-walker && "$moon_update"
cd ../loom/loom && "$moon_update"
cd ../../svg-dsl && "$moon_update"
cd ../graphviz && "$moon_update"
