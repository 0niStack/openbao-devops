"""Demo FastAPI app that reads secrets from OpenBao via AppRole.
hvac works with OpenBao because the API is Vault-compatible."""
import os
import hvac
from fastapi import FastAPI, HTTPException

BAO_ADDR = os.environ["BAO_ADDR"]
ROLE_ID = os.environ["BAO_ROLE_ID"]
SECRET_ID = os.environ["BAO_SECRET_ID"]
MOUNT = os.getenv("BAO_KV_MOUNT", "secret")
PATH = os.getenv("BAO_SECRET_PATH", "myapp/config")

app = FastAPI(title="OpenBao demo app")
client = hvac.Client(url=BAO_ADDR)


def login() -> None:
    client.auth.approle.login(role_id=ROLE_ID, secret_id=SECRET_ID)


def read_secret() -> dict:
    if not client.token:
        login()
    try:
        resp = client.secrets.kv.v2.read_secret_version(path=PATH, mount_point=MOUNT)
    except hvac.exceptions.Forbidden:
        login()  # token expired -> re-login once
        resp = client.secrets.kv.v2.read_secret_version(path=PATH, mount_point=MOUNT)
    return resp["data"]["data"]


@app.get("/health")
def health():
    return {"status": "ok", "bao_sealed": client.sys.is_sealed()}


@app.get("/secret")
def secret():
    try:
        data = read_secret()
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"OpenBao error: {e}")
    # Real apps should never return secret values; masked here for demo only
    return {k: (v[:3] + "***") for k, v in data.items()}
