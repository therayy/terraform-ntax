# Least-privilege permissions for this disposable lab mount.
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/revoke-self" {
  capabilities = ["update"]
}
path "sys/mounts" {
  capabilities = ["read"]
}
path "sys/mounts/blueprint-app-kv" {
  capabilities = ["create", "read", "update", "delete"]
}
path "sys/mounts/blueprint-app-kv/tune" {
  capabilities = ["read", "update"]
}
