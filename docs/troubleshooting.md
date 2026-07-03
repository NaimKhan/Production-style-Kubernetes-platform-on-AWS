# Troubleshooting

Brief, actionable answers — what I'd actually check first, in order.

---

### 1. Pod is in `CrashLoopBackOff`. What do you check?

1. `kubectl logs <pod> --previous` — the crash reason is almost always in
   the logs from the last attempt, not the current (empty) one.
2. `kubectl describe pod <pod>` — check `Last State: Terminated / Reason` and
   `Exit Code` (137 = OOMKilled, 1 = app error, 143 = SIGTERM from a failed
   probe).
3. If OOMKilled: raise `resources.limits.memory` or fix a memory leak.
4. If it's failing on startup (e.g. can't reach the DB, missing env var):
   check `envFrom`/ConfigMap/Secret are actually mounted —
   `kubectl exec` into a working pod's image, or `kubectl describe cm/secret`.
5. Check the `livenessProbe` isn't firing before the app is actually ready
   (too-short `initialDelaySeconds`), which would restart a genuinely
   healthy but slow-starting app forever.

### 2. Deployment is successful, but app is not reachable. What do you check?

1. `kubectl get pods -o wide` — are pods actually `Running` and `Ready`
   (not just `Running`)? A pod can be running but failing readiness.
2. `kubectl get endpoints <service>` — if empty, the Service's label
   `selector` doesn't match the pod's labels (the #1 cause of this).
3. `kubectl get svc` — confirm the port/targetPort mapping matches the
   container's actual listening port.
4. Test from inside the cluster first: `kubectl run debug --rm -it
   --image=busybox -- wget -qO- http://backend-service:8080/health`
   — isolates "is it a Service problem" from "is it an Ingress problem".
5. If internal test works but external doesn't: move to the Ingress/ALB
   (see Q7).

### 3. Difference between readiness and liveness probe?

- **Readiness** answers "can this pod receive traffic *right now*?" —
  failing it removes the pod from the Service's Endpoints (traffic stops
  routing to it) but does **not** restart the pod. Used for temporary
  states: still loading config, DB connection pool warming up, etc.
- **Liveness** answers "is this pod stuck/dead and needs a restart?" —
  failing it kills and restarts the container. Used for genuine deadlocks
  or unrecoverable states.
- Getting them backwards is a classic outage cause: putting a slow
  dependency check in the liveness probe restarts a pod that just needed
  more time, potentially causing a crash loop under load instead of
  gracefully waiting.

### 4. Docker build works locally but fails in pipeline. Why?

Most common causes, roughly in order of likelihood:
- **Different base image / cached layers** — local Docker has old cached
  layers or a locally-pulled `:latest` base image that's newer/older than
  what CI pulls fresh.
- **Platform mismatch** — building on an Apple Silicon Mac (arm64) but the
  pipeline runner is amd64 (or vice versa) — a native dependency compiled
  for the wrong architecture fails at runtime, not build time, which is
  even more confusing. Fix: `docker build --platform linux/amd64`.
- **Missing files due to `.dockerignore`** or files that exist locally but
  were never committed to git (pipeline builds from a fresh git checkout,
  not your working directory).
- **Environment/secret differences** — a build step relies on an env var
  or credential (npm registry token, private package) present locally but
  not injected in CI.
- **Uncommitted lockfile drift** — `package-lock.json`/`Dockerfile` out of
  sync with what's actually committed.

### 5. Pipeline fails during Docker build. What do you check?

1. Read the actual failing step's log output first — the error is usually
   explicit (missing file, failed `npm install`, network timeout).
2. Confirm build context is correct — `docker build ./backend` vs
   accidentally building from repo root without the right `context:`.
3. Check registry/network access — can the runner reach `registry.npmjs.org`,
   `pypi.org`, etc.? Corporate/self-hosted runners sometimes have
   restrictive egress.
4. Check for a `--platform` or base-image tag mismatch (see Q4).
5. Reproduce locally with the exact same command the pipeline runs
   (copy-paste from the workflow file), not a "close enough" local build.

### 6. Certificate renewal failed. What do you check?

1. Is the renewal automated (ACM auto-renewal, cert-manager) or manual?
   ACM auto-renews as long as DNS validation records still exist — check
   they weren't accidentally deleted.
2. For cert-manager: `kubectl describe certificate <name>` and
   `kubectl describe certificaterequest` — shows the exact ACME challenge
   failure (usually DNS-01 record propagation or HTTP-01 path not reachable
   through the Ingress).
3. Check the domain's DNS still actually points where the validation
   expects — a DNS provider change or expired domain breaks this silently.
4. Check rate limits — Let's Encrypt has weekly rate limits per domain;
   repeated failed attempts can exhaust it.
5. Check certificate expiry monitoring/alerting exists at all — this
   should never be discovered by an outage (see
   `docs/future-improvements.md` → Monitoring and alerting).

### 7. Ingress returns 502 or 504. What do you check?

- **502 (Bad Gateway)** — the ALB/Ingress reached a backend pod, but got an
  invalid response or the connection was reset. Check: is the target
  actually the right port (`targetPort` matches container port)? Is the
  app crashing mid-request? Check backend pod logs at the exact timestamp.
- **504 (Gateway Timeout)** — the ALB never got a response in time. Check:
  is the pod healthy but just slow (DB query timeout, N+1 query)? Is the
  readiness probe passing but the app not actually able to serve real
  traffic yet? Check ALB target group health in the AWS console — if
  targets show "unhealthy", the healthcheck path itself is misconfigured
  (`alb.ingress.kubernetes.io/healthcheck-path`).
- Either way: `kubectl logs` on the pod for that timeframe, and
  `kubectl get targetgroupbindings` / AWS console ALB target health tab.

### 8. Vendor SFTP connection to port 22 times out. What do you check?

1. Security group / NACL on both ends — outbound from our side allowed on
   22? Inbound on the vendor's side allowed **from our specific egress
   IP/CIDR** (if we're behind a NAT gateway, that's the NAT's Elastic IP —
   confirm the vendor whitelisted the *current* one, especially if the NAT
   EIP changed).
2. Route table — is there actually a route from the source subnet toward
   the vendor's IP (via NAT gateway/IGW/VPN/Direct Connect, whichever
   applies)?
3. Is it actually a network issue or an application-layer one — `telnet
   <host> 22` or `nc -zv <host> 22` from the exact source (a pod, not just
   a laptop) isolates "TCP never connects" (network/firewall) from
   "connects but SFTP handshake fails" (auth/host-key issue).
4. Check whether the vendor requires IP allowlisting and whether egress
   is going out through the expected NAT gateway (multiple NAT gateways
   across AZs means multiple possible source IPs — see `modules/vpc`).
5. Confirm it isn't a broader outage — check if other outbound connections
   from the same subnet work fine.

### 9. Terraform plan wants to recreate the cluster. What do you check?

See `terraform/README.md` → "What to check if Terraform wants to recreate
the cluster" for the full explanation. Short version: read exactly which
argument triggered `-/+` in the plan output (usually `vpc_config.subnet_ids`
or `name`), confirm it's an intended change vs. drift from a manual console
edit, check the AWS provider changelog for `ForceNew` behavior changes
around the current provider version, and if recreation is genuinely
required, treat it as a planned blue/green cluster migration — never let
`apply` silently drop the only cluster.

### 10. How would you upgrade AKS/EKS safely?

See `terraform/README.md` → "How to safely upgrade AKS/EKS" for the full
step-by-step. Short version: one minor version at a time, control plane
first, then add-ons, then nodes last (rolling, one at a time via
`max_unavailable = 1`), verify node versions and app health before calling
it done.

### 11. Frontend loads, but backend API calls fail. What do you check?

1. Browser DevTools Network tab first — is it a CORS error, a 404, a 502,
   or a connection refused? Each points somewhere different.
2. If calls go to `/api/*` and get 404: check the nginx `proxy_pass` target
   in `frontend/nginx.conf.template` — is `BACKEND_HOST`/`BACKEND_PORT`
   actually resolving to `backend-service:8080` in this environment?
3. If 502/504 from the proxy: same as Q7 — the backend pod itself is the
   problem, not the frontend.
4. Confirm the backend Service has healthy Endpoints (Q2).
5. Check backend pod logs for the actual incoming request — if it's not
   arriving at all, the break is between frontend and Service (DNS,
   NetworkPolicy); if it arrives and errors, the break is inside the
   backend (DB, bad request handling).

### 12. Backend pod is running, but database connection times out. What do you check?

1. Security group — does the DB's security group actually allow the EKS
   node security group on the DB port? (See `terraform/README.md` Task 4
   section — this is the single most common cause.)
2. Is the pod even in a subnet that routes to the DB's subnet? (Should
   always be true here since both are private subnets in the same VPC,
   but worth confirming after any VPC/routing change.)
3. `DB_HOST`/`DB_PORT` in the ConfigMap — typo, wrong port for the engine
   (5432 vs 3306), or pointing at a different environment's DB entirely.
4. Is the RDS instance actually `available` (not `creating`/`rebooting`/
   `storage-full`)? `aws rds describe-db-instances`.
5. Credential issue masquerading as a timeout — rule this out by checking
   whether it's a TCP-level timeout (network) or an auth failure that the
   client library is mis-reporting as a timeout (check the exact error
   string in backend logs).

### 13. Private DNS is not resolving database hostname. What do you check?

1. Confirm the VPC has `enable_dns_support` and `enable_dns_hostnames` set
   to `true` (both required — `modules/vpc` sets both).
2. `kubectl exec` into a pod and run `nslookup <db-host>` — does it resolve
   at all, or resolve to the wrong IP?
3. If using a custom Route53 private hosted zone: is it actually
   **associated with the VPC** the pods run in? A private hosted zone not
   associated with the right VPC silently fails to resolve from inside it.
4. Check CoreDNS pods are healthy (`kubectl get pods -n kube-system -l
   k8s-app=kube-dns`) — CoreDNS itself being down breaks all in-cluster DNS,
   not just the DB hostname.
5. Confirm no NetworkPolicy is blocking egress to CoreDNS/port 53 for that
   specific pod (only relevant once NetworkPolicies are introduced — see
   `docs/future-improvements.md`).

### 14. How would you rotate database credentials safely?

1. With `manage_master_user_password = true` (as configured in
   `modules/rds`), AWS Secrets Manager can handle **automatic rotation** on
   a schedule using its built-in RDS rotation Lambda — no manual password
   handling at all.
2. For a manual/application-user rotation: create the **new** credential
   alongside the old one (don't delete the old one first), update the
   Kubernetes Secret (or trigger the Secrets Store CSI driver to
   re-sync), roll the backend Deployment so pods pick up the new Secret,
   confirm the app is healthy and using the new credential, **then**
   revoke/delete the old credential.
3. Never do this by editing a running pod's env directly — env vars are
   fixed at container start, so it has to go through an actual rollout to
   take effect cleanly, which also gives an easy rollback point if the new
   credential is wrong.
4. Test the rotation in `dev` first with the exact same automation that
   would run in `prod`.

### 15. Secrets were accidentally committed to GitHub. What do you do?

1. **Rotate the secret immediately** — treat it as compromised the moment
   it hit git, regardless of whether the repo is public or private, and
   regardless of how quickly it's removed. Removing it from git history
   does not un-expose a secret that's already been rotated through GitHub's
   own systems, forks, CI logs, or anyone who already cloned it.
2. Only *after* rotating: remove it from git history (`git filter-repo` or
   BFG Repo-Cleaner — `git rm` alone only removes it from future commits,
   not history), force-push, and have every collaborator re-clone rather
   than pull (stale local clones can reintroduce the old history).
3. Check CI/CD logs, build artifacts, and any place the pipeline might have
   echoed the value — the leak surface is usually bigger than just the
   git diff.
4. Add the file pattern to `.gitignore` (already done here for `.env*`,
   `*.tfstate*`, `*.pem`, `*.key`) and add a pre-commit hook or GitHub
   secret-scanning (native GitHub feature, enable it if not already on) to
   catch this before the next commit instead of after.
5. Document the incident briefly — what leaked, blast radius, what was
   rotated, what prevents recurrence — even for a small team, so it's not
   silently forgotten.
