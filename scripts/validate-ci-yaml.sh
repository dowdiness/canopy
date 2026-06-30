#!/usr/bin/env bash
# Validate all GitHub Actions workflow YAML files in .github/workflows/.
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
for f in "$REPO_ROOT"/.github/workflows/*.yml; do
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
  echo "❌ $errors workflow file(s) have YAML errors"
  exit 1
fi
echo "✅ All workflow YAML files valid"
