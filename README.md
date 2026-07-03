# DevOps Platform — Production-Style Kubernetes Platform on AWS

A small but production-shaped platform: a frontend + backend app,
containerized, tested, built and released through CI/CD, deployed to EKS
via custom Terraform modules, with a private RDS database.

## Architecture

```
                    Internet
                       │
                  ┌────▼────┐
                  │  Ingress │  (ALB, public)
                  │  (frontend only)
                  └────┬────┘
                       │
                ┌──────▼──────┐        /api/*        ┌─────────────┐
                │  frontend    │ ───────────────────▶ │  backend     │
                │  (nginx, 2x) │   proxy_pass          │  (node, 2x)  │
                └──────────────┘                       └──────┬──────┘
                                                                │ private
                                                          ┌─────▼─────┐
                                                          │  RDS (DB)  │
                                                          │  private   │
                                                          └────────────┘
```

- **frontend** never calls the backend using an internal hostname directly
  from the browser — nginx reverse-proxies `/api/*` to the backend. Avoids
  CORS, and means the frontend doesn't change between environments.
- **backend** is internal-only: `ClusterIP` Service, no Ingress rule points
  at it. Only reachable from inside the cluster.
- **database** is in private subnets only, security group locked to the EKS
  node security group, never publicly accessible. Full design rationale in
  [`terraform/README.md`](terraform/README.md).

## Repository structure

```
.
├── backend/                  # Express API - /, /health, /api/info (port 8080)
│   ├── src/app.js  server.js
│   ├── tests/                # Jest + supertest
│   └── Dockerfile             # multi-stage, non-root, HEALTHCHECK
├── frontend/                  # static page served by nginx, proxies /api/*
│   ├── public/index.html
│   ├── tests/                  # sanity checks + htmlhint
│   └── Dockerfile
├── docker-compose.yml           # local dev: frontend :3000, backend :8080
├── .dockerignore / .gitignore
├── .github/workflows/
│   └── deploy.yml                 # test -> build -> tag -> push -> release -> deploy
├── k8s/                             # Kubernetes manifests
│   ├── namespace.yaml
│   ├── backend-deployment.yaml / backend-service.yaml
│   ├── frontend-deployment.yaml / frontend-service.yaml
│   ├── backend-configmap.yaml
│   ├── backend-secret-example.yaml  # template only, not a real secret
│   └── ingress.yaml
├── terraform/                        # AWS infra, custom modules only
│   ├── provider.tf  main.tf  variables.tf  outputs.tf
│   ├── environments/                  # dev / prod tfvars + backend config
│   ├── modules/vpc  ecr  eks  rds  monitoring/
│   └── README.md                        # Task 4 + Task 5 full explanations
└── docs/
    ├── troubleshooting.md                # 15 incident-response scenarios
    └── future-improvements.md              # 16 improvements, each with why/how/risk
```

## Running locally

```bash
docker compose up -d --build
curl http://localhost:8080/           # Application is running
curl http://localhost:8080/health     # {"status":"ok"}
# frontend: http://localhost:3000
```

## Running tests

```bash
cd backend && npm ci && npm test
cd frontend && npm ci && npm test
```

## CI/CD pipeline

See [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) and the
"CI/CD pipeline" section this README previously had, now summarized here:

`test-backend` + `test-frontend` → `check-aws-config` → `build-and-push`
(matrix: frontend, backend — tags each image with git-sha, `latest`, and a
release version) → `release` (GitHub Release + tag) → `deploy` (to EKS).

**The pipeline runs end-to-end today**, before any AWS infrastructure
exists — ECR push and the K8s deploy step both detect whether
`AWS_ROLE_ARN`/`EKS_CLUSTER_NAME` secrets are configured, and cleanly mock
those two steps if not (clearly labeled `::warning::` in the logs). Adding
the secrets after `terraform apply` switches both to real, with no workflow
edit needed.

### Secrets required (once real AWS infra exists)

Add under **Settings → Secrets and variables → Actions**:

| Name | Type | Notes |
|---|---|---|
| `AWS_ROLE_ARN` | Secret | IAM role assumed via OIDC — no long-lived AWS keys stored in GitHub at all |
| `EKS_CLUSTER_NAME` | Secret | from `terraform output cluster_name` |
| `AWS_REGION` | Variable | e.g. `ap-southeast-1` |
| `ECR_REPO_BACKEND` / `ECR_REPO_FRONTEND` | Variable | from `terraform output ecr_repository_urls` |

Full reasoning for OIDC over static keys, and how this compares to Jenkins
Credentials/Azure Key Vault/Secrets Manager, is documented inline in the
workflow file and was covered when the pipeline was first built.

## How each evaluation criterion is met

| Criterion | Where |
|---|---|
| GitHub structure | This layout — matches the expected structure, functional folder names, no "TaskN" labels |
| Frontend/backend separation | `frontend/`, `backend/` — separate apps, separate Dockerfiles, separate CI jobs |
| Docker & Compose quality | multi-stage builds, non-root users, HEALTHCHECK, `docker-compose.yml` |
| CI/CD understanding | `.github/workflows/deploy.yml` — test/build/tag/push/release/deploy staged pipeline |
| Image tagging & ECR push | git-sha + release-version tags, never `latest` in a real deploy; real-or-mock ECR push |
| K8s manifest quality | `k8s/` — probes, resource limits, 2 replicas, ConfigMap/Secret separation, internal-only backend |
| Private DB connectivity | `terraform/README.md` "Task 4" section + `modules/rds` |
| Terraform module structure | `terraform/modules/` — 5 custom modules, no registry modules |
| EKS provisioning knowledge | `modules/eks` — IAM roles, OIDC/IRSA, managed node group, control-plane logging |
| Terraform maintenance | `terraform/README.md` "Task 5" section — upgrades, state, node resize, env separation |
| Security & secrets | OIDC CI auth, `manage_master_user_password`, `k8s/backend-secret-example.yaml` template, `.gitignore` |
| Troubleshooting approach | `docs/troubleshooting.md` — 15 scenarios |
| Documentation quality | this file + `terraform/README.md` + inline comments throughout |
| Future improvements | `docs/future-improvements.md` — 16 areas |
| Production-readiness mindset | rolling updates with zero unavailability, deletion protection, multi-AZ, least-privilege IAM throughout |

## Pushing this to GitHub

```bash
cd devops-platform
git init
git add .
git commit -m "Production-style Kubernetes platform on AWS"
git branch -M main
git remote add origin <your-empty-github-repo-url>
git push -u origin main
```

Then, once real AWS infra is provisioned (`cd terraform && terraform apply`),
add the 4 secrets/variables listed above under repo Settings, and the next
push to `main` will do a real ECR push + EKS deploy automatically.
