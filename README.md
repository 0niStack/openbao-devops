# openbao-devops

Self-hosted [OpenBao](https://openbao.org) (open-source Vault fork) via Docker Compose, plus a small FastAPI app that fetches its secrets through **AppRole**.

```
openbao-devops/
├── docker-compose.yml      # openbao-perms (one-shot) + openbao + demo-app (profile "app")
├── config/openbao.hcl      # server config (Raft storage)
├── policies/myapp.hcl      # least-privilege read policy
├── scripts/
│   ├── _common.sh          # shared helpers (bao wrapper, wait_for_api, INIT_FILE)
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

`init.sh` writes the root token and the 5 unseal keys to `secrets/init.json`. `setup.sh` reads the root token from that file, so run the scripts in this order.

## Volume permissions

The OpenBao image runs as `uid 100 / gid 1000`, but a new Docker volume is created root-owned. Without a fix, the container crash-loops with:

```
failed to open bolt file: open /openbao/data/vault.db: permission denied
```

The compose file handles this with a one-shot `openbao-perms` service that chowns the data volume before `openbao` starts:

```yaml
services:
  openbao-perms:
    image: ghcr.io/openbao/openbao:${OPENBAO_VERSION:-latest}
    user: root
    entrypoint: ["sh", "-c", "chown -R 100:1000 /openbao/data && chmod 700 /openbao/data"]
    volumes:
      - openbao-data:/openbao/data
    networks:
      - bao-net

  openbao:
    # ...
    command: ["server"]
    depends_on:
      openbao-perms:
        condition: service_completed_successfully
```

Notes:

- `openbao-perms` exits after it runs. That is expected.
- Use `command: ["server"]`. The image entrypoint already adds `-config=/openbao/config`. Passing `-config=/openbao/config` again loads the config twice and fails with `listen tcp4 0.0.0.0:8200: bind: address already in use`. If you prefer an explicit flag, use `-config=/openbao/config/openbao.hcl` (it works, with a harmless "duplicate configuration" warning).
- The `chown: ... Read-only file system` lines in the logs are harmless. The entrypoint tries to chown the read-only config mount.

## Accessing the UI

The port is published on `127.0.0.1` only, so the UI is not reachable from the internet. This is deliberate, because the lab config runs without TLS.

### Option 1: SSH tunnel (recommended)

Run on your laptop:

```bash
ssh -i /path/to/key.pem -L 8200:127.0.0.1:8200 ubuntu@<server-ip>
```

Keep the session open and browse to `http://localhost:8200/ui`. If port 8200 is taken locally, use `-L 9200:127.0.0.1:8200` and browse to `http://localhost:9200/ui`.

### Option 2: Direct access, restricted to your IP (lab only)

1. In `docker-compose.yml`, change the `openbao` port mapping to `"${OPENBAO_PORT:-8200}:8200"`.
2. In the AWS security group, add an inbound rule: TCP 8200, source **My IP** (`x.x.x.x/32`). Never use `0.0.0.0/0`.
3. `docker compose up -d openbao && ./scripts/unseal.sh`
4. Browse to `http://<server-ip>:8200/ui`.

Without TLS, the token you type is sent in plain text. Remove the rule when you are done, and switch to a reverse proxy with TLS for anything beyond a lab.

### Signing in

Choose the **Token** method. The server must be unsealed first (`./scripts/unseal.sh`).

```bash
jq -r .root_token secrets/init.json
```

Browse to **Secrets → secret → myapp → config** to view stored values. Use the root token for admin work only, and log out afterwards.

## Day-2

| Task | Command |
|---|---|
| Restart / reboot | `docker compose restart openbao && ./scripts/unseal.sh` |
| Check state | `docker compose exec -T openbao bao status` |
| Add a secret | `docker compose exec -e BAO_TOKEN=<tok> openbao bao kv put -mount=secret myapp/other foo=bar` |
| Read a secret | `docker compose exec -e BAO_TOKEN=<tok> openbao bao kv get -mount=secret myapp/config` |
| Rotate app SecretID | re-run `./scripts/setup.sh`, then `docker compose --profile app up -d --force-recreate demo-app` |
| Raft snapshot | `docker compose exec -e BAO_TOKEN=<tok> openbao bao operator raft snapshot save /openbao/data/backup.snap` |
| Logs | `docker compose logs -f openbao` |
| Full reset (destroys all data) | `docker compose down -v && rm -f secrets/init.json`, then repeat the Quick start |

A restart always re-seals OpenBao, so run `./scripts/unseal.sh` after every restart or reboot.

## Using it from other projects

- Put the other service on network `bao-net` (or reach `127.0.0.1:8200`) and pass `BAO_ADDR`, `BAO_ROLE_ID`, `BAO_SECRET_ID`, then AppRole login (see `app/main.py`).
- CI/CLI: `bao write auth/approle/login role_id=... secret_id=...` then `bao kv get -mount=secret myapp/config`.
- One policy + one AppRole per application. Never share the root token.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| Container restarting, `vault.db: permission denied` | Data volume is root-owned. Make sure the `openbao-perms` service is in the compose file, or chown the volume manually: `docker run --rm -v openbao-devops_openbao-data:/d --user root --entrypoint sh ghcr.io/openbao/openbao:latest -c 'chown -R 100:1000 /d && chmod 700 /d'` |
| `address already in use` on 8200 | The config is loaded twice. Use `command: ["server"]` (see Volume permissions). |
| `setup.sh` returns `403 permission denied` | `secrets/init.json` is empty or stale, so the token is empty or invalid. `setup.sh` ignores an exported `BAO_TOKEN` and reads the token from that file. Check `jq -r .root_token secrets/init.json`. If it is empty, `docker compose down -v`, `rm -f secrets/init.json`, and start over. |
| `setup.sh` prints "(already enabled)" along with a 403 | The script hides real errors behind `2>/dev/null \|\| echo`. Fix the token first. |
| `init.sh` fails with "container is restarting" | OpenBao was not running yet. Fix the volume permissions, confirm `docker logs openbao` shows `OpenBao server started!`, then re-run `init.sh`. |
| `secrets/init.json` is 0 bytes | A failed `init.sh` run wrote an empty file. Delete it and re-run on a healthy, uninitialized server. |
| `ERR_CONNECTION_REFUSED` from the browser | Expected. The port is bound to `127.0.0.1`. Use the SSH tunnel (see Accessing the UI). |
| `/secret` returns `abc***` values | The demo app masks secrets on purpose. Use `bao kv get` or the UI to see the stored values. |
| Sealed after restart | Run `./scripts/unseal.sh`. |

## Security notes

- `secrets/` holds the root token, unseal keys, and AppRole credentials. Keep it in `.gitignore` (check with `git check-ignore -v secrets/init.json secrets/app.env .env`), back up `init.json` off-host, and never paste it into chats or tickets. If keys are ever exposed, wipe the volume and re-initialize.
- If the server is lost, the unseal keys go with it and the data is unrecoverable. Back up the keys and Raft snapshots.

## Before production

1. **TLS**: `tls_disable = 1` is lab-only. Enable TLS (`tls_cert_file` / `tls_key_file`) or front it with a reverse proxy on a private network. Also set `cluster_addr` in `openbao.hcl` to `https://openbao:8201`.
2. **Root token / unseal keys**: distribute the 5 shares to different people, delete `secrets/init.json`, revoke the root token, and use named admin policies (userpass or OIDC, e.g. Keycloak).
3. **Auto-unseal** (transit or cloud KMS) so restarts do not need manual unseal.
4. **Backups**: scheduled Raft snapshots to off-host storage (S3/MinIO).
5. **Audit**: `bao audit enable file file_path=/openbao/data/audit.log`.
6. **Network exposure**: keep the port bound to `127.0.0.1` and expose it only through a TLS reverse proxy or a VPN.
