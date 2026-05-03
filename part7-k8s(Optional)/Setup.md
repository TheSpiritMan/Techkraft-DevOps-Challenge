# Part 7: Kubernetes Deployment — TechKraft Backend

## Directory Structure

```
part7-k8s/
├── Manifest-Files/
│   ├── ns.yaml          ← Namespace: techkraft
│   ├── cm.yaml          ← ConfigMap: non-sensitive env vars
│   ├── secrets.yaml     ← Secret: DB_USER, DB_PASS (base64)
│   ├── deployment.yaml  ← Deployment: pods, probes, security, volumes
│   ├── service.yaml     ← Service: ClusterIP, port 80 → 5000
│   ├── hpa.yaml         ← HorizontalPodAutoscaler: CPU + memory scaling
│   └── pdb.yaml         ← PodDisruptionBudget: HA during node drains (optional)
└── Setup.md             ← This file
```

---

## Prerequisites

| Requirement | Version | Verify |
|---|---|---|
| kubectl | >= v1.34.1 | `kubectl version --client` |
| Kubernetes cluster | >= v1.34.1 | `kubectl version` |
| Docker | >= 24 | `docker --version` |
| metrics-server | installed | `kubectl top pods -n techkraft` |

> **metrics-server is required for HPA to work.** Without it, HPA shows
> `<unknown>` for CPU and memory targets and never scales.
---

## Architecture Overview

```
                ┌──────────────────────────────────────────┐
                │           Namespace: techkraft            │
                │                                          │
                │  ┌────────────────────────────────────┐  │
                │  │           Deployment               │  │
                │  │      backend (2–10 replicas)       │  │
                │  │                                    │  │
                │  │   Pod (AZ-a)       Pod (AZ-b)      │  │
                │  │  ┌──────────┐    ┌──────────┐     │  │
                │  │  │ backend  │    │ backend  │     │  │
                │  │  │  :5000   │    │  :5000   │     │  │
                │  │  │          │    │          │     │  │
                │  │  │ DB_USER ←┤    ├─ Secret  │     │  │
                │  │  │ DB_PASS ←┤    ├─ Secret  │     │  │
                │  │  │ PORT    ←┤    ├─ ConfigMap│    │  │
                │  │  └──────────┘    └──────────┘     │  │
                │  └────────────────┬───────────────────┘  │
                │                   │ selector: app=backend │
                │  ┌────────────────▼───────────────────┐  │
                │  │         Service: ClusterIP          │  │
                │  │      port 80 → containerPort 5000  │  │
                │  └────────────────────────────────────┘  │
                │                                          │
                │  ┌────────────────────────────────────┐  │
                │  │  HPA: min 2 / max 10 replicas      │  │
                │  │  CPU > 60%  →  scale up            │  │
                │  │  MEM > 70%  →  scale up            │  │
                │  └────────────────────────────────────┘  │
                │                                          │
                │  ┌────────────────────────────────────┐  │
                │  │  PDB: minAvailable 1  (optional)   │  │
                │  │  protects during node drains       │  │
                │  └────────────────────────────────────┘  │
                └──────────────────────────────────────────┘
```

---

## Step 1 — Build and Push the Docker Image

The deployment uses image `thespiritman/techkraft-flask-api:prod` from
Docker Hub. Build and push from the `/part2-linux/part2B-Dockerization/` directory:

```bash
# Build
docker build -t thespiritman/techkraft-flask-api:prod ../part2-linux/part2B-Dockerization/

# Log in to Docker Hub
docker login

# Push
docker push thespiritman/techkraft-flask-api:prod
```

Verify the image is publicly accessible:

```bash
docker pull thespiritman/techkraft-flask-api:prod
```

> **Production note:** Pin to a digest instead of a mutable tag to guarantee
> the exact image is always deployed:
> ```bash
> docker inspect --format='{{index .RepoDigests 0}}' thespiritman/techkraft-flask-api:prod
> # Then update deployment.yaml:
> # image: thespiritman/techkraft-flask-api@sha256:<digest>
> ```

---

## Step 2 — Understand the Secrets

`secrets.yaml` contains base64-encoded database credentials injected into
pods as environment variables `DB_USER` and `DB_PASS`.

Current values:

| Secret Key | Base64 Value | Decoded | Env Var |
|---|---|---|---|
| `db-user` | `cm9vdA==` | `root` | `DB_USER` |
| `db-pass` | `c2VjdXJlcGFzc3dvcmQ=` | `securepassword` | `DB_PASS` |

These are exposed by `app.py` at the `/secret` endpoint via `os.environ.get()`.

To encode custom values:

```bash
echo -n "your-username" | base64
echo -n "your-password" | base64
```

Replace the values in `secrets.yaml` before applying.

> **Never commit real production credentials to Git.**
> For production, sync directly from AWS Secrets Manager using the
> External Secrets Operator instead of maintaining base64 values manually.

---

## Step 3 — Apply Manifests

Apply in dependency order — namespace first, then config, then workload:

```bash
# 1. Namespace — must exist before any other resource
kubectl apply -f Manifest-Files/ns.yaml

# 2. ConfigMap and Secret — must exist before Deployment references them
kubectl apply -f Manifest-Files/cm.yaml
kubectl apply -f Manifest-Files/secrets.yaml

# 3. Deployment
kubectl apply -f Manifest-Files/deployment.yaml

# 4. Service
kubectl apply -f Manifest-Files/service.yaml

# 5. HPA
kubectl apply -f Manifest-Files/hpa.yaml

# 6. PDB (optional — uncomment pdb.yaml contents first)
kubectl apply -f Manifest-Files/pdb.yaml
```

Or apply the entire directory at once:

```bash
kubectl apply -f Manifest-Files/
```

---

## Step 4 — Verify the Deployment

```bash
# Check all resources in the namespace
kubectl get all -n techkraft
```

Expected output:

```
NAME                           READY   STATUS    RESTARTS   AGE
pod/backend-7f7cc86b6b-2qzhh   0/1     Running   0          15s
pod/backend-7f7cc86b6b-cbzx4   1/1     Running   0          15s

NAME              TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)   AGE
service/backend   ClusterIP   10.43.127.7   <none>        80/TCP    22s

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/backend   1/2     2            1           15s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/backend-7f7cc86b6b   2         2         1       15s

NAME                                          REFERENCE            TARGETS                        MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/backend   Deployment/backend   cpu: 1%/60%, memory: 39%/70%   2         10        2          83s
```

Additional checks:

```bash
# Watch pods start up in real time
kubectl get pods -n techkraft -w

# Check pod events and probe status
kubectl describe pod -n techkraft -l app=backend

# Confirm secrets are injected correctly
kubectl exec -n techkraft deploy/backend -- env | grep DB
# DB_USER=root
# DB_PASS=securepassword

# Confirm ConfigMap values are injected
kubectl exec -n techkraft deploy/backend -- env | grep -E "PORT|LOG_LEVEL|APP_VERSION"

# Stream logs from all backend pods
kubectl logs -n techkraft -l app=backend -f

# Check HPA is receiving metrics (requires metrics-server)
kubectl get hpa -n techkraft

# Check PDB (if enabled)
kubectl get pdb -n techkraft
```

---

## Step 5 — Test the Application

```bash
# Port-forward the Service to your local machine
kubectl port-forward -n techkraft svc/backend 8080:80
```

In a separate terminal:

```bash
# Root endpoint
curl http://localhost:8080/
# {"message": "TechKraft API v1.0"}

# Health check — used by liveness and readiness probes
curl http://localhost:8080/health
# {"status": "healthy"}

# Secret endpoint — reads DB_USER and DB_PASS from Kubernetes Secret
curl http://localhost:8080/secret
# {"db_pass": "securepassword", "db_user": "root"}
```

Test connectivity from inside the cluster:

```bash
kubectl run -it --rm debug \
  --image=alpine \
  --namespace=techkraft \
  -- sh -c "apk add --no-cache curl && curl http://backend/health"
```

---

## Manifest Reference

### ns.yaml: Namespace

Creates the `techkraft` namespace to isolate all resources from other
workloads running in the same cluster.

```bash
kubectl get namespace techkraft
```

### cm.yaml: ConfigMap

Non-sensitive configuration injected into every pod as environment variables:

| Key | Value | Purpose |
|---|---|---|
| `FLASK_ENV` | `production` | Flask runtime mode |
| `PORT` | `5000` | Port gunicorn listens on |
| `LOG_LEVEL` | `INFO` | Application log verbosity |
| `APP_VERSION` | `1.0.0` | Version label visible in logs |

```bash
kubectl describe configmap backend-config -n techkraft
```

### secrets.yaml: Secret

Sensitive credentials injected as environment variables. Kubernetes decodes
the base64 values before passing them to the container.

| Secret Key | Env Var | Current Value |
|---|---|---|
| `db-user` | `DB_USER` | `root` |
| `db-pass` | `DB_PASS` | `securepassword` |

```bash
# List secret keys without revealing values
kubectl get secret backend-secrets -n techkraft -o jsonpath='{.data}' | python3 -c \
  "import sys,json; [print(k) for k in json.load(sys.stdin)]"
```

### deployment.yaml: Deployment

Key design decisions:

| Feature | Setting | Reason |
|---|---|---|
| Image | `thespiritman/techkraft-flask-api:prod` | Docker Hub public image |
| Replicas | 2 minimum | No SPOF, one pod per AZ |
| Strategy | RollingUpdate, maxUnavailable: 0 | Zero-downtime deploys |
| Non-root user | uid 1001 | Container escape mitigation |
| Read-only filesystem | `readOnlyRootFilesystem: true` | Prevent runtime tampering |
| Writable volumes | `/tmp`, `/var/run`, `/home/appuser` | Required by gunicorn at runtime |
| Liveness probe | `GET /health` every 20s | Restart deadlocked containers |
| Readiness probe | `GET /health` every 10s | Remove unready pods from Service |
| Startup probe | `GET /health` up to 60s | Allow slow start without false restarts |
| Topology spread | hostname + zone | Pods distributed across nodes and AZs |
| CPU request / limit | 100m / 500m | Guaranteed slice, burstable up to 0.5 core |
| Memory request / limit | 128Mi / 256Mi | OOM killed before affecting other pods |

> **Why three writable volume mounts?**
> `readOnlyRootFilesystem: true` blocks all writes to the container
> filesystem. gunicorn needs three writable locations at runtime:
>
> | Mount | Path | Purpose |
> |---|---|---|
> | `tmp` | `/tmp` | Worker heartbeat files (`--worker-tmp-dir`) |
> | `var-run` | `/var/run` | Master process PID file |
> | `home` | `/home/appuser` | `.gunicorn/` control socket |
>
> All three are `emptyDir` volumes — ephemeral and cleaned up automatically
> when the pod terminates.

```bash
kubectl rollout status deployment/backend -n techkraft
```

### service.yaml: Service

ClusterIP Service provides a stable internal DNS name (`backend.techkraft.svc.cluster.local`)
and load balances traffic across all ready pods. Port 80 on the Service maps
to containerPort 5000 on the pod.

Since this service is for Internal Connection only, we have to expose externally via an Ingress controller or AWS Load
Balancer Controller.

```bash
# Verify endpoints are registered (one entry per healthy pod)
kubectl get endpoints backend -n techkraft
```

### hpa.yaml: HorizontalPodAutoscaler

Automatically scales the Deployment between 2 and 10 replicas:

| Metric | Threshold | Scale-up behaviour |
|---|---|---|
| CPU utilization | > 60% average | Add up to 2 pods per minute |
| Memory utilization | > 70% average | Add up to 2 pods per minute |
| Scale-down cooldown | — | Remove 1 pod per 2 minutes after 5 min stable |

```bash
# Watch HPA decisions in real time
kubectl get hpa backend -n techkraft -w
```

### pdb.yaml: PodDisruptionBudget (Optional)

Currently commented out in `pdb.yaml`. When enabled, guarantees at least
1 pod stays running during voluntary disruptions like `kubectl drain`,
cluster upgrades, or node pool replacements. Prevents Kubernetes from
evicting all pods simultaneously.

To enable:

```bash
# Uncomment the contents of pdb.yaml, then:
kubectl apply -f Manifest-Files/pdb.yaml
kubectl get pdb -n techkraft
```

---

## Rolling Update: Deploy a New Image Version

```bash
# Update to a new image tag or digest
kubectl set image deployment/backend \
  backend=thespiritman/techkraft-flask-api:prod \
  -n techkraft

# Watch the rollout
kubectl rollout status deployment/backend -n techkraft

# Rollback immediately if something is wrong
kubectl rollout undo deployment/backend -n techkraft

# View rollout history
kubectl rollout history deployment/backend -n techkraft
```

---

## Teardown

```bash
# Remove all manifests
kubectl delete -f Manifest-Files/

# Or delete the entire namespace (removes everything inside it)
kubectl delete namespace techkraft
```

---

## Troubleshooting

| Symptom | Command | Likely Cause |
|---|---|---|
| Pods stuck in `Pending` | `kubectl describe pod -n techkraft <pod>` | Insufficient node resources or nodeSelector mismatch |
| `CrashLoopBackOff` | `kubectl logs -n techkraft <pod> --previous` | App crash, missing secret key, bad env var |
| HPA shows `<unknown>` targets | `kubectl top pods -n techkraft` | metrics-server not installed or not ready |
| Readiness probe failing | `kubectl describe pod -n techkraft <pod>` | App not responding on `/health` or wrong port |
| `Read-only file system` error | Check volumeMounts in deployment.yaml | Missing emptyDir for `/home/appuser`, `/tmp`, or `/var/run` |
| `ImagePullBackOff` | `kubectl describe pod -n techkraft <pod>` | Image name wrong or registry unauthenticated |
| Secret env vars empty | `kubectl exec -n techkraft deploy/backend -- env \| grep DB` | Wrong key name in secretKeyRef or bad base64 |