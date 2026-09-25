# Workshop 1: Terraform Foundations and Vault Enterprise Codification

<!-- markdownlint-disable MD013 MD024 MD025 -->

[Back to the workshop landing page](./README.md)

**Live delivery:** Use the
[Workshop 1 presenter script](./presenter-script.md#workshop-1-terraform-foundations-and-vault-enterprise-codification).
The detailed sections below are your technical reference.

## Workshop 1 timeline

| Time | Block | Topics |
| --- | --- | --- |
| 0:00-0:55 | Terraform foundations | Providers, resources, data sources, state, plan, apply, modules, and provider versions |
| 0:55-1:05 | Break | 10-minute break |
| 1:05-1:35 | Reusable Vault automation | Vault provider, JSON input, loops, conditions, validation, templates, outputs, plan review, and apply |
| 1:35-1:55 | Enterprise codification extension | Namespaces, policies, auth methods, secrets engines, and ephemeral or write-only values |
| 1:55-2:00 | Recap | Key differences, safety rules, and questions |

## Opening speaker notes

### Read aloud

> Good morning, everyone. Thank you for joining.
>
> We already know that your team uses HCP Terraform, GitHub, and HCP Terraform
> workspaces. We also know that most runs are started from the Terraform CLI
> today.
>
> Your main goal is to make Vault management easier and more consistent. You
> want to use reusable Terraform modules, simple JSON input, GitHub review,
> Jenkins checks, HCP Terraform approvals, secure Vault access, and drift
> detection.
>
> We are not going to import all 60 or more Vault namespaces during this
> training. That would be unsafe and too large. We will use one small
> development example. After the pattern works, you can expand it carefully.
>
> We will have three workshops. Each workshop starts with the basic idea. I will
> then show the process. You will practice it, and we will finish with a short
> quiz.

## The final workflow

### Read aloud

> This is the workflow we are working toward.
>
> A team updates the approved Terraform module or the JSON configuration. They
> create a GitHub pull request. Jenkins checks the code. HCP Terraform creates a
> plan. A person reviews and approves the change. HCP Terraform then uses an
> Agent and short-lived Vault credentials to make the approved change.
>
> Development and production do not need to be identical. A team can exist in
> development, production, or both. The same module can be used, but each
> environment should have its own configuration, workspace, state, and
> approval process.

```mermaid
flowchart TD
    A["Change module or JSON"] --> B["GitHub pull request"]
    B --> C["Jenkins checks"]
    C --> D["HCP Terraform plan"]
    D --> E["Review and approval"]
    E --> F{"Target environment"}
    F -->|Dev| G["Development Vault"]
    F -->|Prod| H["Production Vault"]
    G --> I["State and drift checks"]
    H --> I
```

## Workshop 1 goal

### Read aloud

> Today we will review the basic Terraform workflow. Then we will build a small
> reusable module that creates a Vault KV secrets engine and a Vault policy.
>
> We will use a JSON file to add teams. The JSON file will contain only simple,
> non-sensitive settings. It will never contain passwords, Vault tokens,
> private keys, or secret values.
>
> We will finish with a 20-minute Enterprise extension showing how the Vault
> provider codifies namespaces, policies, auth methods, secrets engines, and
> safer credential flows.

## Part 1: Definition

### Configuration

### Read aloud

> Terraform configuration is the code that describes what we want.
>
> For example, our configuration may say that the payments team needs a KV
> secrets engine and a read policy.

### Provider

### Read aloud

> A provider is the plugin Terraform uses to communicate with another system.
>
> In this training, Terraform uses the Vault provider to call the Vault API.

### Provider documentation and versions

### Read aloud

> The provider documentation shows the resources and data sources that the
> provider supports.
>
> We must check the documentation for the provider version we use. If a new
> service or feature is not supported by that version, Terraform cannot manage
> it through that provider yet.

### Resource

### Read aloud

> A resource is something Terraform creates or manages.
>
> A Vault namespace, policy, secrets engine, or auth method can be a Terraform
> resource when the Vault provider supports it.

### Data source

### Read aloud

> A data source reads information that already exists.
>
> A data source does not import that object. It also does not make Terraform the
> owner of that object.

### State

### Read aloud

> Terraform state is Terraform's record of the objects it manages.
>
> State connects a Terraform resource address to a real object in Vault. The
> state is not the Terraform code, and it is not a Vault backup.

### Plan and apply

### Read aloud

> Terraform plan shows what Terraform wants to change. Terraform apply makes
> the approved change.
>
> We always read the plan before apply. If the plan shows an unexpected deletion
> or replacement, we stop and fix the problem.

### Module

### Read aloud

> A module is reusable Terraform code.
>
> We can build one standard team module and use it many times. This helps every
> team receive the same basic Vault configuration.
>
> The module does not know the existing infrastructure by itself. Terraform
> uses the provider and state to understand managed objects.

### Provider and module together

### Read aloud

> A provider connects Terraform to a system and its API. A module packages
> reusable Terraform code.
>
> The resources inside a module still use a provider. A module does not replace
> the provider.

### Terraform workflow

### Read aloud

> First, we write the Terraform code. Next, Terraform initializes the working
> directory. Then Terraform creates a plan. We review the plan. If it is correct,
> we apply it. Terraform updates the real system and its state.

```mermaid
flowchart TD
    A["Write code"] --> B["terraform init"]
    B --> C["terraform plan"]
    C --> D{"Plan correct?"}
    D -->|No| A
    D -->|Yes| E["terraform apply"]
    E --> F["Vault and state updated"]
```

## Part 2: Trainer hands-on walkthrough

## Step 1: Start the local Vault server

### Read aloud

> I am using a local Vault development server. This server is only for
> training. It runs in memory, starts unsealed, and loses its data when the
> container stops.
>
> This is not a production Vault design.

### On screen

Start Vault by following the Podman or Docker option in
[pre-reqs.md](./pre-reqs.md).

Then run:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=training-root
vault status
```

### Expected result

```text
Initialized     true
Sealed          false
Storage Type    inmem
```

### Read aloud

> Vault is initialized and unsealed. The storage type is in-memory. That tells
> us this is the disposable training server.

## Step 2: Create the folders

### On screen

```bash
mkdir -p vault-team-training/modules/team-config/templates
cd vault-team-training
```

The folder structure will be:

```text
vault-team-training/
|-- main.tf
|-- outputs.tf
|-- teams.json
|-- versions.tf
`-- modules/
    `-- team-config/
        |-- main.tf
        |-- outputs.tf
        |-- variables.tf
        `-- templates/
            `-- reader-policy.hcl.tftpl
```

### Read aloud

> The files at the top are the root module. The folder under `modules` is the
> reusable child module.
>
> The root module reads the team input. The child module contains the standard
> Vault resources.

## Step 3: Create `versions.tf`

### On screen

```hcl
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
```

### Read aloud

> This file requires Terraform 1.5 or later. It also tells Terraform to download
> the HashiCorp Vault provider.
>
> The provider block is empty because the local lab reads the Vault address and
> token from the terminal environment variables.
>
> Later, HCP Terraform will use short-lived credentials instead of a permanent
> token.

## Step 4: Create `teams.json`

### On screen

```json
{
  "teams": {
    "payments": {
      "enable_kv": true
    }
  }
}
```

### Read aloud

> This JSON file contains one team named payments.
>
> The value `enable_kv` is true, so Terraform will create a KV secrets engine
> for this team.
>
> The file contains no secrets. It only contains configuration choices.

## Step 5: Create root `main.tf`

### On screen

```hcl
locals {
  team_configuration = jsondecode(file("${path.module}/teams.json"))
  teams              = local.team_configuration.teams
}

module "team_config" {
  source   = "./modules/team-config"
  for_each = local.teams

  team_name = each.key
  enable_kv = try(each.value.enable_kv, true)
}
```

### Read aloud

> Terraform reads `teams.json` and converts it into data Terraform can use.
>
> `for_each` creates one copy of the team module for every team in the JSON
> file.
>
> `each.key` is the team name. In this example, the team name is payments.
>
> If `enable_kv` is missing, Terraform uses true as the default.

## Step 6: Create root `outputs.tf`

### On screen

```hcl
output "team_mounts" {
  description = "KV mount created for each team."
  value = {
    for team_name, team_module in module.team_config :
    team_name => team_module.mount_path
  }
}
```

### Read aloud

> This output shows the KV mount created for each team. Outputs give us useful
> information after the plan or apply.

## Step 7: Create module `variables.tf`

### On screen

Create `modules/team-config/variables.tf`:

```hcl
variable "team_name" {
  description = "Short lowercase team name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.team_name))
    error_message = "Use 3-31 lowercase letters, numbers, or hyphens."
  }
}

variable "enable_kv" {
  description = "Create the team's KV v2 secrets engine."
  type        = bool
  default     = true
}
```

### Read aloud

> These are the inputs accepted by the module.
>
> The team name must use lowercase letters, numbers, or hyphens. Terraform will
> reject an invalid team name before apply.
>
> `enable_kv` is a true or false choice. Its default value is true.

## Step 8: Create the policy template

### On screen

Create `modules/team-config/templates/reader-policy.hcl.tftpl`:

```hcl
path "${mount_path}/data/*" {
  capabilities = ["read", "list"]
}

path "${mount_path}/metadata/*" {
  capabilities = ["read", "list"]
}
```

### Read aloud

> This template creates the same policy structure for every team.
>
> Terraform replaces `mount_path` with the correct team KV path.

## Step 9: Create module `main.tf`

### On screen

Create `modules/team-config/main.tf`:

```hcl
terraform {
  required_providers {
    vault = {
      source = "hashicorp/vault"
    }
  }
}

locals {
  mount_path = "${var.team_name}-kv"
}

resource "vault_mount" "team_kv" {
  count = var.enable_kv ? 1 : 0

  path        = local.mount_path
  type        = "kv"
  description = "KV v2 engine for ${var.team_name}"

  options = {
    version = "2"
  }
}

resource "vault_policy" "team_reader" {
  count = var.enable_kv ? 1 : 0

  name = "${var.team_name}-reader"
  policy = templatefile(
    "${path.module}/templates/reader-policy.hcl.tftpl",
    { mount_path = local.mount_path }
  )
}
```

### Read aloud

> The local value builds a mount path from the team name. The payments team gets
> a path named `payments-kv`.
>
> The `count` condition creates the resources when `enable_kv` is true. When it
> is false, the count becomes zero.
>
> The first resource creates the KV secrets engine. The second resource creates
> the reader policy from the template.

## Step 10: Create module `outputs.tf`

### On screen

Create `modules/team-config/outputs.tf`:

```hcl
output "mount_path" {
  description = "Created KV mount path, or null when disabled."
  value       = var.enable_kv ? vault_mount.team_kv[0].path : null
}
```

### Read aloud

> The child module returns the mount path to the root module. If KV is disabled,
> the output is null.

## Step 11: Run Terraform

### On screen

```bash
terraform init
```

### Read aloud

> Terraform initialized the folder and downloaded the Vault provider.

### On screen

```bash
terraform fmt -recursive
terraform validate
```

### Read aloud

> Formatting makes the code consistent. Validation checks that the Terraform
> configuration is valid.

### On screen

```bash
terraform plan -out=tfplan
```

### Read aloud

> The plan should show one KV mount and one policy being created for the
> payments team.
>
> We read the plan before applying it. We are looking for unexpected changes,
> especially deletion or replacement.

### On screen

```bash
terraform apply tfplan
terraform state list
vault secrets list
vault policy read payments-reader
```

### Expected Terraform state

```text
module.team_config["payments"].vault_mount.team_kv[0]
module.team_config["payments"].vault_policy.team_reader[0]
```

### Read aloud

> Terraform created the Vault resources and recorded them in state.
>
> The state address shows the payments module, the Vault resource type, the
> resource name, and the count index.

## Enterprise extension: Codify Vault Enterprise management with Terraform

**Duration:** 20 minutes

**Delivery:** Guided code and architecture walkthrough. Run it live only when
the Enterprise prerequisites are ready.

### Why this section belongs in Workshop 1

### Read aloud

> The first lab taught the core pattern with a KV mount and policy.
>
> This Enterprise extension applies the same Terraform workflow to a broader
> Vault configuration. Terraform still uses the Vault provider. The difference
> is that we now manage Enterprise features such as namespaces and Transform.
>
> We are configuring an existing Vault Enterprise server. We are not deploying
> the Vault cluster or the machines underneath it.

### Personas

| Persona | Role |
| --- | --- |
| `admin` | Organization-level administrator who configures Vault |
| `student` | Demonstration user allowed to access approved Vault paths |

### Challenge and solution

### Read aloud

> Manual configuration becomes difficult when an organization manages
> development, testing, staging, and production Vault environments.
>
> Terraform lets the platform team codify supported Vault configuration. The
> code can be reviewed, tested, versioned, repeated, and promoted through an
> approved workflow.
>
> This reduces manual effort and human error, but it does not remove the need
> for Vault permissions, plan review, testing, and environment separation.

### Enterprise prerequisites

The full reference lab requires:

- Terraform CLI 1.11 or later for the ephemeral and write-only examples.
- Vault CLI.
- Vault provider 5.0 or later.
- Vault Enterprise Standard for namespaces.
- Vault Enterprise Advanced Data Protection for the Transform secrets engine.
- Git and a disposable Vault Enterprise development environment.
- A valid development license supplied through `VAULT_LICENSE`.

If only Vault Community is available, keep the existing KV and policy lab. Do
not attempt to create Enterprise namespaces or use Transform.

### What the reference configuration creates

| Area | Example configuration |
| --- | --- |
| Namespaces | `finance`, `engineering`, `education`, `education/training`, `education/training/vault_cloud`, and `education/training/boundary` |
| ACL policies | `admins` in the appropriate namespaces and `fpe-client` at root |
| Human demo auth | Userpass with a demonstration `student` user |
| Machine auth | AppRole and `test-role` in `education/training` |
| Secrets engines | KV v2 in `finance`, database at root, and Transform at root |
| Transform objects | Numeric alphabet, credit-card template, FPE transformation, and `payments` role |
| Credential flow | Write-only secret arguments and an ephemeral Vault read for the database connection |

The nested namespace is named `boundary`. Do not describe it as another
`engineering` namespace.

### Reference repository and file layout

### On screen

```bash
git clone https://github.com/hashicorp-education/learn-vault-codify
cd learn-vault-codify/enterprise
```

```text
enterprise/
|-- auth.tf
|-- main.tf
|-- policies.tf
|-- provider.tf
|-- secrets.tf
`-- policies/
    |-- admin-policy.hcl
    `-- fpe-client-policy.hcl
```

### Read aloud

> The files are separated by responsibility.
>
> `provider.tf` defines the Vault provider requirement. `main.tf` creates
> namespaces and core mounts. `policies.tf` creates ACL policies.
> `auth.tf` enables userpass and AppRole. `secrets.tf` configures KV and
> Transform.

### Provider and authentication

### On screen

```hcl
terraform {
  required_version = ">= 1.11.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
  }
}

provider "vault" {}
```

### Read aloud

> The provider reads the target Vault address and authentication from the
> runtime environment.
>
> The local reference lab uses `VAULT_ADDR`, `VAULT_CACERT`, and
> `VAULT_TOKEN`. Those values must not be committed to Git.
>
> In the target HCP Terraform workflow, use the Agent for network connectivity
> and short-lived OIDC credentials for Vault authentication.

### Namespace hierarchy

### On screen

```hcl
resource "vault_namespace" "education" {
  path = "education"
}

resource "vault_namespace" "training" {
  namespace = vault_namespace.education.path
  path      = "training"
}

resource "vault_namespace" "boundary" {
  namespace = vault_namespace.training.path_fq
  path      = "boundary"
}
```

### Read aloud

> The `namespace` argument identifies the parent. Terraform references the
> parent's path instead of repeating a hard-coded hierarchy.
>
> The same concept applies when a policy, auth method, or secrets engine must
> be created inside a specific namespace.

### Policies, authentication, and secrets engines

### Read aloud

> The reference code creates the same `admins` policy in several namespaces.
> That demonstrates the behavior, but our customer design should package the
> repeated pattern in a module or drive it from approved input data.
>
> Userpass and the password `changeme` are tutorial-only examples. Do not use
> that pattern for a real user or store a real password in Terraform code.
>
> AppRole demonstrates machine authentication inside
> `education/training`. The finance namespace receives a KV v2 secrets
> engine. Transform demonstrates format-preserving encryption, but it requires
> the Enterprise ADP license.

### Ephemeral and write-only values

### Read aloud

> The reference tutorial also demonstrates two protections for sensitive
> values.
>
> An ephemeral resource exists only during the Terraform operation and does not
> persist its returned value in the plan or state.
>
> A write-only argument, normally ending in `_wo`, passes a value to a
> provider without saving that value in the plan or state. Its matching
> `_wo_version` value tells Terraform when the secret must be updated.
>
> These features reduce state exposure. They do not make hard-coded passwords
> safe. The source value must still come from an approved secure runtime path.

### On screen

```hcl
ephemeral "vault_kv_secret_v2" "db_secret" {
  mount    = vault_mount.kvv2.path
  mount_id = vault_mount.kvv2.id
  name     = vault_kv_secret_v2.db_root.name
}

resource "vault_database_secret_backend_connection" "postgres" {
  backend       = vault_mount.db.path
  name          = "learn-postgres"
  allowed_roles = ["*"]

  postgresql {
    connection_url      = "postgresql://{{username}}:{{password}}@localhost:5432/postgres?sslmode=disable"
    username            = "postgres"
    password_wo         = tostring(ephemeral.vault_kv_secret_v2.db_secret.data.password)
    password_wo_version = 1
  }
}
```

### Demonstration flow

### On screen

```bash
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
terraform apply
```

### Read aloud

> The plan should show the intended Enterprise configuration. The official
> reference currently creates 28 objects on the first apply.
>
> Before approval, check the target address, namespace paths, policy contents,
> auth methods, secrets engine paths, and every create, update, replace, or
> delete action.

### Verification focus

### On screen

```bash
vault namespace list
vault namespace list -namespace=education
vault namespace list -namespace=education/training
vault policy list -namespace=finance
vault secrets list -namespace=finance
vault auth list -namespace=education/training
vault list -namespace=education/training auth/approle/role
```

### Read aloud

> Verification proves that Terraform configured the intended namespace, not
> only that the Terraform command returned successfully.
>
> We also inspect state carefully to confirm that a write-only password was not
> persisted. We never print the secret value during that check.

### How this maps to the three workshops

| Workshop | Enterprise tutorial connection |
| --- | --- |
| Workshop 1 | Create and understand namespaces, policies, auth methods, secrets engines, provider behavior, and state-safe values |
| Workshop 2 | Import equivalent resources that already exist, review the first plan, and refactor repeated configuration safely |
| Workshop 3 | Put the code behind GitHub review, Jenkins checks, HCP Terraform plans, policies, approvals, Agents, OIDC, and drift detection |

### Official references

- [Codify Vault Enterprise management with Terraform](https://developer.hashicorp.com/vault/tutorials/operations/codify-mgmt-enterprise)
- [Reference repository](https://github.com/hashicorp-education/learn-vault-codify)
- [Manage sensitive data in Terraform](https://developer.hashicorp.com/terraform/language/manage-sensitive-data)

## Part 3: Attendee hands-on practice

## Practice 1: Add a second team

### Read aloud

> Now you will add a second team named analytics. Do not apply immediately.
> First, run a plan and tell us what Terraform wants to add.

### On screen

Change `teams.json` to:

```json
{
  "teams": {
    "analytics": {
      "enable_kv": true
    },
    "payments": {
      "enable_kv": true
    }
  }
}
```

Run:

```bash
terraform validate
terraform plan
```

### Correct result

- Terraform keeps the payments resources.
- Terraform adds an analytics KV mount.
- Terraform adds an analytics reader policy.

## Practice 2: Test the condition

### Read aloud

> Change `analytics.enable_kv` from true to false. Run a plan. Do not apply.
> Tell us why Terraform wants to remove the analytics resources.

### On screen

```text
"enable_kv": false
```

Run:

```bash
terraform plan
```

### Read aloud

> The condition changed the resource count from one to zero. Terraform now
> believes the analytics KV mount and policy should not exist.
>
> This is why a small JSON change still needs a full plan review.

Restore the value to true.

## Practice 3: Test validation

### Read aloud

> Change the analytics team name to `Analytics Team` and run a plan. The name is
> invalid because it contains uppercase letters and a space.

### On screen

```bash
terraform plan
```

### Correct result

Terraform rejects the input and shows this message:

```text
Use 3-31 lowercase letters, numbers, or hyphens.
```

Restore the team name to `analytics`.

## Part 4: Quiz

### Read aloud

> We will finish with five short questions. Choose the best answer.

1. What does Terraform state contain?
   - A. Vault audit logs
   - B. Mappings between Terraform addresses and real objects
   - C. GitHub passwords
   - D. Only the latest plan
2. What does a data source do?
   - A. Reads information
   - B. Imports a resource
   - C. Approves an apply
   - D. Stores secrets
3. What belongs in `teams.json`?
   - A. Root tokens
   - B. Private keys
   - C. Non-sensitive team settings
   - D. Passwords
4. Why do we use a module?
   - A. To package reusable code
   - B. To replace state
   - C. To skip plan
   - D. To store credentials
5. What must happen before apply?
   - A. Review the plan
   - B. Delete state
   - C. Disable validation
   - D. Add a secret to Git

### Answer key

1. B
2. A
3. C
4. A
5. A

## Workshop 1 closing notes

### Read aloud

> Today we reviewed the Terraform lifecycle and built a reusable Vault module.
> We used JSON input, `for_each`, a condition, input validation, and a policy
> template.
>
> In the next workshop, we will connect an existing Vault resource to Terraform
> state and move it into a better code structure.

### On screen after the workshop

Remove the disposable Workshop 1 resources:

```bash
terraform destroy
```

Stop the Vault container by following the cleanup command for your selected
runtime in [pre-reqs.md](./pre-reqs.md).

## Continue

Next: [Workshop 2: Import, Moved Blocks, Workspaces, and State](./workshop-2.md)
