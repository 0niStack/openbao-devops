# Read-only access to myapp secrets (KV v2 mounted at "secret/")
path "secret/data/myapp/*" {
  capabilities = ["read"]
}
path "secret/metadata/myapp/*" {
  capabilities = ["list", "read"]
}
