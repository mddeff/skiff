#!/usr/bin/env bash
# TODO(skiff#11): wire this into CI on tag push (v[0-9]* — not v*, that also
# matches vscode-v* tags) to produce skiff-airgap.tgz as a release asset
# instead of requiring someone to run this by hand on a bastion.
#
# Run on a networked bastion host. Bundles skiff, outboard, mermaid.js, and
# the three Google Fonts families the dashboard links to into a single
# tarball for hand-carrying into an airgapped environment.
#
# Usage:
#   scripts/airgap-prep.sh [output.tar.gz]
#
# Env overrides:
#   SKIFF_REPO_URL, OUTBOARD_REPO_URL   clone sources
#   SKIFF_REF, OUTBOARD_REF             branch or tag to clone (default: main)
#   MERMAID_URL                          mermaid UMD build to fetch
#
# Quick-and-dirty by design (see skiff#9's larger graceful-fallback issue for
# the durable version): this just fetches known-good URLs into a tarball.
# It does not pin arbitrary commit SHAs (git clone --branch needs a ref the
# remote advertises) — pass a tag via SKIFF_REF/OUTBOARD_REF if you need a
# specific point in history.

set -euo pipefail

SKIFF_REPO_URL="${SKIFF_REPO_URL:-https://github.com/mddeff/skiff}"
OUTBOARD_REPO_URL="${OUTBOARD_REPO_URL:-https://github.com/mddeff/outboard}"
SKIFF_REF="${SKIFF_REF:-main}"
OUTBOARD_REF="${OUTBOARD_REF:-main}"
MERMAID_URL="${MERMAID_URL:-https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js}"
OUT="${1:-airgap-bundle-$(date +%Y%m%d).tar.gz}"

UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
FONT_QUERY="family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&family=Space+Grotesk:wght@600;700&display=swap"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> cloning skiff@${SKIFF_REF}"
git clone --quiet --depth 1 --branch "$SKIFF_REF" "$SKIFF_REPO_URL" "$WORK/skiff"
SKIFF_SHA="$(git -C "$WORK/skiff" rev-parse HEAD)"
rm -rf "$WORK/skiff/.git"

echo "==> cloning outboard@${OUTBOARD_REF}"
git clone --quiet --depth 1 --branch "$OUTBOARD_REF" "$OUTBOARD_REPO_URL" "$WORK/outboard"
OUTBOARD_SHA="$(git -C "$WORK/outboard" rev-parse HEAD)"
rm -rf "$WORK/outboard/.git"

echo "==> fetching mermaid"
mkdir -p "$WORK/vendor"
curl -fsSL "$MERMAID_URL" -o "$WORK/vendor/mermaid.min.js"

echo "==> fetching fonts"
mkdir -p "$WORK/fonts"
curl -fsSL -A "$UA" "https://fonts.googleapis.com/css2?${FONT_QUERY}" -o "$WORK/fonts/fonts.css"
# Google serves woff2 to this UA; pull every url(...) it references and
# rewrite the CSS to point at the local filename instead.
grep -oE 'https://fonts\.gstatic\.com/[^)]+\.woff2' "$WORK/fonts/fonts.css" | sort -u | while read -r url; do
  fname="$(basename "$url")"
  echo "    ${fname}"
  curl -fsSL "$url" -o "$WORK/fonts/${fname}"
  esc_url="$(printf '%s\n' "$url" | sed 's/[&/\]/\\&/g')"
  sed -i.bak "s#${esc_url}#/static/fonts/${fname}#g" "$WORK/fonts/fonts.css"
  rm -f "$WORK/fonts/fonts.css.bak"
done

cat > "$WORK/MANIFEST.txt" <<EOF
airgap bundle built $(date -u +%Y-%m-%dT%H:%M:%SZ)
skiff:    ${SKIFF_REPO_URL} @ ${SKIFF_REF} (${SKIFF_SHA})
outboard: ${OUTBOARD_REPO_URL} @ ${OUTBOARD_REF} (${OUTBOARD_SHA})
mermaid:  ${MERMAID_URL}
fonts:    Inter, JetBrains Mono, Space Grotesk (woff2, via fonts.googleapis.com css2 API)
EOF

echo "==> packaging ${OUT}"
tar -C "$WORK" -czf "$OUT" skiff outboard vendor fonts MANIFEST.txt

echo "==> done"
cat "$WORK/MANIFEST.txt"
( command -v sha256sum >/dev/null 2>&1 && sha256sum "$OUT" ) || \
  ( command -v shasum >/dev/null 2>&1 && shasum -a 256 "$OUT" ) || true
