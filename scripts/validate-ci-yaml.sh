#!/usr/bin/env bash
# Validate all GitHub Actions workflow and local composite-action YAML files.
# Uses js-yaml for proper structural parsing.
# Exit code 0 = all valid, 1 = any invalid.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Ensure js-yaml is available
if ! node -e "require('js-yaml')" 2>/dev/null; then
  npm install --no-save --silent js-yaml
fi

errors=0
for f in "$REPO_ROOT"/.github/workflows/*.yml "$REPO_ROOT"/.github/actions/*/action.yml; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  if node -e "
    const yaml = require('js-yaml');
    const fs = require('fs');
    try {
      yaml.load(fs.readFileSync('$f', 'utf8'));
    } catch(e) {
      console.error('$name: ' + e.message);
      process.exit(1);
    }
  " 2>/dev/null; then
    echo "  ✅ $name"
  else
    echo "  ❌ $name — invalid YAML"
    errors=$((errors + 1))
  fi
done

if [ "$errors" -gt 0 ]; then
  echo "❌ $errors GitHub Actions YAML file(s) have errors"
  exit 1
fi
echo "✅ All GitHub Actions YAML files valid"
