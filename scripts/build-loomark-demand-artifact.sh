#!/usr/bin/env bash
set -euo pipefail

# Build an isolated, test-only Loomark artifact. The production checkout and
# dist are never instrumented. The temporary copy gets an extraction counter
# and a query-selected fixture for the public Recent documents interface.
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUT=${1:?usage: $0 OUTPUT_DIR}
"$ROOT/scripts/moon-toolchain.sh" ensure >/dev/null
"$ROOT/scripts/install-local-warren.sh" "$ROOT/_build/tools/bin" >/dev/null
TMP=$(mktemp -d "${TMPDIR:-/tmp}/loomark-demand.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/apps"
cp -a "$ROOT/apps/loomark" "$TMP/apps/loomark"
for name in ideal block-editor; do ln -s "$ROOT/apps/$name" "$TMP/apps/$name"; done
for name in examples tools; do ln -s "$ROOT/$name" "$TMP/$name"; done
cp "$ROOT/moon.work" "$ROOT/.moonbit-toolchain" "$TMP/"
for name in deps modules _build .mooncakes; do ln -s "$ROOT/$name" "$TMP/$name"; done
python3 - "$TMP/apps/loomark/main/moon.pkg" "$TMP/apps/loomark/main/main.mbt" \
  "$ROOT/apps/loomark/examples/vanilla/fixtures/recent-dialog-demand.mbt" <<'PY'
from pathlib import Path
import sys
pkg_path = Path(sys.argv[1])
pkg = pkg_path.read_text()
imports = '''  "dowdiness/loomark/app",
  "moonbit-community/rabbita",
'''
replacement = '''  "dowdiness/loomark/app",
  "dowdiness/loomark/internal/recent_documents",
  "moonbit-community/rabbita",
  "moonbit-community/rabbita/cmd",
  "moonbit-community/rabbita/html",
  "moonbitlang/core/immut/vector",
'''
if pkg.count(imports) != 1:
    raise SystemExit("expected one exact main import insertion point")
pkg_path.write_text(pkg.replace(imports, replacement, 1))

main_path = Path(sys.argv[2])
main = main_path.read_text()
fixture = Path(sys.argv[3]).read_text()
original_main = '''///|
fn main {
  @rabbita.new(@app.app).mount("app")
}
'''
replacement_main = '''///|
#cfg(target="js")
extern "js" fn demand_dialog_query() -> Bool =
  #| () => new URLSearchParams(location.search).has("recent-dialog-demand")

///|
fn main {
  if demand_dialog_query() {
    @rabbita.new(() => demand_dialog_fixture()).mount("app")
  } else {
    @rabbita.new(@app.app).mount("app")
  }
}
'''
if main.count(original_main) != 1:
    raise SystemExit("expected one exact main function shape")
main_path.write_text(main.replace(original_main, fixture + "\n" + replacement_main, 1))
PY

python3 - "$TMP/apps/loomark/internal/document_lead/lead.mbt" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
ffi = '''///|\n#cfg(target="js")\nextern "js" fn test_count_extract() -> Unit =\n  #|(() => { globalThis.__loomarkDocumentLeadExtractCount = (globalThis.__loomarkDocumentLeadExtractCount ?? 0) + 1 })\n\n'''
needle = 'pub fn extract(source : String) -> DocumentLead {\n'
if text.count(needle) != 1:
    raise SystemExit(f"expected one named extract entry, found {text.count(needle)}")
text = text.replace(needle, ffi + needle + '  test_count_extract()\n', 1)
path.write_text(text)
PY
rm -rf "$OUT"
mkdir -p "$OUT"
mkdir -p "$TMP/apps/loomark/demand-dist"
(cd "$TMP/apps/loomark" && "$ROOT/_build/tools/bin/warren" build --public-dir public --dist demand-dist)
cp -a "$TMP/apps/loomark/demand-dist/." "$OUT/"
