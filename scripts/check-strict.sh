#!/usr/bin/env bash

# Strict moon check — suppresses errors from vendored submodule sources.
#
# Usage: check-strict.sh [moon-check-args...]
#
# The shared filter owns the vendored directory list and understands both
# source diagnostics and moon.pkg path diagnostics.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vendored-check-common.sh"

run_moon_check_with_vendored_filter --deny-warn "$@"
