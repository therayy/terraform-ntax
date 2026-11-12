# Workshop 3: GitHub, Jenkins, HCP Terraform, Security, and Drift

<!-- markdownlint-disable MD013 MD024 MD025 -->

[Back to the workshop landing page](./README.md)

**Live delivery:** Use this file as the command-line presenter script and
technical reference. Do not use older web-interface steps during this workshop.

## Workshop 3 timeline

| Time | Block | Topics |
| --- | --- | --- |
| 0:00-0:55 | Delivery and execution | GitHub, Jenkins, HCP Terraform workspaces, plans, approvals, Agents, and OIDC |
| 0:55-1:05 | Break | 10-minute break |
| 1:05-2:00 | Guardrails and operating model | Scanning, policy enforcement, drift, private registry, RBAC, governance, and Infragraph |

## Workshop 3 goal

### Notes!

> Today we will follow one change from GitHub to Vault.
>
> We will see where Jenkins, HCP Terraform, the Agent, OIDC credentials,
> policies, approvals, state, and drift detection fit.
>
> We will also discuss how a central platform team can provide governance
> without owning every other team's Terraform code.

## Command-line-only delivery requirements

### Notes!

> This workshop is delivered from a terminal. We do not use the GitHub,
> Jenkins, HCP Terraform, Vault, or HCP web interfaces.
>
> The customer must provide the existing GitHub App or VCS connection, Agent
> pool, HCP Terraform organization, Vault OIDC trust configuration, policies,
> and run-task integration before the workshop. We configure and inspect them
> through Terraform providers and APIs.

flowchart TD
    A["Change Terraform code"] --> B["Run local CLI checks"]
    B --> C{"Checks pass?"}

    C -->|No| D["Fix the code"]
    D --> B

    C -->|Yes| E["Push branch with Git"]
    E --> F["Create pull request with GitHub CLI"]
    F --> G["Jenkins validation and security scans"]
    G --> H["HCP Terraform speculative plan"]

    H --> I{"Plan and checks pass?"}
    I -->|No| D
    I -->|Yes| J["Review and merge pull request"]

    J --> K["HCP Terraform final plan"]
    K --> L["Policy checks and run tasks"]
    L --> M{"Apply approved?"}

    M -->|No| N["Stop and correct the change"]
    N --> D

    M -->|Yes| O["Apply through HCP Terraform API"]
    O --> P["Verify Vault with Vault CLI"]
    P --> Q["Run drift assessment"]
    Q --> R{"Drift detected?"}

    R -->|No| S["Deployment complete"]
    R -->|Yes| T["Create recovery pull request"]
    T --> B****
Required commands:

```bash
terraform version
vault version
git --version
gh --version
curl --version
jq --version
trivy --version
```

Set the non-secret identifiers:

```bash
export TFE_ADDRESS="https://app.terraform.io"
export TFE_API="${TFE_ADDRESS%/}/api/v2"
export TFE_HOSTNAME="app.terraform.io"
export TFE_ORGANIZATION="nutanix"
export TFE_WORKSPACE="vault-team-pilot-dev"
export GH_REPO="NUTANIX_ORG/vault-platform"
export JENKINS_URL="https://jenkins.example.com"
export JENKINS_JOB="vault-platform"
export JENKINS_USER="trainer@example.com"
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_CACERT="/path/to/vault-ca.pem"
export VAULT_NAMESPACE="nutanix"
```

Read tokens without echoing them and keep them out of Git:

```bash
read -r -s -p "HCP Terraform token: " TFE_TOKEN
printf '\n'
export TFE_TOKEN
export TF_TOKEN_app_terraform_io="$TFE_TOKEN"

read -r -s -p "GitHub token: " GH_TOKEN
printf '\n'
export GH_TOKEN

read -r -s -p "Vault demonstration token: " VAULT_TOKEN
printf '\n'
export VAULT_TOKEN
```

Validate access from the terminal:

```bash
gh auth status

curl --fail --silent --show-error \
  --header "Authorization: Bearer $TFE_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  "$TFE_API/account/details" | jq '{username: .data.attributes.username}'

vault status
```

### Safety note

> Do not paste tokens into commands, Terraform files, shell history, logs, or
> Git. Use short-lived tokens where possible. The HCP Terraform run itself uses
> Vault OIDC dynamic credentials instead of `VAULT_TOKEN`.

## Part 1: Definition

### GitHub

### Notes!

> GitHub stores the Terraform code and JSON configuration. A pull request gives
> the team a place to review the code before merging it.

### Jenkins

### Notes!

> Jenkins runs automated checks. It can check formatting, validate Terraform,
> run tests, and run a security scanner such as Trivy, Checkov, or Cycode.
>
> Jenkins checks the code. HCP Terraform still creates the authoritative plan
> and performs the approved apply.

### HCP Terraform

### Notes!

> HCP Terraform runs Terraform, stores state, connects to GitHub, shows plans,
> applies approved changes, enforces policies, and keeps run history.

### Speculative plan

### Notes!

> A speculative plan is a preview for a pull request. It helps reviewers see
> the expected infrastructure change before the code is merged.
>
> A speculative plan cannot be applied.

### HCP Terraform Agent

### Notes!

> The Agent runs Terraform inside the private network. It allows HCP Terraform
> to reach a private Vault API without making Vault public.
>
> The Agent is not the Vault credential.

### OIDC dynamic credentials

### Notes!

> OIDC lets an HCP Terraform run authenticate to Vault with short-lived
> credentials.
>
> This is safer than storing a permanent Vault token in Git or in a normal
> workspace variable.

### Policies, run tasks, and Vault EGP

### Notes!

> These controls work at different layers.
>
> A static scanner reads the Terraform code. A run task calls an external
> service during an HCP Terraform run. A Terraform policy checks the plan and
> run information. Vault EGP or RGP checks requests at the Vault API.
>
> These controls support each other. They are not replacements for each other.

### Drift detection

### Notes!

> Drift happens when the real Vault configuration changes outside the approved
> Terraform workflow.
>
> HCP Terraform health assessments can detect supported configuration drift.
> They do not automatically fix the drift.

## Part 2: Trainer hands-on walkthrough

## Step 1: Show the repository layout

### In terminal

```text
vault-platform/
|-- modules/
|   `-- team-config/
|-- live/
|   |-- dev/
|   |   |-- main.tf
|   |   `-- teams.json
|   `-- prod/
|       |-- main.tf
|       `-- teams.json
`-- Jenkinsfile
```

### Notes!

> The `modules` folder contains reusable code.
>
> The development folder contains development configuration. The production
> folder contains production configuration.
>
> Both environments can use the same approved module version. They still have
> separate inputs, workspaces, state, access, and approvals.
>
> A team can exist only in development, only in production, or in both.

## Step 2: Show the Jenkins checks

### In terminal

```groovy
pipeline {
  agent any

  stages {
    stage('Terraform format') {
      steps {
        sh 'terraform fmt -check -recursive'
      }
    }

    stage('Terraform validate') {
      steps {
        sh 'terraform -chdir=live/dev init -backend=false'
        sh 'terraform -chdir=live/dev validate'
      }
    }

    stage('Terraform security scan') {
      steps {
        sh 'trivy config --exit-code 1 --severity HIGH,CRITICAL .'
      }
    }
  }
}
```

### Notes!

> The first stage checks Terraform formatting.
>
> The second stage initializes Terraform without using the remote backend and
> validates the development configuration.
>
> The third stage scans the Terraform code with Trivy. Nutanix can replace this
> command with Checkov or Cycode after choosing the standard scanner.
>
> Harbor mainly stores and scans container images. Harbor using Trivy does not
> automatically mean the Terraform pull request is scanned. The IaC scanner
> must be added to the Jenkins pipeline.

### In terminal

Show the Checkov alternative:

```bash
checkov -d . --framework terraform --compact
```

## Step 3: Create the development workspace from the terminal

### In terminal

Use a separate bootstrap configuration with the `tfe` provider. The GitHub App
installation, Agent pool, team, policies, and run task must already exist.

```hcl
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.83.0"
    }
  }
}

provider "tfe" {
  hostname     = var.hostname
  organization = var.organization
}

variable "hostname" {
  type    = string
  default = "app.terraform.io"
}

variable "organization" {
  type = string
}

variable "github_owner" {
  type = string
}

variable "repository" {
  type = string
}

variable "agent_pool_name" {
  type = string
}

variable "development_team_name" {
  type = string
}

variable "terraform_version" {
  type = string
}

variable "vault_address" {
  type = string
}

variable "vault_namespace" {
  type = string
}

variable "vault_run_role" {
  type = string
}

variable "run_task_id" {
  type    = string
  default = null
}

variable "policy_ids" {
  type    = set(string)
  default = []
}

variable "enable_health_assessments" {
  type    = bool
  default = false
}

data "tfe_github_app_installation" "github" {
  name = var.github_owner
}

data "tfe_agent_pool" "approved" {
  name         = var.agent_pool_name
  organization = var.organization
}

data "tfe_team" "development" {
  name         = var.development_team_name
  organization = var.organization
}

resource "tfe_project" "vault_development" {
  name         = "Vault Development"
  organization = var.organization
}

resource "tfe_workspace" "pilot" {
  name                       = "vault-team-pilot-dev"
  organization               = var.organization
  project_id                 = tfe_project.vault_development.id
  working_directory          = "live/dev"
  terraform_version          = var.terraform_version
  auto_apply                 = false
  allow_destroy_plan         = false
  assessments_enabled        = var.enable_health_assessments
  file_triggers_enabled      = true
  trigger_patterns           = ["live/dev/**", "modules/**"]

  vcs_repo {
    identifier                 = "${var.github_owner}/${var.repository}"
    branch                     = "main"
    github_app_installation_id = data.tfe_github_app_installation.github.id
  }
}

resource "tfe_workspace_settings" "pilot" {
  workspace_id   = tfe_workspace.pilot.id
  execution_mode = "agent"
  agent_pool_id  = data.tfe_agent_pool.approved.id
}

resource "tfe_team_access" "development" {
  workspace_id = tfe_workspace.pilot.id
  team_id      = data.tfe_team.development.id
  access       = "write"
}

locals {
  vault_environment = {
    TFC_VAULT_PROVIDER_AUTH = "true"
    TFC_VAULT_ADDR          = var.vault_address
    TFC_VAULT_RUN_ROLE      = var.vault_run_role
    TFC_VAULT_NAMESPACE     = var.vault_namespace
  }
}

resource "tfe_variable" "vault_dynamic_credentials" {
  for_each = local.vault_environment

  workspace_id = tfe_workspace.pilot.id
  category     = "env"
  key          = each.key
  value        = each.value
  sensitive    = false
}

resource "tfe_workspace_run_task" "security" {
  count = var.run_task_id == null ? 0 : 1

  workspace_id      = tfe_workspace.pilot.id
  task_id           = var.run_task_id
  enforcement_level = "advisory"
  stages            = ["post_plan"]
}

resource "tfe_policy_set" "vault_guardrails" {
  count = length(var.policy_ids) == 0 ? 0 : 1

  name          = "vault-pilot-guardrails"
  organization  = var.organization
  kind          = "sentinel"
  policy_ids    = var.policy_ids
  workspace_ids = [tfe_workspace.pilot.id]
}

output "workspace_id" {
  value = tfe_workspace.pilot.id
}
```

Supply the environment-specific values and apply the bootstrap configuration:

```bash
export TF_VAR_hostname="$TFE_HOSTNAME"
export TF_VAR_organization="$TFE_ORGANIZATION"
export TF_VAR_github_owner="NUTANIX_ORG"
export TF_VAR_repository="vault-platform"
export TF_VAR_agent_pool_name="APPROVED_AGENT_POOL"
export TF_VAR_development_team_name="Vault Development Team"
export TF_VAR_terraform_version="$(terraform version -json | jq -r .terraform_version)"
export TF_VAR_vault_address="https://vault.example.com:8200"
export TF_VAR_vault_namespace="nutanix"
export TF_VAR_vault_run_role="vault-team-pilot"

terraform -chdir=bootstrap/hcp init
terraform -chdir=bootstrap/hcp fmt -check
terraform -chdir=bootstrap/hcp validate
terraform -chdir=bootstrap/hcp plan -out=bootstrap.tfplan
terraform -chdir=bootstrap/hcp apply bootstrap.tfplan
```

Confirm the settings through the API:

```bash
WORKSPACE_ID="$(terraform -chdir=bootstrap/hcp output -raw workspace_id)"
export WORKSPACE_ID

curl --fail --silent --show-error \
  --header "Authorization: Bearer $TFE_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  "$TFE_API/workspaces/$WORKSPACE_ID" |
  jq '.data | {
    id,
    name: .attributes.name,
    auto_apply: .attributes["auto-apply"],
    assessments: .attributes["assessments-enabled"],
    working_directory: .attributes["working-directory"],
    execution_mode: .attributes["execution-mode"]
  }'
```

### Notes!

> This workspace manages only the development pilot.
>
> The GitHub connection allows pull-request plans and runs after merge.
>
> Auto-apply is disabled because a person must review and approve the final
> plan.
>
> The Agent runs Terraform from the private network and reaches the private
> Vault API.
>
> Health assessments remain disabled until this workspace completes its first
> successful apply. We enable them later by setting
> `TF_VAR_enable_health_assessments=true` and applying the bootstrap
> configuration again.

## Step 4: Show Vault dynamic credential settings

### In terminal

```text
TFC_VAULT_PROVIDER_AUTH=true
TFC_VAULT_ADDR=https://vault.example.com:8200
TFC_VAULT_RUN_ROLE=vault-team-pilot
TFC_VAULT_NAMESPACE=nutanix
```

For separate plan and apply roles:

```text
TFC_VAULT_PLAN_ROLE=vault-team-pilot-plan
TFC_VAULT_APPLY_ROLE=vault-team-pilot-apply
```

The provider configuration stays simple:

```hcl
provider "vault" {}
```

Confirm that the workspace variables exist without printing their values:

```bash
curl --fail --silent --show-error \
  --header "Authorization: Bearer $TFE_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  "$TFE_API/workspaces/$WORKSPACE_ID/vars" |
  jq '[.data[] |
    select(.attributes.key | startswith("TFC_VAULT_")) |
    {
      key: .attributes.key,
      category: .attributes.category,
      sensitive: .attributes.sensitive
    }
  ]'
```

### Notes!

> HCP Terraform uses these settings to request short-lived Vault credentials.
>
> A Vault specialist must configure the trusted OIDC issuer, audience, bound
> claims, Vault roles, Vault policies, token lifetime, namespace, and CA trust.
>
> Plan and apply can use different roles when different permissions are needed.
>
> We do not store a permanent Vault token in Git or in a normal workspace
> variable.

## Step 5: Follow one GitHub change

### Notes!

> I will now follow one development change through the complete workflow.

### In terminal

Create a branch and change one non-sensitive value. Adjust the `jq` selector to
match the actual `teams.json` schema.

```bash
BRANCH="workshop3-cli-change"
git switch -c "$BRANCH"

jq '(.teams[] | select(.name == "pilot") | .description) =
    "Updated through the reviewed CLI workflow"' \
  live/dev/teams.json > /tmp/teams.json
mv /tmp/teams.json live/dev/teams.json

terraform fmt -check -recursive
terraform -chdir=live/dev init -backend=false
terraform -chdir=live/dev validate
trivy config --exit-code 1 --severity HIGH,CRITICAL .

git diff --check
git diff -- live/dev/teams.json
git add live/dev/teams.json
git commit -m "Update pilot team configuration"
git push --set-upstream origin "$BRANCH"
```

Create and inspect the pull request with GitHub CLI:

```bash
PR_URL="$(gh pr create \
  --repo "$GH_REPO" \
  --base main \
  --head "$BRANCH" \
  --title "Update pilot team configuration" \
  --body "Workshop 3 command-line workflow demonstration")"

gh pr view "$PR_URL" --json number,title,state,headRefName,baseRefName
gh pr diff "$PR_URL"
gh pr checks "$PR_URL" --watch --fail-fast
```

If Jenkins does not report its result as a GitHub check, query Jenkins directly:

```bash
read -r -s -p "Jenkins API token: " JENKINS_API_TOKEN
printf '\n'
export JENKINS_API_TOKEN

curl --fail --silent --show-error \
  --user "$JENKINS_USER:$JENKINS_API_TOKEN" \
  "$JENKINS_URL/job/$JENKINS_JOB/lastBuild/api/json" |
  jq '{number, result, building, url}'
```

Get the workspace ID if it was not exported by the bootstrap step:

```bash
WORKSPACE_ID="${WORKSPACE_ID:-$(
  curl --fail --silent --show-error \
    --header "Authorization: Bearer $TFE_TOKEN" \
    --header "Content-Type: application/vnd.api+json" \
    "$TFE_API/organizations/$TFE_ORGANIZATION/workspaces/$TFE_WORKSPACE" |
    jq -r '.data.id'
)}"
export WORKSPACE_ID
```

Retrieve the latest speculative pull-request run. The runs endpoint excludes
plan-only runs unless they are explicitly requested.

```bash
SPECULATIVE_RUN_ID="$(
  curl --fail --silent --show-error \
    --header "Authorization: Bearer $TFE_TOKEN" \
    --header "Content-Type: application/vnd.api+json" \
    "$TFE_API/workspaces/$WORKSPACE_ID/runs?filter%5Boperation%5D=plan_only&page%5Bsize%5D=20" |
    jq -r '.data[0].id'
)"

curl --fail --silent --show-error \
  --header "Authorization: Bearer $TFE_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  "$TFE_API/runs/$SPECULATIVE_RUN_ID" |
  jq '.data | {
    id,
    status: .attributes.status,
    operation: .attributes.operation,
    message: .attributes.message,
    created_at: .attributes["created-at"]
  }'
```

Wait for the speculative plan to finish:

```bash
while :; do
  RUN_STATUS="$(
    curl --fail --silent --show-error \
      --header "Authorization: Bearer $TFE_TOKEN" \
      --header "Content-Type: application/vnd.api+json" \
      "$TFE_API/runs/$SPECULATIVE_RUN_ID" |
      jq -r '.data.attributes.status'
  )"

  printf 'Speculative run status: %s\n' "$RUN_STATUS"

  case "$RUN_STATUS" in
    planned_and_finished|policy_soft_failed|errored|canceled|discarded) break ;;
  esac

  sleep 10
done
```

Print the speculative plan log in the terminal:

```bash
PLAN_ID="$(
  curl --fail --silent --show-error \
    --header "Authorization: Bearer $TFE_TOKEN" \
    --header "Content-Type: application/vnd.api+json" \
    "$TFE_API/runs/$SPECULATIVE_RUN_ID" |
    jq -r '.data.relationships.plan.data.id'
)"

PLAN_LOG_URL="$(
  curl --fail --silent --show-error \
    --header "Authorization: Bearer $TFE_TOKEN" \
    --header "Content-Type: application/vnd.api+json" \
    "$TFE_API/plans/$PLAN_ID" |
    jq -r '.data.attributes["log-read-url"]'
)"

curl --fail --silent --show-error --location "$PLAN_LOG_URL"
unset PLAN_LOG_URL
```

Merge only after the GitHub checks and speculative plan pass:

```bash
gh pr merge "$PR_URL" --squash --delete-branch
```

Wait for HCP Terraform to create the post-merge run:

```bash
while :; do
  RUN_ID="$(
    curl --fail --silent --show-error \
      --header "Authorization: Bearer $TFE_TOKEN" \
      --header "Content-Type: application/vnd.api+json" \
      "$TFE_API/workspaces/$WORKSPACE_ID" |
      jq -r '.data.relationships["current-run"].data.id // empty'
  )"

  if [ -n "$RUN_ID" ] && [ "$RUN_ID" != "$SPECULATIVE_RUN_ID" ]; then
    break
  fi

  sleep 10
done

export RUN_ID
printf 'Post-merge run: %s\n' "$RUN_ID"
```

Inspect the run, Terraform policy evaluations, and run-task stages:

```bash
curl --fail --silent --show-error \
  --header "Authorization: Bearer $TFE_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  "$TFE_API/runs/$RUN_ID?include=plan,tf_policy_evaluations" |
  jq '{
    run: {
      id: .data.id,
      status: .data.attributes.status,
      operation: .data.attributes.operation,
      actions: .data.attributes.actions
    },
    policy_evaluations: [
      .included[]? |
      select(.type == "policy-evaluations") |
      {id, status: .attributes.status}
    ]
  }'

curl --fail --silent --show-error \
  --header "Authorization: Bearer $TFE_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  "$TFE_API/runs/$RUN_ID/task-stages?include=task-results,policy-evaluations" |
  jq '{
    stages: [.data[] | {id, stage: .attributes.stage, status: .attributes.status}],
    results: [.included[]? | {id, type, status: .attributes.status}]
  }'
```

Print the final plan log using the same plan-log commands, replacing
`SPECULATIVE_RUN_ID` with `RUN_ID`. Verify that the plan contains only the
expected change.

The authorized approver applies the run from the terminal. This requires a
user or team token with apply permission. An organization token cannot apply a
run.

```bash
curl --fail --silent --show-error \
  --request POST \
  --header "Authorization: Bearer $TFE_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --data '{"comment":"Approved after CLI plan and policy review"}' \
  "$TFE_API/runs/$RUN_ID/actions/apply"
```

Wait for the apply to finish and print its log:

```bash
while :; do
  RUN_STATUS="$(
    curl --fail --silent --show-error \
      --header "Authorization: Bearer $TFE_TOKEN" \
      --header "Content-Type: application/vnd.api+json" \
      "$TFE_API/runs/$RUN_ID" |
      jq -r '.data.attributes.status'
  )"

  printf 'Run status: %s\n' "$RUN_STATUS"

  case "$RUN_STATUS" in
    applied|planned_and_finished|errored|canceled|discarded) break ;;
  esac

  sleep 10
done

APPLY_ID="$(
  curl --fail --silent --show-error \
    --header "Authorization: Bearer $TFE_TOKEN" \
    --header "Content-Type: application/vnd.api+json" \
    "$TFE_API/runs/$RUN_ID" |
    jq -r '.data.relationships.apply.data.id'
)"

APPLY_LOG_URL="$(
  curl --fail --silent --show-error \
    --header "Authorization: Bearer $TFE_TOKEN" \
    --header "Content-Type: application/vnd.api+json" \
    "$TFE_API/applies/$APPLY_ID" |
    jq -r '.data.attributes["log-read-url"]'
)"

curl --fail --silent --show-error --location "$APPLY_LOG_URL"
unset APPLY_LOG_URL
```

Inspect state metadata and run history without downloading the raw state file:

```bash
curl --fail --silent --show-error \
  --header "Authorization: Bearer $TFE_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  "$TFE_API/workspaces/$WORKSPACE_ID/current-state-version" |
  jq '.data | {
    id,
    serial: .attributes.serial,
    created_at: .attributes["created-at"],
    resources_processed: .attributes["resources-processed"]
  }'

curl --fail --silent --show-error \
  --header "Authorization: Bearer $TFE_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  "$TFE_API/workspaces/$WORKSPACE_ID/runs?page%5Bsize%5D=10" |
  jq '[.data[] | {
    id,
    status: .attributes.status,
    operation: .attributes.operation,
    created_at: .attributes["created-at"]
  }]'
```

After the first successful apply, enable scheduled health assessments through
the bootstrap configuration:

```bash
export TF_VAR_enable_health_assessments=true
terraform -chdir=bootstrap/hcp plan -out=enable-health.tfplan
terraform -chdir=bootstrap/hcp apply enable-health.tfplan
```

### Notes!

> The pull request gives us code review. Jenkins gives us automated code checks.
> The speculative plan gives us an infrastructure preview before merge.
>
> After merge, HCP Terraform creates the real workspace plan. Policies and run
> tasks check the run. A person approves the apply.
>
> The Agent reaches Vault, and OIDC gives the run short-lived Vault access.
> HCP Terraform then updates the state and saves the run history.

## Step 6: Show the security layers

### In terminal

| Control | What it checks |
| --- | --- |
| `terraform fmt` and `validate` | Formatting and Terraform validity |
| Trivy, Checkov, or Cycode | Static security scan of Terraform code |
| HCP Terraform run task | External service result during a run |
| Sentinel, OPA, or Terraform policy | Terraform plan and run information |
| Vault EGP or RGP | Vault API requests |
| Health assessment | Drift after deployment |

### Notes!

> Formatting and validation find basic code problems.
>
> Trivy, Checkov, or Cycode scans the Terraform code for security risks.
>
> A run task sends run information to an external service.
>
> Sentinel, OPA, or another supported HCP Terraform policy checks the plan and
> its metadata.
>
> Vault EGP or RGP protects Vault at request time, even when the request comes
> from another approved client.
>
> A health assessment checks for drift after deployment.

## Step 7: Show drift detection

### Notes!

> I will make one controlled manual change in development Vault. This represents
> a change made outside the approved Terraform workflow.

### In terminal

Set the demonstration mount path to a disposable development mount. Never run
this against production:

```bash
export DRIFT_DEMO_MOUNT="team-kv"
```

Record the current description and introduce one controlled out-of-band change:

```bash
ORIGINAL_DESCRIPTION="$(
  vault secrets list \
    -namespace="$VAULT_NAMESPACE" \
    -format=json |
    jq -r --arg mount "$DRIFT_DEMO_MOUNT/" '.[$mount].description'
)"

printf 'Original description: %s\n' "$ORIGINAL_DESCRIPTION"

vault secrets tune \
  -namespace="$VAULT_NAMESPACE" \
  -description="OUT-OF-BAND DRIFT DEMONSTRATION" \
  "$DRIFT_DEMO_MOUNT/"
```

HCP Terraform currently exposes on-demand health-assessment triggering only in
its web interface. Because this workshop is command-line only, create a
non-auto-applied refresh-only run through the API for immediate drift detection:

```bash
jq -n --arg workspace_id "$WORKSPACE_ID" '
{
  data: {
    type: "runs",
    attributes: {
      message: "Workshop 3 CLI drift check",
      operation: "refresh_only",
      "auto-apply": false
    },
    relationships: {
      workspace: {
        data: {
          type: "workspaces",
          id: $workspace_id
        }
      }
    }
  }
}' > /tmp/refresh-only-run.json

DRIFT_RUN_ID="$(
  curl --fail --silent --show-error \
    --request POST \
    --header "Authorization: Bearer $TFE_TOKEN" \
    --header "Content-Type: application/vnd.api+json" \
    --data @/tmp/refresh-only-run.json \
    "$TFE_API/runs" |
    jq -r '.data.id'
)"

rm -f /tmp/refresh-only-run.json
printf 'Refresh-only run: %s\n' "$DRIFT_RUN_ID"
```

Wait for the run to finish planning, then print its plan log using the plan-log
commands from Step 5 with `DRIFT_RUN_ID`. Do not apply this refresh-only run.
After reviewing the result, discard it:

```bash
curl --fail --silent --show-error \
  --request POST \
  --header "Authorization: Bearer $TFE_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  "$TFE_API/runs/$DRIFT_RUN_ID/actions/discard"
```

Scheduled HCP Terraform health assessments continue independently. Retrieve
the latest scheduled result through the API when one exists:

```bash
ASSESSMENT_ID="$(
  curl --fail --silent --show-error \
    --header "Authorization: Bearer $TFE_TOKEN" \
    --header "Content-Type: application/vnd.api+json" \
    "$TFE_API/workspaces/$WORKSPACE_ID" |
    jq -r '.data.relationships["current-assessment-result"].data.id // empty'
)"

if [ -n "$ASSESSMENT_ID" ]; then
  curl --fail --silent --show-error \
    --header "Authorization: Bearer $TFE_TOKEN" \
    --header "Content-Type: application/vnd.api+json" \
    "$TFE_API/assessment-results/$ASSESSMENT_ID" |
    jq '.data | {
      id,
      drifted: .attributes.drifted,
      succeeded: .attributes.succeeded,
      created_at: .attributes["created-at"]
    }'
else
  printf '%s\n' "No scheduled health-assessment result exists yet."
fi
```

Reject the out-of-band change by queuing a normal reviewed run from the latest
workspace configuration. This plan should restore the description defined in
Git:

```bash
jq -n --arg workspace_id "$WORKSPACE_ID" '
{
  data: {
    type: "runs",
    attributes: {
      message: "Restore Vault configuration after controlled drift test",
      operation: "plan_and_apply",
      "auto-apply": false
    },
    relationships: {
      workspace: {
        data: {
          type: "workspaces",
          id: $workspace_id
        }
      }
    }
  }
}' > /tmp/recovery-run.json

RECOVERY_RUN_ID="$(
  curl --fail --silent --show-error \
    --request POST \
    --header "Authorization: Bearer $TFE_TOKEN" \
    --header "Content-Type: application/vnd.api+json" \
    --data @/tmp/recovery-run.json \
    "$TFE_API/runs" |
    jq -r '.data.id'
)"

rm -f /tmp/recovery-run.json
printf 'Recovery run: %s\n' "$RECOVERY_RUN_ID"
```

Review its plan log and policy results with the Step 5 commands. Apply it only
after confirming that it restores the expected description and makes no other
changes.

### Notes!

> HCP Terraform detected that the real Vault configuration no longer matches
> the Terraform configuration.
>
> We now have two valid choices.
>
> First, we can reject the manual change and apply Terraform to restore the
> value from code.
>
> Second, we can accept the manual change by updating Git, reviewing the plan,
> and applying the reviewed configuration.
>
> We do not hide unexplained drift by changing state manually.
>
> For this live CLI demonstration, the refresh-only run provides immediate
> evidence. The scheduled health assessment provides the ongoing HCP Terraform
> control after the workshop.

## Step 8: Show the shared governance model

### In terminal

| Central platform team owns | Consumer team owns |
| --- | --- |
| Approved modules | Environment inputs |
| Module versions and retirement | Pull requests |
| Workspace standards | Workspace runs within its access |
| Policy sets and exceptions | Deployment results |
| Identity and access standards | Failed plan and drift remediation |
| Agent and credential patterns | Daily use of the approved pattern |
| Audit and governance visibility | Its infrastructure responsibility |

### Notes!

> The central team should not own every other team's Terraform code and every
> apply.
>
> The central team provides approved modules, workspace standards, policies,
> access rules, Agent patterns, and secure credential patterns.
>
> Consumer teams keep ownership of their configuration, pull requests,
> deployments, and problems.
>
> We start new policies in advisory mode. We check failures and false positives.
> We create an exception process. After the policy is stable, we can make it
> mandatory.

## Step 9: Separate HCP Terraform access from Vault access

### Notes!

> We have two permission layers.
>
> HCP Terraform permissions control who can view, plan, apply, approve, and
> manage projects and workspaces.
>
> Vault permissions control what Terraform can create or change inside Vault.
> This includes Vault namespaces, ACL policies, and EGP or RGP policies.
>
> We need both layers. HCP Terraform access does not replace Vault access.

## Step 10: Show the private module registry path

### In terminal

Validate and version the module repository:

```bash
terraform fmt -check -recursive
terraform -chdir=examples/basic init -backend=false
terraform -chdir=examples/basic validate
trivy config --exit-code 1 --severity HIGH,CRITICAL .

git status --short
git tag -a v1.0.0 -m "Release team-config module v1.0.0"
git push origin v1.0.0
```

Publish the existing GitHub repository to the HCP Terraform private registry
through the `tfe` provider:

```hcl
data "tfe_github_app_installation" "github" {
  name = var.github_owner
}

resource "tfe_registry_module" "team_config" {
  organization = var.organization

  vcs_repo {
    identifier                 = "${var.github_owner}/terraform-vault-team-config"
    display_identifier         = "${var.github_owner}/terraform-vault-team-config"
    github_app_installation_id = data.tfe_github_app_installation.github.id
  }
}
```

Apply the registry configuration from the terminal:

```bash
terraform -chdir=bootstrap/hcp fmt -check
terraform -chdir=bootstrap/hcp validate
terraform -chdir=bootstrap/hcp plan -out=publish-module.tfplan
terraform -chdir=bootstrap/hcp apply publish-module.tfplan
```

Pin the published module version in consuming code:

```hcl
module "team_config" {
  source  = "app.terraform.io/nutanix/team-config/vault"
  version = "1.0.0"

  # Approved inputs
}
```

### Notes!

> After the module works in the pilot, we can publish it to the HCP Terraform
> private registry.
>
> The public Terraform Registry can be used by anyone. The private registry
> gives Nutanix control over which internal modules are published and who can
> use them.
>
> Private does not automatically mean secure. Every module still needs review,
> testing, scanning, versioning, and maintenance.
>
> The module should have its own Git repository, documentation, examples, tests,
> and security scans. A pull request reviews every module change.
>
> We tag a version such as `v1.0.0` and publish it. Consumer teams pin an
> approved module version. We publish a new version when the module changes.
>
> We do not silently change a shared module and force every team to receive the
> change without review.

## Step 11: Introduce Infragraph

### Notes!

> Infragraph gives visibility into supported infrastructure resources and the
> relationships between them.
>
> Infragraph does not replace Terraform state, Terraform drift detection, or a
> security scanner. It does not automatically fix infrastructure.
>
> Infragraph activation, connections, and graph queries currently depend on
> the HCP web experience. There is no documented supported CLI workflow for
> this demonstration.
>
> Because this workshop is command-line only, Infragraph remains a short
> conceptual overview. We do not perform a live Infragraph demonstration or
> use undocumented private endpoints.

## Part 3: Attendee hands-on practice

## Practice 1: Put the workflow in order

### Notes!

> Put these steps in the correct order: GitHub pull request, Jenkins checks,
> speculative plan, peer review and merge, HCP Terraform workspace plan,
> approval, Agent execution with OIDC, and state update with health assessment.

### Answer

1. GitHub pull request
2. Jenkins checks
3. HCP Terraform speculative plan
4. Peer review and merge
5. HCP Terraform workspace plan
6. Authorized approval
7. Agent execution with OIDC
8. State update and health assessment

## Practice 2: Choose the correct control

### Notes!

> Match each requirement with its main control.

| Requirement | Correct control |
| --- | --- |
| Check Terraform syntax | `terraform validate` |
| Scan Terraform code | Trivy, Checkov, or Cycode |
| Require an approved module | Sentinel, OPA, or HCP Terraform policy |
| Restrict a Vault API operation | Vault EGP or RGP |
| Reach private Vault | HCP Terraform Agent |
| Authenticate without a permanent token | OIDC dynamic credentials |
| Find a manual change | Health assessment |

## Practice 3: Choose Terraform or an operational job

### Notes!

> Decide whether each activity belongs in Terraform desired state or in a
> separate operational job.

| Activity | Correct answer |
| --- | --- |
| Ensure a namespace exists | Terraform |
| Define an ACL policy | Terraform |
| Configure a secrets engine | Terraform |
| Delete inactive identities on a schedule | Operational job |
| Run Vault upgrade tests | Operational job |
| Perform a one-time data migration | Operational job |

### Notes!

> Terraform is good for describing what should exist.
>
> It should not become a general scheduler for cleanup, runtime decisions,
> upgrade tests, emergency actions, or one-time migrations.

## Part 4: Quiz

### Notes!

> We will finish with five short questions. Choose the best answer.

1. What starts a speculative plan?
   - A. A change in a connected pull request
   - B. Vault token expiration
   - C. State deletion
   - D. An Infragraph query
2. What does the Agent provide?
   - A. A permanent Vault token
   - B. Private execution and network access
   - C. GitHub approval
   - D. Vault policy code
3. What gives the run short-lived Vault authentication?
   - A. OIDC dynamic credentials
   - B. Jenkins logs
   - C. Infragraph
   - D. A moved block
4. What does a health assessment do?
   - A. Detects drift and check failures
   - B. Fixes every manual change automatically
   - C. Creates a Vault cluster
   - D. Publishes a module
5. Who owns a consumer team's deployment?
   - A. The consumer team within central guardrails
   - B. The central team in every case
   - C. The scanner vendor
   - D. The Vault root token owner

### Answer key

1. A
2. B
3. A
4. A
5. A

## Workshop 3 closing notes

### Notes!

> We now have a complete target pattern.
>
> GitHub stores and reviews the code. Jenkins checks the code. HCP Terraform
> creates the plan, enforces policies, controls approval, runs Terraform, stores
> state, and detects drift.
>
> The Agent provides private network access. OIDC provides short-lived Vault
> authentication.
>
> The next step is not a large production rollout. The next step is one
> development pilot. We will prove the pattern, record what we learn, and then
> decide how to expand it.

---

## After the Training

## Development pilot

### Notes!

> The first pilot will use one new or existing development team namespace.
>
> We will list the exact Vault resources in scope. We will build and review the
> module. We will create the development JSON configuration. We will add
> Jenkins checks and connect the development HCP Terraform workspace to GitHub.
>
> We will configure Agent connectivity and short-lived Vault authentication.
> If the resources already exist, we will import one resource type at a time.
>
> We will review every plan before apply. After the first successful apply, we
> will create one controlled drift event and confirm that the team can detect
> and respond to it.

## Pilot checklist

- [ ] Select one development team or namespace.
- [ ] List the Vault resources in scope.
- [ ] Confirm the final Terraform resource addresses.
- [ ] Build the reusable module.
- [ ] Create the non-sensitive JSON input.
- [ ] Add Jenkins validation and scanning.
- [ ] Connect the development workspace to GitHub.
- [ ] Disable auto-apply.
- [ ] Configure the Agent pool.
- [ ] Configure Vault OIDC credentials.
- [ ] Add the required policies and run tasks.
- [ ] Import existing resources one type at a time, if needed.
- [ ] Review every first plan.
- [ ] Apply only after approval.
- [ ] Create and detect one controlled drift event.
- [ ] Record lessons before expanding.

## Pilot success

### Notes!

> The pilot succeeds when one engineer can add or manage the pilot team through
> reviewed configuration, the module creates consistent resources, and the
> workspace manages only the intended development resources.
>
> Jenkins checks must pass. HCP Terraform policies and approvals must work. The
> Agent must reach Vault without making Vault public. HCP Terraform must use
> short-lived Vault credentials. State must stay protected in HCP Terraform.
>
> The team must also detect one controlled drift event and know how to respond.

## Safety notes for you

Do not read this section to the customer. Use it to protect the demonstration.

- Do not say every Terraform resource supports import.
- Do not say import guarantees a clean plan.
- Do not say a data source imports a resource.
- Do not say a module knows the existing infrastructure.
- Do not call the Agent a Vault credential.
- Do not say run tasks promote development to production.
- Do not say Infragraph fixes drift.
- Do not say Harbor automatically scans Terraform code.
- Do not put every namespace in one state file.
- Do not use Terraform for every Vault operational task.
- Do not use a production Vault token or production workspace.

If you do not know a Vault security answer, read this:

> I need to confirm that with the Vault specialist. I do not want to guess about
> a security-sensitive configuration.

## Official references

- [Terraform overview](https://developer.hashicorp.com/terraform/intro)
- [HCP Terraform](https://developer.hashicorp.com/terraform/cloud-docs)
- [HCP Terraform API](https://developer.hashicorp.com/terraform/cloud-docs/api-docs)
- [HCP Terraform runs API](https://developer.hashicorp.com/terraform/cloud-docs/api-docs/run)
- [HCP Terraform plans API](https://developer.hashicorp.com/terraform/cloud-docs/api-docs/plans)
- [HCP Terraform applies API](https://developer.hashicorp.com/terraform/cloud-docs/api-docs/applies)
- [HCP Terraform assessment results API](https://developer.hashicorp.com/terraform/cloud-docs/api-docs/assessment-results)
- [HCP Terraform task stages API](https://developer.hashicorp.com/terraform/cloud-docs/api-docs/tasks/task-stages-and-results)
- [HCP Terraform and Terraform Enterprise provider](https://registry.terraform.io/providers/hashicorp/tfe/latest/docs)
- [Terraform import](https://developer.hashicorp.com/terraform/language/import)
- [Generated import configuration](https://developer.hashicorp.com/terraform/language/import/generating-configuration)
- [Vault Terraform provider tutorial](https://developer.hashicorp.com/vault/tutorials/get-started/learn-terraform)
- [Manage Vault with Terraform](https://developer.hashicorp.com/vault/docs/configuration/programmatic-management)
- [HCP Terraform Vault dynamic credentials](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/vault-configuration)
- [HCP Terraform health assessments](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/health)
- [HCP Terraform run tasks](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/settings/run-tasks)
- [HCP Terraform private registry](https://developer.hashicorp.com/terraform/cloud-docs/registry)
- [HCP Terraform project best practices](https://developer.hashicorp.com/terraform/cloud-docs/projects/best-practices)
- [Infragraph](https://developer.hashicorp.com/hcp/docs/infragraph)
- [GitHub CLI pull requests](https://cli.github.com/manual/gh_pr)
- [Jenkins remote access API](https://www.jenkins.io/doc/book/using/remote-access-api/)

## Navigation

- Previous: [Workshop 2: Import, Moved Blocks, Workspaces, and State](./workshop-2.md)
- Landing page: [Nutanix Terraform and Vault Workshop Series](./README.md)
