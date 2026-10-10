#!/usr/bin/env bash
# Configure OpenBao: KV v2, policy, AppRole, sample secret. Writes secrets/app.env for the demo app.
source "$(dirname "$0")/_common.sh"
[ -f "$INIT_FILE" ] || { echo "Run ./scripts/init.sh first." >&2; exit 1; }
export BAO_TOKEN=$(jq -r .root_token "$INIT_FILE")

echo "Enabling KV v2 at secret/ ..."
bao secrets enable -path=secret -version=2 kv 2>/dev/null || echo "  (already enabled)"

echo "Writing policy 'myapp' ..."
bao policy write myapp /openbao/policies/myapp.hcl

echo "Enabling AppRole auth ..."
bao auth enable approle 2>/dev/null || echo "  (already enabled)"

echo "Creating role 'myapp' ..."
bao write auth/approle/role/myapp \
  token_policies="myapp" token_ttl=1h token_max_ttl=4h \
  secret_id_ttl=0 secret_id_num_uses=0 >/dev/null

echo "Seeding sample secret at secret/myapp/config ..."
bao kv put -mount=secret myapp/config \
  db_user="appuser" \
  db_password="$(openssl rand -hex 16)" \
  api_key="$(openssl rand -hex 24)" >/dev/null

ROLE_ID=$(bao read -field=role_id auth/approle/role/myapp/role-id)
SECRET_ID=$(bao write -f -field=secret_id auth/approle/role/myapp/secret-id)

umask 077
cat > "$ROOT_DIR/secrets/app.env" <<ENV
BAO_ROLE_ID=$ROLE_ID
BAO_SECRET_ID=$SECRET_ID
BAO_SECRET_PATH=myapp/config
BAO_KV_MOUNT=secret
ENV

echo
echo "Done. Wrote secrets/app.env"
echo "Start the demo app:  docker compose --profile app up -d --build"
echo "Then:                curl localhost:8000/secret"
