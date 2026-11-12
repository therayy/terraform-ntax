terraform {
  required_version = ">= 1.6.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
}

# HCP Terraform supplies short-lived Vault credentials through OIDC.
# Do not add a Vault token or Vault address to this block.
provider "vault" {}

resource "vault_mount" "blueprint_kv" {
  path        = "blueprint-app-kv"
  type        = "kv"
  description = "Workshop 3 blueprint baseline"

  options = {
    version = "2"
  }
}

output "blueprint_mount_path" {
  description = "The Vault KV mount managed by this workspace."
  value       = vault_mount.blueprint_kv.path
}
