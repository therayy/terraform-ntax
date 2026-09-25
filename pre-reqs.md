# Workshop Prerequisites

<!-- markdownlint-disable MD013 -->

[Back to the workshop landing page](./README.md)

Complete this file before delivering the Nutanix Terraform and Vault training.

You need only one container runtime:

- Option A: Podmana
- Option B: Docker

Do not run both at the same time. Both may try to use port `8200`.

## Current trainer status

Verified on 2026-09-03:

| Requirement | Status | Evidence |
| --- | --- | --- |
| Terraform CLI | Complete | Terraform 1.15.2 |
| Git | Complete | Git 2.50.1 |
| Vault CLI | Complete | Vault CLI 2.0.4 |
| Podman | Complete | Successfully started Vault 1.21.4 |
| Local Vault | Complete | Initialized, unsealed, and using in-memory storage |
| Docker | Not required | Podman is the selected runtime |
| Complete every lab twice | Pending | Must be finished before delivery |
| Save screenshots | Pending | Must be finished before delivery |
| Vault specialist review | Pending | Required for namespaces and OIDC |

The successful Vault startup proved that the local Podman environment works.
The generated unseal key and development root token are not stored here.

## 1. Install the basic tools

These examples are for macOS with Homebrew.

### Terraform

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform version
```

Required result: Terraform 1.5.0 or later.

Your verified version is Terraform 1.15.2. It meets the requirement. You do not
need to upgrade just because Terraform shows a newer version warning.

### Git

```bash
git --version
```

If Git is missing:

```bash
brew install git
```

### Vault CLI

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/vault
vault version
```

Do not start Vault as a Homebrew background service. The training uses a
disposable Vault container.

Do not run:

```bash
brew services start hashicorp/tap/vault
```

If you already started it:

```bash
brew services stop hashicorp/tap/vault
```

## 2. Choose one container option

## Option A: Podman

Use this option if you want Podman.

### Install Podman

```bash
brew install podman
podman --version
```

Podman uses a small Linux virtual machine on macOS.

### Create the Podman machine

Check first:

```bash
podman machine list
```

If no machine exists:

```bash
podman machine init
podman machine start
```

If a machine exists but is stopped:

```bash
podman machine start
```

Confirm Podman is working:

```bash
podman info
```

### Pull the Vault image with Podman

Do this before the live session:

```bash
podman pull docker.io/hashicorp/vault:1.21.4
```

The `docker.io` part is the image registry name. The runtime is still Podman.

### Start the training Vault server with Podman

```bash
podman run --rm -d \
  --cap-add=IPC_LOCK \
  --name vault-training \
  -e VAULT_DEV_ROOT_TOKEN_ID=training-root \
  -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
  -p 8200:8200 \
  docker.io/hashicorp/vault:1.21.4
```

Confirm the container:

```bash
podman ps
podman logs vault-training
```

### Stop the Podman lab

```bash
podman stop vault-training
unset VAULT_ADDR
unset VAULT_TOKEN
```

Because the command uses `--rm`, Podman removes the container after it stops.

## Option B: Docker

Use this option only if you prefer Docker Desktop.

### Install Docker Desktop

```bash
brew install --cask docker-desktop
open -a Docker
```

Wait for Docker Desktop to finish starting.

Confirm Docker is working:

```bash
docker version
docker info
```

Both commands must show Docker Server information. Seeing only the Client is not
enough.

### Pull the Vault image with Docker

Do this before the live session:

```bash
docker pull docker.io/hashicorp/vault:1.21.4
```

### Start the training Vault server with Docker

```bash
docker run --rm -d \
  --cap-add=IPC_LOCK \
  --name vault-training \
  -e VAULT_DEV_ROOT_TOKEN_ID=training-root \
  -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
  -p 8200:8200 \
  docker.io/hashicorp/vault:1.21.4
```

Confirm the container:

```bash
docker ps
docker logs vault-training
```

### Stop the Docker lab

```bash
docker stop vault-training
unset VAULT_ADDR
unset VAULT_TOKEN
```

Because the command uses `--rm`, Docker removes the container after it stops.

## 3. Connect the Vault CLI

This part is the same for Podman and Docker.

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=training-root
vault status
```

Expected result:

```text
Initialized     true
Sealed          false
Version         1.21.4
Storage Type    inmem
HA Enabled      false
```

This means the local Vault lab works.

Important:

- `training-root` is only for the disposable local lab.
- Do not use this token in HCP Terraform.
- Do not use a customer production token.
- Do not commit the token to Git.
- Do not save the unseal key in the training guide.

## 4. Check for a port conflict

Vault uses port `8200`.

Before starting the lab, run:

```bash
lsof -nP -iTCP:8200 -sTCP:LISTEN
```

If another Vault server or container is already using the port, stop the
disposable training process before starting another one.

For Podman:

```bash
podman ps
```

For Docker:

```bash
docker ps
```

Do not stop an unknown container. Confirm who owns it first.

## 5. Confirm Terraform can reach Vault

Create a temporary test directory:

```bash
TRAINING_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vault-provider-test.XXXXXX")
cd "$TRAINING_TEST_DIR"
```

Create a small Terraform configuration:

```hcl
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
```

Run:

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan
```

Required result:

- The Vault provider downloads.
- Terraform validation succeeds.
- Terraform creates a plan without a provider error.

This test validates the provider installation. The data source creates policy
text locally and may not prove API connectivity by itself. The `vault status`
test confirms the local Vault endpoint.

## 6. Prepare clean lab folders

Use a new directory for every rehearsal:

```bash
TRAINING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nutanix-training.XXXXXX")
cd "$TRAINING_DIR"
pwd
```

Do not reuse old Terraform state for a new rehearsal.

Do not run destructive cleanup commands against an existing customer or Git
directory.

## 7. Complete the labs twice

| Lab | First run | Second run |
| --- | --- | --- |
| Workshop 1 module lab | Pending | Pending |
| Add a second JSON team | Pending | Pending |
| Input validation test | Pending | Pending |
| Workshop 2 CLI import | Pending | Pending |
| Workshop 2 import block explanation | Pending | Pending |
| Moved block plan | Pending | Pending |
| Workshop 3 HCP workflow | Pending | Pending |
| Drift walkthrough | Pending | Pending |

A command working is not enough. You must be able to explain what happened.

## 8. Save screenshots

Create folders:

```bash
mkdir -p training-evidence/workshop-1
mkdir -p training-evidence/workshop-2
mkdir -p training-evidence/workshop-3
```

Save these screenshots:

### Workshop 1

- `terraform validate` success
- Terraform plan
- Terraform apply
- Terraform state list
- Vault secrets list
- Input validation failure

### Workshop 2

- Vault mount before import
- Successful import
- Terraform state show
- First plan after import
- Moved block plan with no deletion

### Workshop 3

- GitHub pull request
- Jenkins checks
- HCP Terraform speculative plan
- Policy and run-task results
- Approval screen
- Apply result
- Health assessment or drift result

If the HCP Terraform environment is not ready, use prepared screenshots and a
walkthrough. Do not fake a live customer connection.

## 9. Confirm customer access

Get these answers before a customer-connected lab:

- [ ] Which development team or namespace is the pilot?
- [ ] Is it a new resource or an import?
- [ ] Which Vault resources are included?
- [ ] What is the HCP Terraform organization?
- [ ] What is the HCP Terraform project?
- [ ] What is the development workspace name?
- [ ] What is the GitHub repository and working directory?
- [ ] Does Jenkins have Terraform and the selected scanner?
- [ ] Can the HCP Terraform Agent reach development Vault?
- [ ] Who is the Vault specialist?
- [ ] Who owns the module?
- [ ] Who approves development applies?
- [ ] Are OIDC roles and policies ready?
- [ ] Is auto-apply disabled?
- [ ] Are production credentials excluded?

## 10. Get Vault specialist review

Ask the Vault specialist to review:

- Enterprise namespace creation
- Parent and child namespace paths
- Vault provider permissions
- Namespaced import requirements
- OIDC issuer and audience
- Bound claims
- Plan and apply roles
- Vault policies
- Token lifetime
- CA certificate trust
- EGP and RGP interaction

Do not guess about these items during the customer session.

## 11. Final safety check

Before every lab, check:

```bash
printf 'Vault address: %s\n' "$VAULT_ADDR"
printf 'Vault namespace: %s\n' "$VAULT_NAMESPACE"
vault token lookup
```

For a local lab, the Vault address must be:

```text
http://127.0.0.1:8200
```

For an HCP Terraform demonstration, confirm:

- The workspace name clearly says development, sandbox, or training.
- Auto-apply is disabled.
- The workspace uses the development Vault address.
- Production variable sets are not attached.
- The role has development-only permissions.
- A second person confirms the environment before apply.

If the environment is unclear, stop. Do not run Terraform.

## 12. Prepare the optional Enterprise extension

The core labs require Terraform 1.5 or later and can use Vault Community.

Running the full 20-minute Enterprise reference extension requires:

- [ ] Terraform 1.11 or later
- [ ] Vault provider 5.0 or later
- [ ] Vault Enterprise Standard license for namespaces
- [ ] Vault Enterprise ADP license for Transform
- [ ] Git access to `hashicorp-education/learn-vault-codify`
- [ ] A disposable Vault Enterprise development server
- [ ] `VAULT_LICENSE` available in the shell but not printed or recorded
- [ ] `VAULT_ADDR`, `VAULT_CACERT`, and `VAULT_TOKEN` configured locally

If these requirements are not ready, deliver the section as a code walkthrough.
Do not spend workshop time debugging Enterprise licensing or connectivity.

Never use a production root token or copy the tutorial's demonstration password
pattern into customer code.

## Ready-to-train checklist

- [x] Terraform installed
- [x] Git installed
- [x] Vault CLI installed
- [x] Podman local Vault test completed
- [ ] Selected runtime confirmed for the session
- [ ] Every lab completed twice
- [ ] Screenshots saved
- [ ] Clean lab directory prepared
- [ ] Definitions rehearsed
- [ ] Vault specialist review completed
- [ ] Customer development access confirmed
- [ ] Production access excluded
