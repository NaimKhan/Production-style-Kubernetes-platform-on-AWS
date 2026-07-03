# Future Improvements

What this platform deliberately does **not** include yet, and the plan for
each — in rough priority order for a real production rollout.

---

## 1. Secret management (Secrets Store CSI Driver)

- **What**: Replace manually-created Kubernetes Secrets with the AWS
  Secrets Manager and Config Provider for the Secrets Store CSI Driver, so
  Secrets are synced live from Secrets Manager into pods as mounted
  files/env vars.
- **Why needed**: Right now `k8s/backend-secret-example.yaml` is explicitly
  a template — a real Secret still has to be created out-of-band. That's a
  manual step that doesn't scale past one person/one environment.
- **Business value**: credential rotation becomes a Secrets Manager
  operation, not a "who has kubectl access to update the Secret" operation
  — faster, auditable, and doesn't require redeploying to rotate.
- **Implementation**: install the CSI driver + AWS provider as a cluster
  add-on (Terraform `aws_eks_addon` or a Helm release), define a
  `SecretProviderClass` referencing the RDS `master_user_secret_arn`
  output, mount it in the backend Deployment.
- **Risk reduced**: credentials sitting in `kubectl get secret -o yaml`
  output (base64, not encrypted) accessible to anyone with namespace read
  access; stale credentials that were never rotated because rotation was
  manual and got skipped.

## 2. Image vulnerability scanning (CI-gated)

- **What**: Fail the CI pipeline if a pushed image has HIGH/CRITICAL CVEs
  (ECR scan-on-push is already enabled in `modules/ecr` — this adds a
  pipeline gate that actually blocks on the result, plus periodic
  re-scanning of images already in production).
- **Why needed**: scan-on-push alone reports findings but doesn't stop a
  vulnerable image from being deployed; someone has to be watching.
- **Business value**: catches known-vulnerable base images/dependencies
  before they reach production, which is far cheaper than a post-incident
  patch.
- **Implementation**: add a step in `.github/workflows/ci-cd.yml` after
  push that polls `aws ecr describe-image-scan-findings` and fails the
  job on findings above a configurable severity threshold; separately, a
  scheduled workflow re-scans images currently running in each environment.
- **Risk reduced**: shipping a known CVE into production that a scanner
  already knew about at build time.

## 3. Monitoring and alerting (beyond raw metrics collection)

- **What**: `modules/monitoring` ships logs/metrics to CloudWatch, but
  nothing currently *alerts* a human. Add CloudWatch Alarms (or migrate to
  Prometheus + Alertmanager if the team outgrows CloudWatch) for pod
  restart rate, 5xx rate on the ALB, RDS CPU/connections/storage, and node
  disk pressure — routed to Slack/PagerDuty.
- **Why needed**: a certificate expiring or a pod crash-looping should be
  caught by an alert, not by a customer report (see
  `docs/troubleshooting.md` Q6).
- **Business value**: reduces mean-time-to-detection from "whenever
  someone notices" to minutes, which directly reduces downtime cost.
- **Implementation**: `aws_cloudwatch_metric_alarm` resources in
  `modules/monitoring`, SNS topic wired to a Slack webhook via Lambda or
  AWS Chatbot.
- **Risk reduced**: silent outages; slow incident response.

## 4. Rollback strategy

- **What**: a documented, tested one-command rollback — both for a bad
  Kubernetes rollout (`kubectl rollout undo`) and for a bad database
  migration.
- **Why needed**: the CI/CD pipeline currently deploys forward only; there's
  no rehearsed "undo" path if a release breaks something in production.
- **Business value**: turns "we need to fix this urgently" into "we revert
  in 30 seconds while we investigate calmly" — directly reduces incident
  duration and stress.
- **Implementation**: since every image is tagged with an immutable
  git-sha (never `latest`), rollback is just re-pointing the Deployment at
  the previous tag — `kubectl set image` or re-running the deploy job with
  a prior `RELEASE_TAG`. Document the exact commands in
  `docs/troubleshooting.md` and rehearse it at least once in `dev`.
- **Risk reduced**: prolonged outages while someone improvises a fix under
  pressure.

## 5. Helm chart

- **What**: convert `k8s/*.yaml` into a parameterized Helm chart (or keep
  Kustomize, but formalize environment overlays either way).
- **Why needed**: the current manifests hardcode values that differ by
  environment (replica count, resource limits, image tag) via manual edits
  or `sed`/`kustomize edit` in CI — fine for 2 services, harder to keep
  consistent as it grows.
- **Business value**: one templated source of truth per environment,
  fewer copy-paste drift bugs between dev/staging/prod manifests.
- **Implementation**: `helm create`, move current YAML into
  `templates/`, extract environment-specific values into
  `values-dev.yaml`/`values-prod.yaml`, deploy via `helm upgrade --install`
  in the CI/CD `deploy` job instead of raw `kubectl apply`.
- **Risk reduced**: manifest drift between environments causing
  "works in dev, breaks in prod" surprises.

## 6. Terraform remote backend hardening

- **What**: the S3 backend (`provider.tf`) is configured, but the bucket
  itself needs: versioning enabled, a bucket policy restricting access to
  the CI IAM role only, and MFA delete for the state bucket in prod.
- **Why needed**: state currently would be readable by anyone with general
  S3 read access in the account unless explicitly locked down — and state
  can contain sensitive resource attributes.
- **Business value**: prevents both accidental and malicious state
  tampering, which could otherwise be used to hide or mask infrastructure
  changes.
- **Implementation**: a small one-time `bootstrap/` Terraform config
  (separate, local-state) that creates the S3 bucket + DynamoDB table with
  the correct policies, run once per AWS account before the main config's
  first `terraform init`.
- **Risk reduced**: state corruption/tampering, accidental public exposure
  of a state file containing infrastructure details.

## 7. Kubernetes autoscaling (HPA + Cluster Autoscaler)

- **What**: Horizontal Pod Autoscaler on both Deployments (scale on CPU/
  memory or request rate) plus the Kubernetes Cluster Autoscaler wired to
  the node group's min/max (already sized for this in `modules/eks`).
- **Why needed**: right now replica count is fixed at 2 regardless of load
  — fine for a demo, not for real traffic variability.
- **Business value**: handles traffic spikes automatically without manual
  intervention, and scales *down* during low traffic to save cost.
- **Implementation**: `HorizontalPodAutoscaler` manifests targeting
  `backend`/`frontend` Deployments; Cluster Autoscaler deployed as a
  cluster add-on with IRSA permissions scoped to the specific node group's
  ASG.
- **Risk reduced**: manual capacity planning errors — both under-provisioning
  (outages during spikes) and over-provisioning (wasted spend).

## 8. Cluster upgrade strategy (automated + tested)

- **What**: formalize the manual steps in `terraform/README.md` into a
  tested runbook, ideally rehearsed against a disposable `dev` cluster
  before every prod upgrade, with a maintenance-window/change-management
  process for prod.
- **Why needed**: EKS forces upgrades eventually (AWS deprecates old
  versions); doing this for the first time under deadline pressure is how
  upgrades turn into incidents.
- **Business value**: predictable, low-risk upgrade cadence instead of a
  scramble every time AWS sends an end-of-support notice.
- **Implementation**: a scheduled quarterly "upgrade dev, soak 1 week,
  upgrade staging, soak, upgrade prod" cadence, documented as a checklist.
- **Risk reduced**: forced emergency upgrades on AWS's timeline instead of
  the team's own, with less time to catch compatibility issues.

## 9. Production approval gates

- **What**: `deploy` job in `.github/workflows/ci-cd.yml` already declares
  a GitHub `environment: production` — the missing piece is actually
  configuring required reviewers on that Environment in repo settings.
- **Why needed**: currently any successful merge to `main` deploys straight
  through automatically once real credentials are configured.
- **Business value**: a human checkpoint before production changes,
  without slowing down dev/staging iteration at all.
- **Implementation**: GitHub repo Settings → Environments → `production` →
  Required reviewers; optionally add a wait timer for off-hours deploys.
- **Risk reduced**: an untested or accidental merge going straight to
  production with no human in the loop.

## 10. Private cluster (restrict public API endpoint)

- **What**: `modules/eks` currently sets `endpoint_public_access = true`
  (with a comment flagging this). Harden to `public_access_cidrs`
  restricted to office/VPN CIDRs, or fully private with a bastion/VPN for
  `kubectl` access.
- **Why needed**: the EKS API server is internet-reachable by default in
  this config (auth is still required, but it's still a larger attack
  surface than necessary).
- **Business value**: significantly shrinks the attack surface for the
  single most privileged endpoint in the whole platform.
- **Implementation**: set `public_access_cidrs` in `modules/eks`'s
  `vpc_config` to known IP ranges, or disable public access entirely and
  require VPN/bastion/Session Manager for cluster admin access.
- **Risk reduced**: credential-stuffing or exploit attempts against the
  Kubernetes API server from arbitrary internet sources.

## 11. WAF on the Ingress ALB

- **What**: attach an `aws_wafv2_web_acl` (AWS managed rule groups: common
  exploits, known bad inputs, rate-based rule) to the ALB created by the
  Ingress controller — the annotation is already stubbed out (commented)
  in `k8s/ingress.yaml`.
- **Why needed**: the frontend is the one deliberately public entry point
  into the platform — it should have basic exploit/bot/rate protection in
  front of it, not just app-level input validation.
- **Business value**: blocks common automated attack traffic (SQLi, XSS
  payloads, credential-stuffing bursts) before it ever reaches a pod.
- **Implementation**: create the WebACL in Terraform (a new small module
  or added to `modules/eks`), output its ARN, uncomment and populate the
  `alb.ingress.kubernetes.io/wafv2-acl-arn` annotation in `ingress.yaml`.
- **Risk reduced**: exposure to common, automated web attacks that don't
  require a sophisticated attacker — the "background noise" of the
  internet that every public endpoint receives.

## 12. GitOps with Argo CD

- **What**: move from CI directly running `kubectl apply`/`helm upgrade`
  to CI only building/pushing images + updating a manifest repo, with
  Argo CD continuously reconciling the cluster to match git.
- **Why needed**: today, the cluster's actual state can only be known by
  asking the cluster (`kubectl get`) — there's no single source of truth
  and no automatic drift detection if someone runs a manual `kubectl edit`.
- **Business value**: git becomes the actual source of truth for "what's
  running," drift is detected and can be auto-corrected, and rollback is
  a `git revert`.
- **Implementation**: install Argo CD, point it at a manifest path (or a
  separate GitOps repo), CI's `deploy` job changes from `kubectl apply` to
  "commit the new image tag to the manifest repo."
- **Risk reduced**: undocumented manual cluster changes ("it works because
  someone patched it by hand once and nobody remembers"), harder-to-audit
  deployment history.

## 13. Blue/green or canary deployment

- **What**: instead of rolling every pod straight to the new version,
  route a small percentage of traffic to the new version first (canary),
  or run both versions fully side-by-side and switch traffic atomically
  (blue/green), using something like AWS App Mesh, Argo Rollouts, or ALB
  weighted target groups.
- **Why needed**: the current RollingUpdate strategy is safe against
  *unavailability* but not against a *bad but "healthy-looking"* release —
  a new version can pass its readiness probe while still returning wrong
  data or elevated error rates under real traffic.
- **Business value**: catches bad releases against a small fraction of
  real traffic before every user is affected, and gives a fast, clean
  abort path.
- **Implementation**: Argo Rollouts CRDs replacing the plain Deployment,
  automated analysis (error rate/latency) gating progression from 10% →
  50% → 100% traffic.
- **Risk reduced**: a subtly broken release affecting 100% of users
  before anyone notices.

## 14. Backup and disaster recovery

- **What**: automated RDS snapshots (beyond the default 7-day backup
  window already set in `modules/rds`) copied cross-region, plus a
  documented, tested restore procedure and an EKS cluster
  re-provisioning runbook (this Terraform config *is* that runbook, but
  it's never been rehearsed end-to-end from zero).
- **Why needed**: a backup that's never been restored isn't a verified
  backup — and single-region snapshots don't protect against a regional
  AWS incident.
- **Business value**: a bounded, known recovery time instead of an
  open-ended "we hope this works" during an actual disaster.
- **Implementation**: `aws_db_instance` cross-region automated backup
  replication, a quarterly game-day exercise that actually restores a
  snapshot into a scratch environment and re-runs `terraform apply` from
  scratch against a fresh AWS account/VPC.
- **Risk reduced**: extended or total data loss / extended downtime in a
  disaster scenario that's never been tested.

## 15. Network policies

- **What**: Kubernetes `NetworkPolicy` resources restricting pod-to-pod
  traffic — specifically, only the frontend can reach the backend, and
  only the backend can reach anything DB-related, at the pod level (not
  just the AWS security-group level, which is already in place).
- **Why needed**: currently, network isolation between frontend and
  backend stops at the AWS security group — any pod in the cluster could
  technically reach `backend-service` today. A NetworkPolicy adds a second,
  independent layer so a compromised unrelated pod can't pivot to the
  backend.
- **Business value**: limits blast radius if any single workload in the
  cluster is compromised — defense in depth instead of a single perimeter.
- **Implementation**: requires a CNI that enforces NetworkPolicy (the
  default AWS VPC CNI needs the network policy add-on enabled); add
  `NetworkPolicy` manifests to `k8s/` denying all ingress by default,
  explicitly allowing frontend → backend on port 8080.
- **Risk reduced**: lateral movement inside the cluster from a compromised
  or misconfigured unrelated workload.

## 16. Cost optimization

- **What**: Savings Plans / Reserved Instances for the steady-state node
  baseline, Spot instances for a secondary non-critical node group,
  right-sizing based on actual CloudWatch Container Insights usage data
  (once #3 is in place) instead of the current estimated defaults, and S3
  lifecycle rules on old Terraform state versions / ECR untagged images
  (partially done — see `modules/ecr`'s lifecycle policy).
- **Why needed**: default on-demand sizing across all environments is the
  most expensive way to run this, and nobody's actually looked at real
  utilization yet since the platform doesn't exist in production.
- **Business value**: directly reduces monthly AWS spend — often 30-50%
  achievable with RIs/Savings Plans alone at steady state.
- **Implementation**: after 2-4 weeks of real Container Insights data,
  right-size `node_instance_type`/`instance_class` per environment; add a
  second `capacity_type = "SPOT"` node group for fault-tolerant workloads.
- **Risk reduced**: budget overrun / paying on-demand rates indefinitely
  for predictable, steady-state capacity.
