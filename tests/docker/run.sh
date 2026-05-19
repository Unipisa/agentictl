#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="$ROOT/tests/docker/compose.yml"
PROJECT_NAME="agentictl-test"

cleanup() {
  docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" down -v --remove-orphans
}

trap cleanup EXIT

docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" up -d --build

runner_id="$(docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" ps -q runner)"
[[ -n "$runner_id" ]] || {
  docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" logs --no-color
  exit 1
}

status="$(docker wait "$runner_id")"
docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" logs --no-color runner
exit "$status"
