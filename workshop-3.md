# Workshop 3: GitHub, Jenkins, HCP Terraform, Security, and Drift

<!-- markdownlint-disable MD013 MD024 MD025 -->

[Back to the workshop landing page](./README.md)

**Live delivery:** Use the
[Workshop 3 presenter script](./presenter-script.md#workshop-3-github-jenkins-hcp-terraform-security-and-drift).
The detailed sections below are your technical reference.

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

### On screen

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

### On screen

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

### On screen

Show the Checkov alternative:

```bash
checkov -d . --framework terraform --compact
```

## Step 3: Show the development workspace

### On screen

Open HCP Terraform and complete these steps:

1. Open the correct organization.
2. Open or create the Vault Development project.
3. Open or create `vault-team-pilot-dev`.
4. Connect the GitHub repository.
5. Set the working directory to `live/dev`.
6. Select Agent execution mode.
7. Select the approved Agent pool.
8. Disable auto-apply.
9. Pin the Terraform version.
10. Add the development team permissions.
11. Add the Vault dynamic credential settings.
12. Add the required policy sets and run tasks.
13. Enable health assessments after the first successful apply.

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

## Step 4: Show Vault dynamic credential settings

### On screen

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

### On screen

1. Change one non-sensitive value in `live/dev/teams.json`.
2. Create a Git branch.
3. Create a GitHub pull request.
4. Open the Jenkins results.
5. Open the HCP Terraform speculative plan.
6. Review the Terraform code and the plan.
7. Merge the pull request.
8. Open the new HCP Terraform workspace run.
9. Review policy and run-task results.
10. Review the final plan.
11. Ask the authorized development approver to confirm apply.
12. Open the Agent run output.
13. Open the final state and run history.

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

### On screen

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

### On screen

1. Record the current Terraform-managed Vault setting.
2. Change that setting manually in development Vault.
3. Open the HCP Terraform workspace Health page.
4. Start or wait for the next health assessment.
5. Open the drift result.

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

## Step 8: Show the shared governance model

### On screen

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
> Before a live demonstration, we need to confirm Nutanix access, supported
> connections, supported resource types, and current product availability.

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

## Navigation

- Previous: [Workshop 2: Import, Moved Blocks, Workspaces, and State](./workshop-2.md)
- Landing page: [Nutanix Terraform and Vault Workshop Series](./README.md)
