#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
VERSION="${1:-0.1.0}"
NAME="agentictl-$VERSION"
DIST_DIR="$REPO_DIR/dist"
ARCHIVE="$DIST_DIR/$NAME.tar.gz"

mkdir -p "$DIST_DIR"
tar -C "$REPO_DIR" \
  --exclude './dist' \
  --exclude './.git' \
  --transform "s#^.#$NAME#" \
  -czf "$ARCHIVE" \
  .

printf '%s\n' "$ARCHIVE"
