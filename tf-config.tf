terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
}

provider "vault" {}

data "vault_policy_document" "test" {
  rule {
    path         = "secret/data/example"
    capabilities = ["read"]
    description  = "Training provider test"
  }
}

output "policy" {
  value = data.vault_policy_document.test.hcl
}