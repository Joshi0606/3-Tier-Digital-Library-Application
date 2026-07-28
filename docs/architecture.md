# 3-Tier Digital Library — Complete Architecture Reference

> Interview-ready reference. Everything you need to explain end-to-end.

---

## Table of Contents

1. [High-Level Overview](#1-high-level-overview)
2. [Terraform — How Modules Connect](#2-terraform--how-modules-connect)
3. [Infrastructure Workflow (infrastructure.yml)](#3-infrastructure-workflow)
4. [CI/CD Pipeline (ci-cd.yml)](#4-cicd-pipeline)
5. [Kubernetes Manifests](#5-kubernetes-manifests)
6. [Application Services](#6-application-services)
7. [Security — IRSA Explained](#7-security--irsa-explained)
8. [Observability](#8-observability)
9. [End-to-End Request Flow](#9-end-to-end-request-flow)
10. [Key Design Decisions](#10-key-design-decisions)
11. [Interview Q&A](#11-interview-qa)

---

## 1. High-Level Overview

```
Developer pushes code
        │
        ▼
GitHub Actions
  ├── infrastructure.yml  ←  .tf file changes  →  Terraform apply → AWS infra
  └── ci-cd.yml           ←  app/k8s changes   →  Build → ECR → EKS deploy

AWS Infrastructure
  VPC (10.0.0.0/16)
  ├── Public subnets  → ALB, SonarQube EC2, NAT Gateway
  └── Private subnets → EKS nodes, RDS MySQL

Internet → ALB → EKS (auth:5001, book:5002, borrow:5003, frontend:80)
                     └── SQS → Worker pod → SNS email / RDS bulk insert
```

**Stack:** React (Vite) frontend · Python Flask backends · MySQL RDS · EKS · ECR · SQS · SNS · S3 · SSM · Secrets Manager · CloudWatch

---

## 2. Terraform — How Modules Connect

### State Backend
```hcl
backend "s3" {
  bucket = "ak2.kops"
  key    = "digital-library/prod/terraform.tfstate"
  region = "us-east-1"
}
```
State is stored remotely in S3 with file-based locking (`use_lockfile = true`).

### Module Dependency Tiers

Terraform resolves build order from `module.xxx.output` references, not file order.

```
TIER 1 (no dependencies)
├── module.vpc       → VPC, subnets, IGW, NAT GW, 3 security groups
├── module.iam       → EKS cluster role, EKS node role
├── module.ecr       → 5 ECR repos (auth, book, borrow, frontend, worker)
├── module.s3        → Assets bucket (private, encrypted, versioned)
├── module.sqs       → Orders queue + DLQ with redrive policy
├── module.sns       → Alerts topic + email subscriptions
└── module.secrets   → Generates JWT key → stores in Secrets Manager

TIER 2 (needs VPC + IAM)
├── module.eks       → EKS cluster, OIDC provider, node group, CI/CD access entry
├── module.rds       → MySQL RDS (private subnets, AWS-managed password)
└── module.sonarqube → EC2 t3.small (Amazon Linux 2023, prevent_destroy=true)

TIER 3 (needs EKS OIDC provider)
├── module.alb_controller → IRSA role for ALB controller
└── module.iam_irsa       → IRSA roles for app pods + CloudWatch agent

TIER 4 (needs ECR + EKS + RDS + SQS + SNS)
├── module.ssm        → SSM params (ECR URLs, DB endpoint, queue URL, etc.)
└── module.cloudwatch → Log groups, 4 alarms, dashboard
```

### How Modules Pass Values to Each Other

```
module.vpc.vpc_id                    → module.eks, module.rds, module.sonarqube
module.vpc.private_subnet_ids        → module.eks (nodes), module.rds
module.vpc.public_subnet_ids         → module.eks (control plane), module.sonarqube
module.vpc.eks_nodes_security_group_id → module.eks (launch template)
module.vpc.rds_security_group_id     → module.rds

module.iam.eks_cluster_role_arn      → module.eks
module.iam.eks_node_role_arn         → module.eks

module.eks.oidc_provider_arn         → module.alb_controller, module.iam_irsa
module.eks.oidc_provider_url         → module.alb_controller, module.iam_irsa
module.eks.cluster_name              → module.ssm, module.cloudwatch
module.eks.node_group_asg_name       → module.cloudwatch

module.rds.db_endpoint               → module.ssm
module.rds.db_master_user_secret_arn → module.ssm, module.iam_irsa

module.s3.bucket_arn                 → module.iam_irsa
module.s3.bucket_name                → module.ssm

module.sqs.orders_queue_arn          → module.iam_irsa
module.sqs.orders_queue_url          → module.ssm
module.sqs.orders_dlq_arn            → module.iam_irsa
module.sqs.orders_dlq_name           → module.cloudwatch

module.sns.sns_topic_arn             → module.cloudwatch, module.ssm

module.secrets.jwt_signing_key_secret_arn → module.iam_irsa

module.ecr.repository_urls           → module.ssm
module.alb_controller.role_arn       → infrastructure.yml (Helm install)
module.iam_irsa.app_pod_role_arn     → ci-cd.yml (manifest rendering)
module.iam_irsa.cloudwatch_agent_role_arn → ci-cd.yml (manifest rendering)
```


### Module Detail: VPC (`modules/vpc`)

Creates the entire network foundation:

- **VPC**: `10.0.0.0/16`, DNS support + hostnames enabled (required for EKS and RDS)
- **Public subnets**: `10.0.0.0/24`, `10.0.1.0/24` across us-east-1a and us-east-1b. Tagged `kubernetes.io/role/elb=1` so ALB controller knows it can place internet-facing load balancers here
- **Private subnets**: `10.0.10.0/24`, `10.0.11.0/24`. EKS worker nodes and RDS live here — no public IPs
- **NAT Gateway**: 1 instance in a public subnet. Private subnet route tables point to it so nodes can reach the internet (for ECR pulls, AWS API calls) without having public IPs
- **Security group chain** (layered, least-privilege):

```
Internet
  │ port 80
  ▼
ALB SG          — ingress: 80 from 0.0.0.0/0; egress: all
  │ ports 80, 5001, 5002, 5003
  ▼
EKS Nodes SG    — ingress: app ports FROM ALB SG only; node-to-node (self); egress: all
  │ port 3306
  ▼
RDS SG          — ingress: 3306 FROM EKS Nodes SG only; egress: all
```

The ALB Controller webhook (port 443) is also allowed from ALB SG to EKS Nodes SG — without this, Ingress resources fail to create.

### Module Detail: EKS (`modules/eks`)

```
aws_eks_cluster         — control plane, uses cluster role from modules/iam
aws_iam_openid_connect_provider — registers the cluster's OIDC URL with AWS IAM
                                   (this is what makes IRSA possible)
aws_launch_template     — attaches OUR custom SG + cluster SG to nodes
                           sets IMDSv2 (http_tokens=required, hop_limit=2)
aws_eks_node_group      — t3.small nodes in private subnets, 2 desired/1 min/3 max
aws_eks_access_entry    — grants GitHub Actions IAM user kubectl cluster-admin
aws_eks_access_policy_association — AmazonEKSClusterAdminPolicy at cluster scope
```

`access_config { authentication_mode = "API_AND_CONFIG_MAP" }` — enables the modern Access Entries API while keeping backward compatibility with the legacy aws-auth ConfigMap.

### Module Detail: IAM-IRSA (`modules/iam-irsa`)

Two IRSA roles:

**app-pod-role** — for `library-sa` service account in `library` namespace:
- S3: GetObject, PutObject, DeleteObject on assets bucket
- SQS: SendMessage, ReceiveMessage, DeleteMessage on orders queue + DLQ
- Secrets Manager: GetSecretValue on JWT key + RDS password secret
- SSM: GetParametersByPath on `/digital-library/prod/*`
- SNS: Publish to alerts topic

**cloudwatch-agent-role** — for `cloudwatch-agent` + `fluent-bit` service accounts in `amazon-cloudwatch` namespace:
- `CloudWatchAgentServerPolicy` (AWS-managed)


---

## 3. Infrastructure Workflow

**File:** `.github/workflows/infrastructure.yml`
**Triggers:** Push/PR to `main` on `**/*.tf` or `**/*.tfvars`

### Plan Job (Pull Requests only)
```
checkout → configure AWS → setup Terraform → fmt check → init → validate → plan
→ posts plan output as PR comment (truncated to 60k chars)
```
Uses `AWS_ACCESS_KEY_ID_INFRA` / `AWS_SECRET_ACCESS_KEY_INFRA`.

### Apply Job (Push to main)
```
checkout → configure AWS → setup Terraform → init → validate → apply
→ aws eks update-kubeconfig
→ helm upgrade --install aws-load-balancer-controller
    (reads vpc_id + alb_controller_role_arn from terraform output)
→ kubectl rollout status (verify controller running)
```

The ALB Controller is installed via Helm after every `terraform apply` — `--install` creates it if missing, `upgrade` updates it if already there. This is idempotent.

---

## 4. CI/CD Pipeline

**File:** `.github/workflows/ci-cd.yml`
**Triggers:** Push to `main` on `app/**` or `k8s/**`

### Job 1: test

```
checkout (fetch-depth: 0)    ← full history for SonarQube git blame
├── setup Node 20 + Python 3.11
├── npm install + npm run build (Vite)
├── pip install all 4 services' requirements
├── SonarQube scan (if SONAR_HOST_URL + SONAR_TOKEN set)
│     sonarqube-scan-action@v5 → sends code to EC2 SonarQube
├── SonarQube quality gate check → blocks if gate fails
├── python -m compileall (syntax validation)
└── run tests (placeholder)
```

`sonar-project.properties` configures:
- Project key: `digital-library`
- Sources: `app/`
- Excludes: node_modules, dist, __pycache__, database/
- `sonar.qualitygate.wait=true` — pipeline blocks until analysis finishes

### Job 2: build-push (matrix, 5 parallel)

For each service (auth, book, borrow, frontend, worker):
```
configure AWS → ecr-login → docker buildx setup
→ build and push
    tags: :latest AND :<git-sha>
    cache: registry cache (--cache-from / --cache-to)
→ trivy scan (HIGH+CRITICAL, exit-code 0 = non-blocking)
```

### Job 3: deploy

```
configure AWS → update kubeconfig → pre-flight validation
→ RENDER MANIFESTS (Python script)
    Substitutes in all k8s/*.yaml:
      ${K8S_NAMESPACE}              → value from secret (default: library)
      ${APP_POD_ROLE_ARN}           → arn:aws:iam::393323650493:role/...-app-pod-role
      ${CLOUDWATCH_AGENT_ROLE_ARN}  → arn:aws:iam::393323650493:role/...-cloudwatch-agent-role
      ${ALB_SECURITY_GROUP_ID}      → sg-02591f5bac92ce376
    Writes rendered files to /tmp/rendered-k8s/

→ kubectl apply (base): namespace, serviceaccount, configmap, cloudwatch daemonset
→ kubectl apply (services): 5 deployments, ingress, HPA
→ kubectl set image (5 deployments) ← pins :latest to :<git-sha>
→ kubectl rollout status (all 5, 180s timeout each)
→ smoke test: curl ALB DNS /auth/health, /books/health, /borrow/health (5 retries × 15s)
→ SNS notify success or failure
```

**Why render manifests in the pipeline?** The YAML files in source contain `${PLACEHOLDER}` variables. Real IAM role ARNs, security group IDs, and namespaces are injected at deploy time. This keeps no live AWS-account-specific values hardcoded in source.

**Why pin to git SHA after applying?** Applying with `:latest` ensures the manifest is accepted even on the first deploy. Immediately after, `kubectl set image` replaces it with the exact SHA tag — giving reproducible, auditable deployments where you can always trace which commit is running.


---

## 5. Kubernetes Manifests

All manifests live in `k8s/` and use `${PLACEHOLDER}` syntax rendered by the deploy job.

### namespace.yaml
Creates the `library` namespace with label `app: digital-library`.

### serviceaccount.yaml
```yaml
metadata:
  name: library-sa
  annotations:
    eks.amazonaws.com/role-arn: "${APP_POD_ROLE_ARN}"
```
This annotation is what links the Kubernetes service account to the AWS IAM role. The EKS OIDC provider exchanges the pod's projected service account token for temporary AWS credentials scoped to that role — no static keys anywhere.

### configmap.yaml
Injects only two environment variables into every pod:
```
AWS_SSM_PATH = /digital-library/prod/config
AWS_REGION   = us-east-1
```
All other config (DB host, SQS URL, SNS ARN, S3 bucket) is fetched by `secrets.py` from SSM at pod startup. DB password comes from Secrets Manager via the ARN stored in SSM.

### ingress.yaml
```yaml
annotations:
  kubernetes.io/ingress.class: alb
  alb.ingress.kubernetes.io/scheme: internet-facing
  alb.ingress.kubernetes.io/target-type: ip      ← direct pod IP, not NodePort
  alb.ingress.kubernetes.io/security-groups: sg-02591f5bac92ce376
```
Path routing order matters — `/auth`, `/books`, `/borrow` before `/` (catch-all for frontend). `target-type: ip` means the ALB talks directly to pod IPs using the VPC CNI plugin, bypassing NodePort entirely.

### Deployments (auth, book, borrow, frontend, worker)

All service deployments share the same pattern:
```yaml
spec:
  serviceAccountName: library-sa    ← gets IRSA credentials
  containers:
    envFrom:
      - configMapRef:
          name: library-config      ← gets AWS_SSM_PATH + AWS_REGION
    livenessProbe:  httpGet /health  ← kills pod if health check fails
    readinessProbe: httpGet /health  ← removes pod from LB until ready
    resources:
      requests: cpu=100m, memory=128Mi
      limits:   cpu=500m, memory=256Mi
```

**Worker** is different — no HTTP port, liveness is `exec: python -c "import boto3"`.

Each deployment has a paired `ClusterIP` Service. ClusterIP means the service is only reachable inside the cluster — the ALB talks to pod IPs directly (ip mode), not through the service.

### hpa.yaml
HPA for auth, book, borrow (not worker, not frontend):
- Min: 1 replica, Max: 4 replicas
- Scale up when average CPU > 70%
- Requires `metrics-server` to be installed in the cluster

### cloudwatch-daemonset-observability.yaml
DaemonSet = runs one pod on **every** node automatically:

**CloudWatch Agent** — collects pod/node CPU, memory, disk metrics, ships to CloudWatch
**Fluent Bit** — tails `/var/log/containers/*.log`, filters by kubernetes metadata, ships to CloudWatch Log Groups:
- App logs → `/digital-library/prod/application`
- Worker logs → `/digital-library/prod/worker`

Both use IRSA via the `cloudwatch-agent-role`.


---

## 6. Application Services

### Auth Service — `app/auth/auth_service.py` (Flask, port 5001)

| Endpoint | Method | What it does |
|---|---|---|
| `/auth/signup` | POST | bcrypt hash password, insert user, return 201 |
| `/auth/signin` | POST | bcrypt verify, return user_id + name |
| `/auth/health` | GET | test DB connection, return 200/500 |

Reads DB config from SSM via `load_config()` at startup. Raises `Error` if DB unreachable.

### Book Service — `app/book/book_service.py` (Flask, port 5002)

| Endpoint | Method | What it does |
|---|---|---|
| `/books` | GET | SELECT * FROM books |
| `/books/<id>` | GET | SELECT single book |
| `/books` | POST | INSERT book, publish `new_book_added` to SQS |
| `/books/import` | POST | Accept CSV upload, queue each row as `bulk_book_import` SQS message |
| `/books/health` | GET | 200 OK |

**Bulk import flow:** CSV arrives → each row → SQS message → worker inserts to RDS. Returns `202 Accepted` immediately. No DB timeout risk on large files.

### Borrow Service — `app/borrow/borrow_service.py` (Flask, port 5003)

| Endpoint | Method | What it does |
|---|---|---|
| `/borrow` | POST | Check book exists, check not already borrowed, insert borrow_record, publish `borrow_confirmation` to SQS |
| `/borrow/mybooks/<user_id>` | GET | JOIN borrow_records + books, return list |
| `/borrow/health` | GET | 200 OK |

### Worker — `app/worker/worker.py` (no HTTP, SQS consumer)

```
while True:
  sqs.receive_message(WaitTimeSeconds=20, MaxNumberOfMessages=10, VisibilityTimeout=60)
  for each message:
    try:
      route to handler by event_type
      sqs.delete_message()     ← only on success
    except:
      don't delete → SQS retries after 60s
      after maxReceiveCount failures → DLQ
```

| event_type | Handler |
|---|---|
| `borrow_confirmation` | SNS.publish (confirmation email to user) |
| `new_book_added` | SNS.publish (broadcast to all subscribers) |
| `bulk_book_import` | INSERT IGNORE INTO books (RDS direct write) |

### Frontend — `app/frontend/src/App.jsx` (React 18 + Vite)

- `API_URL = ""` — all fetch calls use relative paths (`/auth/signin`, `/books`, `/borrow`)
- Nginx in the container proxies these to the backend services via the ALB DNS
- State: `useState` for form data, `localStorage` for session persistence
- Two views: Auth form (sign in / sign up) and Dashboard (browse books, borrow, view borrowed)

---

## 7. Security — IRSA Explained

**IRSA = IAM Roles for Service Accounts**

The problem IRSA solves: how do pods call AWS APIs (S3, SQS, Secrets Manager) without hardcoding AWS credentials into the Docker image or environment variables?

**How it works:**
```
1. EKS registers an OIDC provider with AWS IAM
   (URL: https://oidc.eks.us-east-1.amazonaws.com/id/XXXX)

2. Terraform creates an IAM role with a trust policy:
   "Trust tokens from THIS OIDC provider WHERE the token claims
    sub = system:serviceaccount:library:library-sa"
   This scopes the role to ONE specific Kubernetes service account

3. The Kubernetes ServiceAccount gets an annotation:
   eks.amazonaws.com/role-arn: arn:aws:iam::393323650493:role/...-app-pod-role

4. When a pod starts using that ServiceAccount:
   - EKS injects a projected service account token (a JWT)
   - The pod's AWS SDK calls STS with that JWT
   - STS verifies the JWT against the OIDC provider
   - STS returns temporary credentials (15 min expiry, auto-renewed)
   - The pod calls S3/SQS/Secrets Manager with those credentials
```

**Result:** No static keys anywhere. If a pod is compromised, the blast radius is scoped to exactly the resources that role can access.

Three IRSA roles in this project:
1. `app-pod-role` — used by `library-sa` (all 5 app pods)
2. `alb-controller-role` — used by `aws-load-balancer-controller` in kube-system
3. `cloudwatch-agent-role` — used by `cloudwatch-agent` and `fluent-bit` in amazon-cloudwatch


---

## 8. Observability

### CloudWatch Alarms (4 total)

| Alarm | Metric | Threshold | Action |
|---|---|---|---|
| `eks-node-cpu-high` | EC2 CPUUtilization (ASG) | > 80% for 10 min | SNS email |
| `rds-cpu-high` | RDS CPUUtilization | > 80% for 10 min | SNS email |
| `rds-storage-low` | RDS FreeStorageSpace | < 5 GB | SNS email |
| `sqs-dlq-not-empty` | SQS ApproximateNumberOfMessagesVisible | > 0 | SNS email |

The DLQ alarm threshold is 0 — any message in the DLQ means something failed 3 times and needs investigation. There is no acceptable non-zero DLQ depth.

### CloudWatch Dashboard

Single pane of glass at `digital-library-prod`:
- EKS node CPU (time series, 5 min intervals)
- RDS CPU (time series)
- SQS queue depth — both orders queue and DLQ
- RDS free storage
- All 4 alarm statuses
- Live application logs (last 20 min, cross-log-group query)

### Log Groups

Terraform pre-creates (with retention):
- `/digital-library/prod/auth`
- `/digital-library/prod/book`
- `/digital-library/prod/borrow`
- `/digital-library/prod/worker`
- `/digital-library/prod/frontend`

Fluent Bit ships container logs into `/digital-library/prod/application` and `/digital-library/prod/worker`.

---

## 9. End-to-End Request Flow

### User signs in and borrows a book

```
1. Browser → ALB:80 → frontend-service:80 (React SPA)

2. React fetch POST /auth/signin
   → ALB routes to auth-service:5001
   → auth-service checks SSM for DB config (cached at startup)
   → auth-service calls Secrets Manager for DB password (via IRSA)
   → MySQL query on RDS (private subnet, port 3306)
   → return { user_id, name }

3. React fetch POST /borrow { user_id, book_id }
   → ALB routes to borrow-service:5003
   → borrow-service queries RDS: book exists? already borrowed?
   → INSERT INTO borrow_records
   → SQS.send_message({ event_type: "borrow_confirmation", ... })
   → return 201

4. Worker pod (long-polling SQS)
   → receives borrow_confirmation message
   → SNS.publish (email to subscribed addresses)
   → SQS.delete_message (success)
```

### Developer pushes a code change

```
1. git push → GitHub Actions triggers ci-cd.yml
2. test job: install deps → build React → SonarQube scan → quality gate → Python syntax check
3. build-push job (×5 parallel): docker build → push :latest + :<sha> → Trivy scan
4. deploy job:
   a. aws eks update-kubeconfig (authenticates kubectl)
   b. kubectl cluster-info + auth can-i (preflight)
   c. Python script renders k8s/*.yaml → /tmp/rendered-k8s/
   d. kubectl apply base manifests
   e. kubectl apply service manifests
   f. kubectl set image (pins to :<sha>)
   g. kubectl rollout status (waits for pods to be ready)
   h. curl ALB /health endpoints (smoke test)
   i. SNS.publish success/failure notification
```

---

## 10. Key Design Decisions

**1. IRSA over static credentials**
No `AWS_ACCESS_KEY_ID` in any pod. Service accounts get scoped temporary credentials via the OIDC token exchange. If credentials leak, blast radius is one role's permissions, not the whole account.

**2. SSM as the config bus**
Pods start with only `AWS_SSM_PATH` + `AWS_REGION`. Everything else is fetched from SSM at boot. This means config changes (new DB endpoint, new queue URL) don't require rebuilding Docker images.

**3. RDS password never in Terraform state**
`manage_master_user_password = true` delegates the secret entirely to AWS. The password is never in `terraform.tfstate`, never in environment variables, never in code.

**4. SQS decouples writes from HTTP responses**
Borrow confirmation emails, new-book notifications, and bulk CSV imports are all queued. The Flask APIs respond immediately after the DB write. The worker handles the slow parts asynchronously. If the worker crashes, messages stay in SQS until it restarts.

**5. DLQ for failure isolation**
Failed messages retry up to `maxReceiveCount` times, then go to the DLQ. A CloudWatch alarm fires the moment anything lands in the DLQ. This prevents silent message loss.

**6. Manifest templating over hardcoded values**
`k8s/*.yaml` files use `${PLACEHOLDER}` syntax. The deploy job's Python script substitutes real values at deploy time. No live ARNs, account IDs, or security group IDs are hardcoded in source.

**7. Image tags pinned to git SHA**
After `kubectl apply` (which uses `:latest`), the pipeline immediately runs `kubectl set image` with the exact SHA tag. Every running pod can be traced back to the exact commit that built it.

**8. `prevent_destroy = true` on SonarQube**
SonarQube EC2 has `lifecycle { prevent_destroy = true; ignore_changes = [ami, user_data] }`. This stops `terraform apply` from terminating and recreating the instance (which would change the public IP and break the `SONAR_HOST_URL` GitHub secret).


---

## 11. Interview Q&A

### "Walk me through what happens when you push a code change."
> A push to main on `app/**` triggers `ci-cd.yml`. First the `test` job runs — it builds the React frontend, installs Python deps, runs a SonarQube scan, and checks the quality gate. If that passes, 5 Docker builds run in parallel via a matrix strategy, each pushing two tags to ECR — `:latest` and the git SHA. Trivy scans each image for vulnerabilities. Then the `deploy` job runs — it authenticates kubectl to EKS, renders the Kubernetes manifests using a Python script that substitutes real values for placeholders, applies them with kubectl, then immediately pins image tags to the git SHA so we know exactly which commit is running. Finally it smoke tests the health endpoints via the ALB.

### "What is IRSA and why use it?"
> IRSA is IAM Roles for Service Accounts. EKS registers an OIDC provider with AWS IAM. We create IAM roles whose trust policy says "only trust tokens from this OIDC provider for this specific Kubernetes service account." When a pod starts, EKS injects a projected JWT token. The pod's AWS SDK exchanges that token with STS for temporary credentials. The result is pods can call S3, SQS, Secrets Manager without any static access keys anywhere in the image or environment.

### "Why SQS between the borrow service and the worker?"
> The borrow HTTP endpoint needs to respond fast. Sending an email via SNS, or doing a bulk DB insert, could take seconds. Putting those operations in SQS means the API returns 201 immediately after the DB write. The worker picks up the job asynchronously. If the worker crashes, the message stays in SQS and gets retried. After 3 failures it goes to the DLQ and we get a CloudWatch alarm. None of this would be possible if we did it synchronously in the HTTP handler.

### "How does the ALB know which pod to send traffic to?"
> The ALB is created by the AWS Load Balancer Controller, which watches for Kubernetes Ingress resources. When you apply `ingress.yaml`, the controller reads the annotations and creates an AWS ALB. Because we use `target-type: ip` mode, the ALB talks directly to pod IPs using the VPC CNI plugin — every pod gets a real VPC IP. There's no NodePort or kube-proxy in the traffic path.

### "How is the DB password managed?"
> We use `manage_master_user_password = true` on the RDS resource. AWS creates and manages the secret entirely — it never touches Terraform state, never appears in environment variables, never appears in application code. At runtime, `secrets.py` reads the secret ARN from SSM, then calls Secrets Manager to get the actual password using the pod's IRSA credentials.

### "What's the difference between the two GitHub Actions workflows?"
> `infrastructure.yml` manages the AWS infrastructure itself — it runs Terraform. It triggers on `.tf` file changes and after applying infrastructure it installs the ALB controller via Helm. `ci-cd.yml` manages application deployments — it triggers on `app/` or `k8s/` changes, builds Docker images, scans them, and deploys to EKS. They use different IAM credentials. Infrastructure changes and application changes are deliberately separated.

### "Why does the SonarQube instance have `prevent_destroy = true`?"
> Every time `terraform apply` runs, Terraform evaluates whether the instance needs to be replaced. If the AMI changes, or the user_data changes, Terraform would destroy and recreate the instance — giving it a new public IP. That breaks the `SONAR_HOST_URL` GitHub secret. `prevent_destroy = true` makes Terraform refuse to destroy the instance, and `ignore_changes = [ami, user_data]` stops AMI updates from triggering a replacement.

### "How do you handle secrets in the application?"
> Three layers: (1) SSM Parameter Store holds non-secret config like DB hostname, queue URL, S3 bucket name. (2) AWS Secrets Manager holds actual secrets — the JWT signing key and the RDS master password. (3) The app never stores either. At startup, `secrets.py` reads `AWS_SSM_PATH` from the ConfigMap, fetches all parameters under that path from SSM, then calls Secrets Manager for the DB password using the ARN it got from SSM. The IRSA role grants the pod permission to do exactly this — nothing more.

### "What monitoring is in place?"
> Four CloudWatch alarms: EKS node CPU, RDS CPU, RDS free storage, and SQS DLQ depth. All fire to an SNS topic which emails the configured addresses. There's also a CloudWatch dashboard with time-series graphs for all metrics plus a live log query across all service log groups. Fluent Bit ships container logs to CloudWatch, and the CloudWatch agent collects node-level metrics.

### "What happens if a deployment fails?"
> The deploy job's `kubectl rollout status` step waits up to 180 seconds for each deployment. If a rollout fails — for example a pod can't pull the image or health checks fail — the step exits with an error. The SNS "failed" notification fires automatically via `if: failure()`. Kubernetes keeps the previous ReplicaSet running, so the old version stays live. The failed deployment can be investigated with `kubectl describe pod` and the logs in CloudWatch.

---

*Generated from actual project files — `main.tf`, `modules/*`, `k8s/*.yaml`, `app/*/`, `.github/workflows/*.yml`*
