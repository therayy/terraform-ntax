terraform {
  required_version = ">= 1.5.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
}

provider "vault" {}

variable "team_name" {
  description = "Team name used for the Vault mount"
  type        = string
  default     = "pilot-team"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.team_name))
    error_message = "The team name must contain only lowercase letters, numbers, and hyphens."
  }
}

resource "vault_mount" "team_kv" {
  path        = "${var.team_name}-kv"
  type        = "kv"
  description = "KV version 2 secrets engine managed by HCP Terraform"

  options = {
    version = "2"
  }

  lifecycle {
    prevent_destroy = true
  }
}

output "team_kv_path" {
  description = "Path of the team KV secrets engine"
  value       = vault_mount.team_kv.path
}