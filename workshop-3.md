# Workshop 3 Replica: GitHub + Jenkins + HCP Terraform + Vault + Drift

## Goal

Repeat Workshop 3 without overwriting the original lab. We will build a new Vault KV mount, validate code with Jenkins, use HCP Terraform to apply changes with short-lived Vault credentials, then find and repair a manual change (drift).

**How to read this guide:** `UI` means click in an app. `CLI` means run the command in VS Code Terminal. Each **Why** line is a short explanation you can say during the workshop.

**Important:** This demo assumes the same existing `terraform-ntax` GitHub repository, HCP Terraform organization `nutx`, and running local development Vault at `http://127.0.0.1:8200`. It creates *new* resources inside them. Do not create a new HCP organization or a second Vault server just for the duplicate.

## The new names

| Part | New name |
| --- | --- |
| Folder | `workshop-3-replica` |
| First Git branch | `workshop3-blueprint-setup` |
| Demo change branch | `workshop3-blueprint-change` |
| Jenkins Multibranch job | `vault-blueprint-ci` |
| Jenkinsfile | `workshop-3-replica/jenkins/Jenkinsfile` |
| HCP organization (existing) | `nutx` |
| HCP project | `Vault Blueprint Lab` |
| HCP workspace | `vault-blueprint-dev` |
| HCP Agent pool | `vault-blueprint-agents` |
| Agent container | `tfc-blueprint-runner` |
| Vault JWT auth path | `blueprint-jwt` |
| Vault OIDC run role | `tfc-blueprint-demo` |
| Vault ACL policy | `tfc-blueprint-mount` |
| Terraform resource | `vault_mount.blueprint_kv` |
| New Vault KV mount | `blueprint-app-kv` |
| Terraform output | `blueprint_mount_path` |

### Workflow at a glance

```text
VS Code: change files and run checks
     -> GitHub: create pull request
     -> Jenkins: format, validate, Trivy
     -> HCP Terraform: speculative plan
     -> GitHub: approve and merge
     -> HCP Terraform Agent: final plan and approved apply
     -> Vault: verify the new KV mount
     -> HCP Terraform Health: find drift and repair it
```

## Before you begin

You need VS Code, Git, Terraform, Trivy, Vault CLI, Podman, access to the existing repository and HCP organization, a running **disposable** Vault environment, and permission to create Jenkins jobs and Vault policies. Your Jenkins build agent must have Terraform and Trivy installed. You must have a HCP Terraform plan that supports Agents and, for the drift section, health assessments.

**Never copy a Vault token or HCP Agent token into Git, Jenkinsfile, screenshots, or normal HCP Terraform variables.** The HCP run authenticates through OIDC. A temporary admin Vault login is used only to prepare the demo.

---

## Part A: Put a separate lab in Git (steps 1-9)

### Step 1. Open the correct project

**UI:** VS Code -> **File** -> **Open Folder** -> select `terraform-ntax`.

**CLI:**

```bash
pwd
git status
git remote -v
```

**Why:** Confirm you are in the right repository before changing anything.

### Step 2. Start from a clean `main` branch

**UI:** VS Code -> **Source Control** -> look at the current branch name.

**CLI:**

```bash
git switch main
git pull --ff-only origin main
```

**Why:** Starting from `main` keeps the previous pilot branch out of this duplicate. If Git reports uncommitted changes, commit or safely stash them first. Do not force-switch.

### Step 3. Create a new setup branch

**UI:** Click the branch name in VS Code -> **Create new branch** -> `workshop3-blueprint-setup`.

**CLI alternative:**

```bash
git switch -c workshop3-blueprint-setup
```

**Why:** Your first PR will add the new lab files without touching the old workshop.

### Step 4. Add the replica files

**UI:** Unzip this package. Drag the **whole** `workshop-3-replica` folder into the root of `terraform-ntax` in VS Code Explorer.

**CLI:**

```bash
ls workshop-3-replica
ls workshop-3-replica/{jenkins,vault-configuration,vault-oidc}
```

**Why:** Keep the new demo in its own directory.

### Step 5. Review the Terraform code

**UI:** VS Code Explorer -> `workshop-3-replica` -> `vault-configuration` -> `main.tf`.

**CLI:**

```bash
cat workshop-3-replica/vault-configuration/main.tf
```

**Why:** This file manages only the new `blueprint-app-kv` engine. The empty Vault provider block is intentional because HCP Terraform supplies OIDC credentials.

### Step 6. Format the configuration

**UI:** VS Code -> **Terminal** -> **New Terminal**.

**CLI:**

```bash
terraform fmt -recursive workshop-3-replica/vault-configuration
terraform fmt -check -recursive workshop-3-replica/vault-configuration
```

**Why:** Formatting makes Terraform code consistent.

### Step 7. Initialize and validate locally

**CLI:**

```bash
terraform -chdir=workshop-3-replica/vault-configuration init -backend=false -input=false
terraform -chdir=workshop-3-replica/vault-configuration validate
```

**Why:** This checks the configuration, but does not deploy anything or use HCP state.

### Step 8. Run the security scan

**CLI:**

```bash
trivy config --exit-code 1 --severity HIGH,CRITICAL workshop-3-replica/vault-configuration
git diff --check
```

**Why:** Catch high-severity code issues before opening a PR. This scan does not replace plan policies or Vault ACLs.

### Step 9. Push the setup and merge into `main`

**UI:** VS Code -> **Source Control** -> review changes, then stage and commit. GitHub -> repository -> **Compare & pull request** -> base `main` -> review -> **Merge**.

**CLI (if not committed in UI):**

```bash
git add workshop-3-replica
git commit -m "Add separate Workshop 3 blueprint lab"
git push -u origin workshop3-blueprint-setup
```

**Why:** The HCP workspace will follow `main`, so the new folder must first exist on `main`. If you already committed through VS Code, run only `git push -u ...`.

---

## Part B: Prepare Vault OIDC (steps 10-16)

### Step 10. Refresh local `main`

**UI:** VS Code -> click branch name -> select `main`.

**CLI:**

```bash
git switch main
git pull --ff-only origin main
```

**Why:** Your local copy now has the files that GitHub merged.

### Step 11. Confirm local Vault is running

**UI:** Podman Desktop -> **Containers** -> confirm the existing Vault container is running.

**CLI:**

```bash
export VAULT_ADDR="http://127.0.0.1:8200"
vault status
vault login -method=token
```

**Why:** Use your existing development Vault. `vault login` requests a temporary admin token for setup. Do not save that token in the repository.

### Step 12. Check access from a Podman container

**CLI:**

```bash
podman run --rm docker.io/curlimages/curl:latest \
  -sS -o /dev/null -w '%{http_code}\n' \
  http://host.containers.internal:8200/v1/sys/health
```

**Why:** HCP Terraform's Agent runs inside a container. The Agent must be able to reach Vault. A Vault health HTTP status such as `200` confirms reachability; a network/connection error means fix the Podman network first.

### Step 13. Create a new Vault JWT auth path

**UI:** Vault UI -> **Access** -> **Auth Methods** -> **Enable new method** -> **JWT** -> path `blueprint-jwt` (if your Vault UI exposes that option).

**CLI alternative:**

```bash
vault auth enable -path=blueprint-jwt jwt
```

**Why:** A separate JWT mount keeps the new OIDC demo away from `tfc-jwt`. If it already exists, do not enable it again.

### Step 14. Trust HCP Terraform as the token issuer

**CLI:**

```bash
vault write auth/blueprint-jwt/config \
  oidc_discovery_url="https://app.terraform.io" \
  bound_issuer="https://app.terraform.io"
```

**Why:** Vault must verify HCP Terraform's identity token instead of trusting an arbitrary token.

### Step 15. Install the new Vault access policy

**UI:** Vault UI -> **Policies** -> **ACL Policies** -> review the file `vault-oidc/blueprint-mount-policy.hcl`.

**CLI:**

```bash
vault policy write tfc-blueprint-mount \
  workshop-3-replica/vault-oidc/blueprint-mount-policy.hcl
vault policy read tfc-blueprint-mount
```

**Why:** Give the demo identity access to its own mount, not every secret in Vault.

### Step 16. Create the new JWT role

**UI:** VS Code -> open `vault-oidc/blueprint-jwt-role.json` and confirm that the `organization`, `project`, and `workspace` match the names in this guide.

**CLI:**

```bash
vault write auth/blueprint-jwt/role/tfc-blueprint-demo \
  @workshop-3-replica/vault-oidc/blueprint-jwt-role.json
vault read auth/blueprint-jwt/role/tfc-blueprint-demo
```

**Why:** Only the named HCP workspace can request this Vault role. The JWT audience and full workspace identity must match exactly.

---

## Part C: Create HCP Terraform workspace and Agent (steps 17-25)

### Step 17. Select the existing HCP organization

**UI:** Open https://app.terraform.io -> choose organization `nutx`.

**Why:** We reuse the original HCP organization, but not the old project or workspace.

### Step 18. Create a new project

**UI:** **Projects** -> **New project** -> name `Vault Blueprint Lab` -> **Create**.

**Why:** A project groups related workspaces. Every workspace still has separate state.

### Step 19. Create a new Agent pool

**UI:** Organization **Settings** -> **Agents** / **Agent pools** -> **Create agent pool** -> name `vault-blueprint-agents`. Create an Agent token and copy it **one time**.

**Why:** The Agent will execute Terraform close to your private local Vault.

### Step 20. Start the new Agent container

**CLI (run in your Mac terminal):**

```bash
printf 'Paste the new HCP Agent token: '
read -rs TFC_AGENT_TOKEN
printf '\n'
export TFC_AGENT_TOKEN
export TFC_AGENT_NAME="blueprint-lab-agent"

podman run -d --name tfc-blueprint-runner --platform linux/amd64 \
  -e TFC_AGENT_TOKEN -e TFC_AGENT_NAME \
  docker.io/hashicorp/tfc-agent:latest
unset TFC_AGENT_TOKEN
```

**Why:** We start a second Agent with a different container name and pool token. Use an updated Agent version that supports Vault dynamic credentials.

### Step 21. Confirm the Agent is online

**UI:** HCP Terraform -> **Agent pools** -> `vault-blueprint-agents` -> check for an **Online** Agent.

**CLI:**

```bash
podman ps --filter name=tfc-blueprint-runner
podman logs --tail 30 tfc-blueprint-runner
```

**Why:** Do not continue until an Agent has connected successfully.

### Step 22. Create the HCP Terraform workspace

**UI:** **Workspaces** -> **New workspace** -> **Version control workflow** -> choose the GitHub connection -> repository `terraform-ntax` -> project `Vault Blueprint Lab` -> workspace name `vault-blueprint-dev`.

**Why:** Git is the source of truth for this separate workspace.

### Step 23. Configure the workspace settings

**UI:** Workspace -> **Settings** -> **Version Control** / **General**:

- VCS branch: `main`
- Working directory: `workshop-3-replica/vault-configuration`
- Execution mode: **Agent**
- Agent pool: `vault-blueprint-agents`
- Auto apply: **Off**

**Why:** An authorized person must check the plan before deploying. Make sure the workspace is attached to the *new* directory, not the original Workshop 3 directory.

### Step 24. Add the OIDC environment variables

**UI:** Workspace -> **Variables** -> **Add variable** -> select type **Environment variable** for each entry:

| Key | Value |
| --- | --- |
| `TFC_VAULT_PROVIDER_AUTH` | `true` |
| `TFC_VAULT_ADDR` | `http://host.containers.internal:8200` |
| `TFC_VAULT_RUN_ROLE` | `tfc-blueprint-demo` |
| `TFC_VAULT_AUTH_PATH` | `blueprint-jwt` |

**Why:** These settings tell HCP Terraform how to get a temporary Vault login. Do **not** add `VAULT_TOKEN` or `TFC_VAULT_NAMESPACE` when using the root namespace of Vault OSS.

### Step 25. Run the first plan and apply

**UI:** Workspace -> **New run** -> **Plan and apply** -> review planned creation of `vault_mount.blueprint_kv` -> **Confirm & Apply**.

**Why:** This creates the baseline in Vault and the first HCP state. If the workspace automatically started an initial run, open and approve that run instead of starting a duplicate.

---

## Part D: Verify Vault and set up Jenkins (steps 26-29)

### Step 26. Verify the Terraform-created Vault mount

**UI:** Vault UI -> **Secrets Engines** -> look for `blueprint-app-kv`.

**CLI:**

```bash
vault secrets list
vault secrets list -detailed | grep -A 2 'blueprint-app-kv/'
```

**Why:** Confirm HCP Terraform really created the resource, not just a plan.

### Step 27. Create the Jenkins Multibranch job

**UI:** Jenkins -> **New Item** -> enter `vault-blueprint-ci` -> **Multibranch Pipeline** -> **OK** -> **Branch Sources** -> add GitHub/Git repository `terraform-ntax`, credentials, and branch/PR discovery -> **Build Configuration** -> **by Jenkinsfile** -> Script Path `workshop-3-replica/jenkins/Jenkinsfile` -> **Save**.

**Why:** Jenkins will find the pipeline in the new folder. You must have Jenkins Pipeline, Git/GitHub Branch Source support, and a build agent with Terraform and Trivy installed.

### Step 28. Start a Jenkins scan and build

**UI:** Jenkins -> `vault-blueprint-ci` -> **Scan Multibranch Pipeline Now** -> open `main` -> **Build Now** (if no build started automatically).

**Why:** Jenkins runs code checks, but it does not apply Terraform.

### Step 29. Read Jenkins results

**UI:** Jenkins -> job -> build number -> **Stage View** or **Console Output**.

**CLI (same checks locally):**

```bash
terraform fmt -check -recursive workshop-3-replica/vault-configuration
terraform -chdir=workshop-3-replica/vault-configuration validate
trivy config --exit-code 1 --severity HIGH,CRITICAL workshop-3-replica/vault-configuration
```

**Why:** All checks should pass before anyone merges a change.

---

## Part E: Make one change, review it, and deploy (steps 30-35)

### Step 30. Create a new feature branch

**UI:** VS Code -> bottom-left branch name -> **Create new branch** -> `workshop3-blueprint-change`.

**CLI alternative:**

```bash
git switch main
git pull --ff-only origin main
git switch -c workshop3-blueprint-change
```

**Why:** We want a PR to prove the complete review workflow.

### Step 31. Change one safe field

**UI:** VS Code -> `workshop-3-replica/vault-configuration/main.tf` -> replace:

```hcl
description = "Workshop 3 blueprint baseline"
```

with:

```hcl
description = "Workshop 3 blueprint approved change"
```

**Why:** Changing only a description is easy to review and should avoid deleting the mount.

### Step 32. Check, commit, and push the change

**CLI:**

```bash
terraform fmt -check -recursive workshop-3-replica/vault-configuration
terraform -chdir=workshop-3-replica/vault-configuration validate
trivy config --exit-code 1 --severity HIGH,CRITICAL workshop-3-replica/vault-configuration
git diff --check
git diff
git add workshop-3-replica/vault-configuration/main.tf
git commit -m "Update blueprint Vault mount description"
git push -u origin workshop3-blueprint-change
```

**Why:** Check the code before the remote pipeline checks it again.

### Step 33. Open and review the pull request

**UI:** GitHub -> repository -> **Compare & pull request** -> base `main` -> create PR -> check Jenkins result -> open HCP Terraform speculative plan -> request code review.

**Why:** Jenkins confirms code quality. A speculative HCP Terraform plan shows the proposed real-world change, but **cannot apply** it.

### Step 34. Merge and approve the final run

**UI:** GitHub -> **Merge pull request** after approval -> HCP Terraform -> `vault-blueprint-dev` -> open new run triggered from `main` -> review plan and any configured policy/run-task checks -> **Confirm & Apply**.

**Why:** The final run is the real deployment. HCP Terraform manages state and history, not Jenkins.

### Step 35. Confirm the result and enable health checks

**UI:** Vault -> **Secrets Engines** -> `blueprint-app-kv` -> confirm description. HCP Terraform -> workspace -> **States** / **State** and **Runs**. Then **Settings** -> **Health** -> enable **Health assessments** -> **Save settings**.

**CLI:**

```bash
vault secrets list -detailed | grep -A 2 'blueprint-app-kv/'
```

**Why:** We verify the deployed value and turn on drift monitoring. On-demand health assessments require supported HCP Terraform plan and workspace permissions.

---

## Part F: Create drift and restore the desired state (steps 36-39)

### Step 36. Make a controlled change outside Terraform

**UI:** Vault UI -> **Secrets Engines** -> `blueprint-app-kv` -> edit the description to `Manual drift test from Vault UI` (if the Vault UI allows editing the mount).

**CLI alternative:**

```bash
vault secrets tune \
  -description="Manual drift test outside Terraform" \
  blueprint-app-kv/
```

**Why:** This simulates someone changing Vault without a Git pull request. Change only this disposable lab mount.

### Step 37. Detect drift in HCP Terraform

**UI:** HCP Terraform -> `vault-blueprint-dev` -> **Health** -> **Start health assessment** -> **Drift** -> open the changed resource.

**Why:** Drift means real Vault configuration no longer matches Git. Health checks detect it; they do **not** fix it automatically.

### Step 38. Restore the approved value

**UI:** HCP Terraform -> workspace -> **New run** -> **Plan and apply** -> confirm the plan restores the description from Git -> **Confirm & Apply**.

**Why:** We reject the manual change and return to the approved configuration. Do not edit Terraform state to hide drift.

### Step 39. Recheck health and finish

**UI:** HCP Terraform -> **Health** -> **Start health assessment** again -> verify drift is cleared. Open **Runs** and the latest state. Jenkins -> show successful pipeline history.

**CLI:**

```bash
vault secrets list -detailed | grep -A 2 'blueprint-app-kv/'
git status
```

**Why:** The workshop ends with a deployed, tracked, reviewed, and healthy configuration.

---

## If something fails

| Symptom | Quick fix |
| --- | --- |
| `fatal: couldn't find remote ref <branch>` | The remote branch does not exist. Use `git push -u origin <branch>` first. |
| Jenkins cannot find `Jenkinsfile` | Confirm the Script Path is `workshop-3-replica/jenkins/Jenkinsfile` and the file is on the branch being built. |
| `terraform: command not found` in Jenkins | Install Terraform on the Jenkins build agent, not only on your Mac. |
| `trivy: command not found` in Jenkins | Install Trivy on the Jenkins build agent. |
| Agent offline | Check `podman logs tfc-blueprint-runner` and Agent pool token. |
| HCP Terraform cannot reach Vault | Check the Agent's Podman network and `host.containers.internal:8200`. |
| Vault `permission denied` | Check the Vault ACL policy and role bound claims. |
| Vault JWT authentication rejected | Check issuer, audience, project/workspace names, `TFC_VAULT_AUTH_PATH`, and OIDC role. |
| HCP Terraform shows no PR speculative plan | Confirm GitHub App/VCS connection, workspace VCS settings, PR access, and the working directory. |
| HCP does not trigger on changes | Check branch `main`, the VCS trigger paths, and whether the workspace has completed its first run. |
| Health/Drift option unavailable | Confirm the HCP plan, successful first apply, Agent execution, and workspace permissions. |
| A run partially fails | Review the error, actual Vault resources, and HCP state. Fix and re-plan. Never assume a failed apply rolled everything back. |

## Official references

- [HCP Terraform Vault dynamic provider credentials](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/vault-configuration)
- [HCP Terraform Agents](https://developer.hashicorp.com/terraform/cloud-docs/agents/agents)
- [HCP Terraform Health and drift](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/health)
- [Jenkins Multibranch Pipeline](https://www.jenkins.io/doc/book/pipeline/multibranch/)
