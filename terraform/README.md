# Terraform — AWS Infrastructure for the DevOps Platform

Provisions everything the platform runs on: VPC, EKS cluster + node group,
ECR repositories, a private RDS database, and CloudWatch monitoring. Every
module here is **custom-written** (no `terraform-aws-modules/*` or any other
registry module) — the goal is to demonstrate actually understanding what
each resource does, not to wire together someone else's module.

## Structure

```
terraform/
├── provider.tf              # AWS + TLS providers, S3 remote backend config
├── main.tf                  # wires the 5 modules together
├── variables.tf              # environment, region, sizing, DB config
├── outputs.tf                 # cluster name/endpoint, registry URLs, VPC ID
├── environments/
│   ├── dev.tfvars / prod.tfvars           # per-environment sizing
│   └── dev-backend.hcl / prod-backend.hcl # per-environment state location
└── modules/
    ├── vpc/          # VPC, public+private subnets, NAT per AZ, routing
    ├── ecr/           # container registries, scan-on-push, lifecycle policy
    ├── eks/            # cluster, IAM roles, OIDC provider, managed node group
    ├── rds/             # private database, security group, AWS-managed password
    └── monitoring/       # CloudWatch log groups + Container Insights add-on
```

## Usage

```bash
cd terraform

# One-time per environment: point at that environment's remote state
terraform init -backend-config=environments/dev-backend.hcl

# Review changes
terraform plan -var-file=environments/dev.tfvars

# Apply
terraform apply -var-file=environments/dev.tfvars
```

Switching to `prod` is the *same code*, different `-backend-config` and
`-var-file` — see "Separating dev, staging, and production" below.

---

## Task 4 — Private Database Connectivity

### How EKS connects privately to the database

The backend pod resolves `DB_HOST` (from `k8s/backend-configmap.yaml`) to the
RDS instance's endpoint. That endpoint only has a **private DNS name** — RDS
was never given a public IP, so there is nothing for a public DNS record to
even point at. Traffic flow: `backend pod → node ENI (private subnet) →
VPC router → RDS ENI (private subnet)`, entirely inside the VPC's private
IP space. It never touches the internet gateway, and it never leaves AWS's
private network.

### Private subnet design

`modules/vpc` creates one private subnet per AZ, and `modules/rds`'s
`aws_db_subnet_group` is built **only** from those private subnet IDs — RDS
physically cannot be placed in a public subnet with this code, because the
subnet group it must choose from doesn't contain any. This is enforced by
the module's input, not by convention or a checkbox.

### Private DNS requirement

RDS automatically publishes a private DNS record for its endpoint, resolvable
from anywhere inside the VPC (via the VPC's default DNS resolver, since
`enable_dns_support`/`enable_dns_hostnames` are both `true` on the VPC). No
extra private hosted zone is required for RDS itself. If a custom internal
domain is preferred later (e.g. `db.internal.platform.local`), that would be
a Route53 **private hosted zone** associated with the VPC, with a `CNAME`
pointing at the real RDS endpoint — see `k8s/backend-configmap.yaml`'s
`DB_HOST` comment for where that would slot in.

### Security group rules — only the backend can reach the database

`modules/rds` creates a security group with **exactly one ingress rule**:
TCP on the DB port (5432/3306), source = the EKS node security group ID
(passed in from `modules/eks`'s `node_security_group_id` output). There is
no `0.0.0.0/0` rule anywhere in this security group. Concretely:

- A request from the internet: blocked at the VPC boundary — RDS has no
  route to/from the internet gateway at all.
- A request from another AWS account or a different VPC: blocked — no
  peering/route exists.
- A request from an EC2 instance in the *same* VPC that isn't an EKS node
  (e.g. a bastion host): blocked, unless that instance's security group is
  explicitly added as a second ingress source — which this code deliberately
  does not do.
- A request from an EKS pod: the pod's traffic egresses via the node's ENI,
  which *is* in the allowed security group, so it's permitted at the
  network layer. (Kubernetes NetworkPolicies would add a second, pod-level
  layer restricting this to only backend pods specifically — see
  `docs/future-improvements.md` → "Network Policies".)

### How database credentials are stored securely

`aws_db_instance.this` sets `manage_master_user_password = true`. This means:

- AWS RDS itself generates the master password at creation time.
- It's stored directly in **AWS Secrets Manager**, encrypted with a
  Secrets-Manager-managed KMS key.
- **Terraform never receives, stores, or logs the plaintext password** — not
  in a variable, not in the `.tfstate` file, not in a plan/apply log. The
  only thing Terraform ever handles is the *ARN* of the secret
  (`master_user_secret_arn`, exposed as a root output).
- At runtime, the backend pod's credentials come from a Kubernetes `Secret`
  (`backend-db-secret`, see `k8s/backend-secret-example.yaml`) which — in a
  real deployment — is synced from that same Secrets Manager entry via the
  **AWS Secrets Manager and Config Provider for Secrets Store CSI Driver**,
  not typed in by hand and not committed anywhere.

### How to confirm the database is not publicly accessible

```bash
# 1. Confirm publicly_accessible is false
aws rds describe-db-instances --db-instance-identifier devops-platform-dev-db \
  --query 'DBInstances[0].PubliclyAccessible'
# expected: false

# 2. Confirm it only has a private DNS record (no public one)
dig devops-platform-dev-db.xxxxxxxxxx.ap-southeast-1.rds.amazonaws.com
# expected: resolves only from inside the VPC / over a VPN, times out from
# a machine outside the VPC

# 3. Confirm the security group has no 0.0.0.0/0 ingress rule
aws ec2 describe-security-groups --group-ids <db-sg-id> \
  --query 'SecurityGroups[0].IpPermissions'
# expected: single rule, source = EKS node security group ID, not a CIDR

# 4. Try to connect from outside the VPC (should time out, not "connection
#    refused" - a refused connection means it's reachable but rejecting;
#    a timeout means there is genuinely no route)
psql -h <db-endpoint> -U app_admin -d appdb
```

---

## Task 5 — Terraform Maintenance & Operations

### How to safely upgrade AKS/EKS

EKS upgrades one **minor** version at a time (e.g. 1.29 → 1.30, never 1.29 →
1.31 directly):

1. Read the AWS EKS release notes for the target version for any deprecated
   API removals (`pluto` or `kubent` can scan manifests for removed APIs
   before upgrading).
2. Upgrade the **control plane** first: bump `kubernetes_version` in
   `environments/*.tfvars`, `terraform plan`, review, `terraform apply`.
   AWS upgrades the control plane with no action needed on running
   workloads — the control plane is HA across AZs by design.
3. Upgrade **add-ons** next (VPC CNI, CoreDNS, kube-proxy) to versions
   compatible with the new control plane version.
4. Upgrade the **node group** last. `update_config.max_unavailable = 1`
   (already set in `modules/eks`) means nodes are replaced one at a time —
   the ASG launches a new node on the new AMI/version, waits for it to be
   `Ready`, cordons + drains an old node, then repeats. Pod Disruption
   Budgets on the deployments (a natural next addition — see
   `docs/future-improvements.md`) prevent a drain from taking down every
   replica of a service at once.
5. Verify with `kubectl get nodes` (all on new version) and watch
   application health/error rates for a few minutes before considering it done.

### How to add or resize node pools

Change `node_desired_count` / `node_min_count` / `node_max_count` (or
`node_instance_type` for a new instance family) in the relevant
`environments/*.tfvars`, then `terraform apply`. Note `modules/eks` already
sets `lifecycle { ignore_changes = [scaling_config[0].desired_size] }` —
this is deliberate: once a cluster autoscaler is running, *it* owns
desired_size in response to real-time load, and Terraform should only own
the min/max ceiling, not fight the autoscaler on every apply.

To add an entirely new node pool (e.g. a GPU or spot pool for a specific
workload), add a second `aws_eks_node_group` resource block to
`modules/eks/main.tf` with its own instance type/capacity_type/taints —
existing pods are unaffected since Kubernetes only schedules new pods (or
pods matching a `nodeSelector`/toleration) onto the new pool.

### How to maintain Terraform state

- **Remote backend** (`provider.tf`): state lives in a versioned, encrypted
  S3 bucket — never on a laptop, never in git.
- **Locking**: a DynamoDB table (`environments/*-backend.hcl` →
  `dynamodb_table`) ensures only one `apply` can run at a time; a second
  concurrent apply fails fast with a lock-held error instead of corrupting
  state.
- **Versioning**: S3 bucket versioning (provisioned once, out-of-band, as
  part of the bootstrap step below) means any bad state write can be rolled
  back to the previous version.
- **Isolation**: each environment has its own state file
  (`key = "eks/dev/terraform.tfstate"` vs `.../prod/...`) so a mistake in
  `dev` can never touch `prod`'s state.
- **Bootstrapping**: the S3 bucket + DynamoDB table themselves can't be
  created by the same Terraform config that needs them to exist first —
  they're created once, manually or via a small separate `bootstrap/`
  config with local state, before anyone runs `terraform init` against
  the main config.

### How to avoid downtime during cluster changes

- `maxUnavailable: 0, maxSurge: 1` on every Kubernetes Deployment (already
  set in `k8s/*-deployment.yaml`) — a new pod must be `Ready` before an old
  one is removed.
- `update_config.max_unavailable = 1` on the node group — nodes roll one
  at a time, never all at once.
- `deletion_protection = true` on the RDS instance — an accidental
  `terraform destroy`/apply-that-implies-replacement cannot silently delete
  the database.
- Multi-AZ node group and multi-AZ RDS (`multi_az` auto-enabled for
  non-micro instance classes) so a single AZ failure doesn't take the
  platform down.
- Always run `terraform plan` and actually read it before `apply` —
  specifically watch for lines showing `-/+` (destroy and recreate) on the
  cluster or database resources; see the next section.

### How to separate dev, staging, and production

Same module code, three separate:
- **State files** — different `key` in each `environments/*-backend.hcl`,
  so `terraform apply` in dev can never see or touch prod's state.
- **`.tfvars` files** — different CIDR ranges (no overlap, so VPC peering
  is possible later without renumbering), different instance sizes, and
  `environment` variable drives naming/tagging so all resources are
  unambiguously identifiable in the AWS console/cost explorer.
- **AWS accounts (recommended, not yet implemented here)** — the strongest
  isolation is separate AWS accounts per environment (via AWS
  Organizations), so a mis-scoped IAM policy or compromised credential in
  dev has zero blast radius into prod. This repo's current setup (same
  account, different state/tfvars) is the appropriate starting point for a
  small platform and documented here as the next step — see
  `docs/future-improvements.md`.
- **CI/CD gating** — `staging`/`prod` applies require a manual approval
  step (GitHub Environments with required reviewers), `dev` applies on
  every merge to `main`.

### How to handle secrets outside Terraform code

- The RDS master password never exists as Terraform state (see Task 4
  section above — `manage_master_user_password = true`).
- Any secret Terraform *does* need as an input (rare, given the above) is
  passed via a `TF_VAR_*` environment variable sourced from CI secrets —
  never written into a `.tfvars` file that gets committed.
  `terraform.tfstate` itself can still contain sensitive *values* for some
  resource types, which is exactly why the state bucket is encrypted and
  access-restricted (bucket policy limits reads to the CI role only) rather
  than relying on "don't put secrets in tfvars" alone.
- Application-level secrets (DB credentials the backend needs at runtime)
  flow **Secrets Manager → Kubernetes Secret (via CSI driver) → pod env
  var**, bypassing Terraform state entirely after initial creation.

### What to check if Terraform wants to recreate the cluster

A `-/+` (destroy and recreate) on `aws_eks_cluster` is almost always caused
by a change to an **immutable** argument. Before running `apply`:

1. `terraform plan` output — look at exactly which argument shows as
   changed under the `~`/`-/+`. The usual suspects for EKS specifically:
   - `vpc_config.subnet_ids` changed (e.g. a subnet was added/removed/
     reordered) — subnet *set* changes can force recreation depending on
     the provider version; reordering a list vs. a true set matters.
   - `name` changed — cluster name is immutable, full recreate.
   - `role_arn` pointing at a genuinely different IAM role (not just a
     policy change on the same role — that's mutable in place).
2. Check whether the diff is a **real intended change** or **drift** —
   run `terraform plan` again after confirming no one changed anything
   manually in the AWS console (console changes bypass Terraform and show
   up as unexpected diffs on the next plan).
3. Check the Terraform AWS provider version — provider upgrades sometimes
   change a resource's `ForceNew` behavior between versions; check the
   provider's CHANGELOG for the specific resource before upgrading in a
   live environment.
4. If recreation truly is unavoidable (e.g. genuinely renaming the
   cluster), plan it as an explicit blue/green cluster migration — stand
   up the new cluster alongside the old one, migrate workloads, cut over
   DNS/Ingress, then decommission the old cluster — never let a single
   `apply` silently drop the only running cluster.
