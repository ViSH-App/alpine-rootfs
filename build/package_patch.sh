#!/usr/bin/env bash
# Package patch/ into dist/RootfsPatch.tar.gz, the release asset iSH downloads
# at build time and ships as RootfsPatch.bundle inside the app.
# Standalone so it can be run/tested without docker; build.sh calls it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="${1:-$REPO_ROOT/dist}"
OUT_NAME="RootfsPatch.tar.gz"

mkdir -p "$DIST_DIR"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/RootfsPatch.bundle/files"
python3 "$REPO_ROOT/build/gen_patch_manifest.py" \
  "$REPO_ROOT/patch" "$STAGE/RootfsPatch.bundle/manifest.plist"
tar -C "$REPO_ROOT/patch/files" --exclude='.gitkeep' --exclude='.DS_Store' -cf - . \
  | tar -C "$STAGE/RootfsPatch.bundle/files" -xf -

# COPYFILE_DISABLE keeps macOS from injecting ._* AppleDouble entries.
COPYFILE_DISABLE=1 tar -C "$STAGE" -czf "$DIST_DIR/$OUT_NAME" RootfsPatch.bundle

cd "$DIST_DIR"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$OUT_NAME" > "$OUT_NAME.sha256"
else
  shasum -a 256 "$OUT_NAME" > "$OUT_NAME.sha256"
fi

echo ">> Packed $DIST_DIR/$OUT_NAME (patch v$(tr -cd '0-9' < "$REPO_ROOT/patch/VERSION"))"
cat "$OUT_NAME.sha256"
