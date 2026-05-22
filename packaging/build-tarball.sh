#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
VERSION="${1:-0.1.0}"
NAME="agentictl-$VERSION"
DIST_DIR="$REPO_DIR/dist"
ARCHIVE="$DIST_DIR/$NAME.tar.gz"
NODE_PAYLOAD="$DIST_DIR/$NAME.node.tar.gz"
SKILL_DIST_DIR="$REPO_DIR/skills/agentictl-ssh/resources/dist"
SKILL_NODE_DIR="$REPO_DIR/skills/agentictl-ssh/resources/node"

mkdir -p "$DIST_DIR" "$SKILL_DIST_DIR" "$SKILL_NODE_DIR"
tar -C "$REPO_DIR" \
  --exclude './dist' \
  --exclude './.git' \
  --exclude './skills/agentictl-ssh/resources/dist' \
  --transform "s#^.#$NAME#" \
  -czf "$NODE_PAYLOAD" \
  .

install -m 0644 "$NODE_PAYLOAD" "$SKILL_DIST_DIR/$NAME.tar.gz"
install -m 0755 "$REPO_DIR/install/install-node.sh" "$SKILL_NODE_DIR/install-node.sh"

if command -v sha256sum >/dev/null 2>&1; then
  SHA256="$(sha256sum "$SKILL_DIST_DIR/$NAME.tar.gz" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  SHA256="$(shasum -a 256 "$SKILL_DIST_DIR/$NAME.tar.gz" | awk '{print $1}')"
else
  printf 'error: sha256sum or shasum is required\n' >&2
  exit 1
fi

{
  printf 'VERSION=%s\n' "$VERSION"
  printf 'TARBALL=%s\n' "$NAME.tar.gz"
  printf 'SHA256=%s\n' "$SHA256"
} > "$SKILL_DIST_DIR/$NAME.manifest"

tar -C "$REPO_DIR" \
  --exclude './dist' \
  --exclude './.git' \
  --transform "s#^.#$NAME#" \
  -czf "$ARCHIVE" \
  .

rm -f "$NODE_PAYLOAD"

printf '%s\n' "$ARCHIVE"
