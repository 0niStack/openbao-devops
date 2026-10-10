# openbao-devops

Self-hosted [OpenBao](https://openbao.org) (open-source Vault fork) via Docker Compose, plus a small FastAPI app that fetches its secrets through **AppRole**.

```
openbao-devops/
├── docker-compose.yml      # openbao + demo-app (profile "app")
├── config/openbao.hcl      # server config (Raft storage)
├── policies/myapp.hcl      # least-privilege read policy
├── scripts/
│   ├── init.sh             # init + unseal (once)
│   ├── unseal.sh           # unseal after each restart
│   └── setup.sh            # KV v2, policy, AppRole, sample secret
├── app/                    # FastAPI consumer (hvac)
└── secrets/                # init.json + app.env (gitignored)
```

## Requirements
Docker + Compose v2, `jq`, `openssl`, `curl`.

## Quick start
```bash
cp .env.example .env            # optionally pin OPENBAO_VERSION
./scripts/init.sh               # start, initialize, unseal
./scripts/setup.sh              # configure + create secrets/app.env
docker compose --profile app up -d --build
curl localhost:8000/health
curl localhost:8000/secret      # masked values read from OpenBao
```
UI: http://127.0.0.1:8200 (root token from `secrets/init.json`, admin use only).

## Day-2
| Task | Command |
|---|---|
| Restart / reboot | `docker compose restart openbao && ./scripts/unseal.sh` |
| Add a secret | `docker compose exec -e BAO_TOKEN=<tok> openbao bao kv put -mount=secret myapp/other foo=bar` |
| Rotate app SecretID | re-run `./scripts/setup.sh`, then `docker compose --profile app up -d --force-recreate demo-app` |
| Raft snapshot | `docker compose exec -e BAO_TOKEN=<tok> openbao bao operator raft snapshot save /openbao/data/backup.snap` |
| Logs | `docker compose logs -f openbao` |

## Using it from other projects
- Put the other service on network `bao-net` (or reach `127.0.0.1:8200`) and pass `BAO_ADDR`, `BAO_ROLE_ID`, `BAO_SECRET_ID`, then AppRole login (see `app/main.py`).
- CI/CLI: `bao write auth/approle/login role_id=... secret_id=...` then `bao kv get -mount=secret myapp/config`.
- One policy + one AppRole per application. Never share the root token.

## Before production
1. **TLS**: `tls_disable = 1` is lab-only. Enable TLS or front it with a reverse proxy on a private network.
2. **Root token / unseal keys**: distribute the 5 shares to different people, delete `secrets/init.json`, revoke the root token, and use named admin policies (userpass or OIDC, e.g. Keycloak).
3. **Auto-unseal** (transit or cloud KMS) so restarts do not need manual unseal.
4. **Backups**: scheduled Raft snapshots to off-host storage (S3/MinIO).
5. **Audit**: `bao audit enable file file_path=/openbao/data/audit.log`.
6. The port is bound to `127.0.0.1` deliberately; expose it only through a reverse proxy.
