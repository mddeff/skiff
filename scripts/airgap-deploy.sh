#!/usr/bin/env bash
# TODO(skiff#10): replace the sed/regex patch below with real local-first,
# CDN-fallback loading in app.js/index.html, so this script just drops files
# into static/vendor + static/fonts instead of patching source text.
#
# Run on the airgapped host, no network required. Unpacks a bundle built by
# airgap-prep.sh, installs skiff + outboard into place, and vendors the
# mermaid/fonts assets by rewriting the known CDN references in skiff's
# static assets.
#
# Usage:
#   scripts/airgap-deploy.sh <bundle.tar.gz>
#
# Env overrides:
#   CCC_INSTALL_DIR   default ~/.ccc/claude-command-center (skiff)
#   WATCHTOWER_DIR    default ~/dev/watchtower (outboard, dev-checkout tier —
#                     never auto-pulled, see docs/airgap.md)
#
# Quick-and-dirty by design: the asset rewrite below is a sed/grep patch
# against today's known CDN strings in app.js/index.html, not a real
# local-first-fall-back-to-CDN code path. If skiff's source moves those
# strings, the patch no-ops with a warning instead of breaking silently.

set -euo pipefail

BUNDLE="${1:?usage: airgap-deploy.sh <bundle.tar.gz>}"
CCC_INSTALL_DIR="${CCC_INSTALL_DIR:-$HOME/.ccc/claude-command-center}"
WATCHTOWER_DIR="${WATCHTOWER_DIR:-$HOME/dev/watchtower}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> unpacking ${BUNDLE}"
tar -xzf "$BUNDLE" -C "$WORK"
[ -f "$WORK/MANIFEST.txt" ] && cat "$WORK/MANIFEST.txt"

echo "==> installing skiff to ${CCC_INSTALL_DIR}"
mkdir -p "$(dirname "$CCC_INSTALL_DIR")"
if [ -e "$CCC_INSTALL_DIR" ]; then
  echo "airgap-deploy: ${CCC_INSTALL_DIR} already exists, leaving it in place" >&2
else
  cp -a "$WORK/skiff" "$CCC_INSTALL_DIR"
fi

echo "==> installing outboard to ${WATCHTOWER_DIR}"
mkdir -p "$(dirname "$WATCHTOWER_DIR")"
if [ -e "$WATCHTOWER_DIR" ]; then
  echo "airgap-deploy: ${WATCHTOWER_DIR} already exists, leaving it in place" >&2
else
  cp -a "$WORK/outboard" "$WATCHTOWER_DIR"
fi

echo "==> vendoring mermaid + fonts into the skiff checkout"
mkdir -p "$CCC_INSTALL_DIR/static/vendor" "$CCC_INSTALL_DIR/static/fonts"
cp "$WORK/vendor/mermaid.min.js" "$CCC_INSTALL_DIR/static/vendor/mermaid.min.js"
cp "$WORK/fonts/"*.woff2 "$WORK/fonts/fonts.css" "$CCC_INSTALL_DIR/static/fonts/"

echo "==> patching local asset references"
APP_JS="$CCC_INSTALL_DIR/static/app.js"
INDEX_HTML="$CCC_INSTALL_DIR/static/index.html"

if grep -q 'cdn.jsdelivr.net/npm/mermaid' "$APP_JS" 2>/dev/null; then
  sed -i.bak \
    "s#https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js#/static/vendor/mermaid.min.js#" \
    "$APP_JS"
  rm -f "$APP_JS.bak"
  echo "    app.js: mermaid now loads from /static/vendor/mermaid.min.js"
else
  echo "airgap-deploy: WARNING: mermaid CDN string not found in app.js — skiff's source moved, patch skipped. Diagrams will try the CDN and fall back to raw source offline." >&2
fi

if grep -q 'fonts.googleapis.com/css2' "$INDEX_HTML" 2>/dev/null; then
  python3 - "$INDEX_HTML" <<'PYEOF'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
pattern = re.compile(
    r'<link rel="preconnect" href="https://fonts\.googleapis\.com">\s*\n'
    r'<link rel="preconnect" href="https://fonts\.gstatic\.com" crossorigin>\s*\n'
    r'<link rel="stylesheet" href="https://fonts\.googleapis\.com/css2\?[^"]*">'
)
replacement = '<link rel="stylesheet" href="/static/fonts/fonts.css">'
new_text, n = pattern.subn(replacement, text)
if n == 0:
    print(
        "airgap-deploy: WARNING: Google Fonts <link> block not found in "
        "index.html (format shape changed) — patch skipped, page falls "
        "back to system fonts",
        file=sys.stderr,
    )
else:
    open(path, "w", encoding="utf-8").write(new_text)
    print(f"    index.html: {n} font <link> block(s) now point at /static/fonts/fonts.css")
PYEOF
else
  echo "airgap-deploy: WARNING: Google Fonts <link> not found in index.html — patch skipped, page falls back to system fonts" >&2
fi

echo "==> done. launch with:"
echo "    cd ${CCC_INSTALL_DIR} && ./run.sh"
