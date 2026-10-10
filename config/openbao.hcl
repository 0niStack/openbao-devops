ui = true

storage "raft" {
  path    = "/openbao/data"
  node_id = "node1"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  # Lab only. In production enable TLS here (tls_cert_file / tls_key_file)
  # or terminate TLS at a reverse proxy on a private network.
  tls_disable     = 1
}

api_addr     = "http://openbao:8200"
cluster_addr = "http://openbao:8201"

disable_mlock = true
