#!/usr/bin/env bash
# Install git pre-commit hook

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

HOOK_FILE="$PROJECT_ROOT/.git/hooks/pre-commit"

echo "Installing pre-commit hook..."

cat > "$HOOK_FILE" << 'EOF'
#!/usr/bin/env bash
# Pre-commit hook: use repo entrypoints for root checks

set -e

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

echo "Running pre-commit checks..."

echo "🔍 Running make check..."
if ! make check; then
    echo "❌ Root check failed. Please fix the issues and try again."
    exit 1
fi

echo "📝 Running make fmt-check..."
if ! make fmt-check; then
    echo "❌ Formatting drift detected. Please run 'make fmt' and review the changes."
    exit 1
fi

echo "✅ Pre-commit checks passed!"
EOF

chmod +x "$HOOK_FILE"

echo "✅ Pre-commit hook installed successfully!"
echo ""
echo "The hook will run 'make check' and 'make fmt-check' before each commit."
echo ""
echo "To bypass the hook (not recommended), use: git commit --no-verify"
