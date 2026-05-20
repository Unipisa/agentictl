#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"

NODES_BIN="${AGENTICTL_NODES_BIN:-}"
if [[ -z "$NODES_BIN" ]]; then
  if [[ -x "$SCRIPT_DIR/agentictl-nodes" ]]; then
    NODES_BIN="$SCRIPT_DIR/agentictl-nodes"
  elif [[ -x "$SCRIPT_DIR/../resources/bin/agentictl-nodes" ]]; then
    NODES_BIN="$SCRIPT_DIR/../resources/bin/agentictl-nodes"
  elif [[ -x "$REPO_DIR/bin/agentictl-nodes" ]]; then
    NODES_BIN="$REPO_DIR/bin/agentictl-nodes"
  elif command -v agentictl-nodes >/dev/null 2>&1; then
    NODES_BIN="$(command -v agentictl-nodes)"
  else
    printf '{"ok":false,"error":"agentictl-nodes not found; set AGENTICTL_NODES_BIN"}\n' >&2
    exit 70
  fi
fi

exec "$NODES_BIN" "$@"
