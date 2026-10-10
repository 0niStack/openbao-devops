#!/usr/bin/env bash
# One-time: initialize OpenBao and unseal it. Keys are saved to secrets/init.json
source "$(dirname "$0")/_common.sh"
docker compose up -d openbao
wait_for_api

if [ -f "$INIT_FILE" ]; then
  echo "secrets/init.json already exists - already initialized. Use ./scripts/unseal.sh"; exit 0
fi

echo "Initializing (5 key shares, threshold 3)..."
bao operator init -key-shares=5 -key-threshold=3 -format=json > "$INIT_FILE"
chmod 600 "$INIT_FILE"
echo "Saved $INIT_FILE"
echo "!! Move the unseal keys + root token to a password manager / separate holders, then delete this file in production."

"$ROOT_DIR/scripts/unseal.sh"
