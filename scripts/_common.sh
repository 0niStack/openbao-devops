#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
INIT_FILE="$ROOT_DIR/secrets/init.json"
[ -f .env ] || cp .env.example .env

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need docker; need jq; need openssl

# Run `bao` inside the container (token passed via BAO_TOKEN if set)
bao() { docker compose exec -T -e BAO_TOKEN="${BAO_TOKEN:-}" openbao bao "$@"; }

wait_for_api() {
  echo "Waiting for OpenBao API..."
  for _ in $(seq 1 30); do
    # `bao status` exits 0 (unsealed), 2 (sealed/uninitialized), 1 (cannot connect)
    rc=0; docker compose exec -T openbao bao status >/dev/null 2>&1 || rc=$?
    [ "$rc" -ne 1 ] && [ "$rc" -ne 126 ] && [ "$rc" -ne 125 ] && return 0
    sleep 1
  done
  echo "OpenBao did not respond in time" >&2; exit 1
}
