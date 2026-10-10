#!/usr/bin/env bash
# Run after every restart of the openbao container (it boots sealed)
source "$(dirname "$0")/_common.sh"
[ -f "$INIT_FILE" ] || { echo "No $INIT_FILE. Run ./scripts/init.sh first." >&2; exit 1; }

for i in 0 1 2; do
  key=$(jq -r ".unseal_keys_b64[$i]" "$INIT_FILE")
  bao operator unseal "$key" >/dev/null
done
bao status || true
