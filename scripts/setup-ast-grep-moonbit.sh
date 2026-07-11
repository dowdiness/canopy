#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CACHE_DIR="$ROOT/.ast-grep"
GRAMMAR_DIR="$CACHE_DIR/tree-sitter-moonbit"
REV="${TREE_SITTER_MOONBIT_REV:-c76eb43a7ea35de24eec13dee1fe22fadb2533d7}"
REPO_URL="${TREE_SITTER_MOONBIT_REPO:-https://github.com/moonbitlang/tree-sitter-moonbit.git}"
CC_BIN="${CC:-cc}"

mkdir -p "$CACHE_DIR"

if [[ ! -d "$GRAMMAR_DIR/.git" ]]; then
  git clone --filter=blob:none "$REPO_URL" "$GRAMMAR_DIR"
fi

git -C "$GRAMMAR_DIR" fetch --depth 1 origin "$REV"
git -C "$GRAMMAR_DIR" checkout --detach "$REV" >/dev/null

case "$(uname -s)" in
  Linux)
    OUT="$CACHE_DIR/tree-sitter-moonbit.so"
    SHARED_FLAGS=(-shared)
    ;;
  Darwin)
    OUT="$CACHE_DIR/tree-sitter-moonbit.dylib"
    SHARED_FLAGS=(-dynamiclib)
    ;;
  *)
    echo "unsupported OS for this setup script: $(uname -s)" >&2
    exit 1
    ;;
esac

"$CC_BIN" -fPIC "${SHARED_FLAGS[@]}" \
  "$GRAMMAR_DIR/src/parser.c" \
  "$GRAMMAR_DIR/src/scanner.c" \
  -I "$GRAMMAR_DIR/src" \
  -o "$OUT"

echo "built $OUT"
echo "ast-grep is now configured via $ROOT/sgconfig.yml"
