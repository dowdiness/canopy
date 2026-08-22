#!/bin/sh
# Read and enforce the repository MoonBit/compiler-core compatibility pair.
# Keep this POSIX shell: it is used by Bash 3.2, /bin/sh, and CI without
# requiring jq, Node, or shell-sourcing untrusted manifest contents.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
MANIFEST=${MOONBIT_TOOLCHAIN_MANIFEST:-$SCRIPT_DIR/../.moonbit-toolchain}

fail() {
  echo "moon-toolchain: $*" >&2
  exit 1
}

compiler=
core=
compiler_seen=0
core_seen=0
[ -f "$MANIFEST" ] || fail "manifest not found: $MANIFEST"

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    ''|\#*) continue ;;
    compiler=*)
      [ "$compiler_seen" -eq 0 ] || fail "duplicate compiler entry in $MANIFEST"
      compiler=${line#compiler=}
      compiler_seen=1
      ;;
    core=*)
      [ "$core_seen" -eq 0 ] || fail "duplicate core entry in $MANIFEST"
      core=${line#core=}
      core_seen=1
      ;;
    *) fail "invalid manifest line in $MANIFEST: $line" ;;
  esac

done < "$MANIFEST"

[ "$compiler_seen" -eq 1 ] || fail "manifest is missing compiler"
[ "$core_seen" -eq 1 ] || fail "manifest is missing core"
case "$compiler" in ''|*[!A-Za-z0-9.+_-]*) fail "invalid compiler version in $MANIFEST" ;; esac
case "$core" in ''|*[!A-Za-z0-9.+_-]*) fail "invalid core version in $MANIFEST" ;; esac
[ "$compiler" = "$core" ] || fail "compiler and core must be the same compatibility pair"

moon_is_pinned() {
  command -v moon >/dev/null 2>&1 || return 1
  moon version --all 2>/dev/null |
    awk -v expected="v$compiler" '$1 == "moonc" && $2 == expected { found=1 } END { exit(found ? 0 : 1) }'
}

ensure_toolchain() {
  export PATH="$HOME/.moon/bin:$PATH"
  if moon_is_pinned; then
    return 0
  fi
  command -v curl >/dev/null 2>&1 || {
    echo "moon-toolchain: curl is required to install MoonBit $compiler." >&2
    return 2
  }
  echo "moon-toolchain: installing MoonBit $compiler..." >&2
  installer=
  if ! installer=$(curl -fsSL https://cli.moonbitlang.com/install/unix.sh); then
    echo "moon-toolchain: failed to install MoonBit $compiler." >&2
    return 1
  fi
  if ! printf '%s\n' "$installer" | bash -s -- "$compiler"; then
    echo "moon-toolchain: failed to install MoonBit $compiler." >&2
    return 1
  fi
  export PATH="$HOME/.moon/bin:$PATH"
  if ! moon_is_pinned; then
    echo "moon-toolchain: installed MoonBit does not provide moonc v$compiler." >&2
    return 1
  fi
}

command=${1:-}
case "$command" in
  get)
    [ "$#" -eq 2 ] || fail "usage: $0 get compiler|core"
    case "$2" in
      compiler) printf '%s\n' "$compiler" ;;
      core) printf '%s\n' "$core" ;;
      *) fail "unknown toolchain field: $2" ;;
    esac
    ;;
  github-output)
    [ "$#" -eq 1 ] || fail "usage: $0 github-output"
    printf 'compiler=%s\ncore=%s\n' "$compiler" "$core"
    ;;
  check)
    [ "$#" -eq 1 ] || fail "usage: $0 check"
    moon_is_pinned
    ;;
  ensure)
    [ "$#" -eq 1 ] || fail "usage: $0 ensure"
    ensure_toolchain
    ;;
  *) fail "usage: $0 get compiler|core | github-output | check | ensure" ;;
esac
