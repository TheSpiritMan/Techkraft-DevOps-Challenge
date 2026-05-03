# Part 6: CI/CD Pipeline Review

## Problems with the Current Pipeline

### Problem 1: No Environment Separation: Direct Deploy to Production
```yaml
- name: Deploy to server
  run: |
    echo "Deploying..."
    # Direct rsync to server - no approval, no rollback
```
Every push to `main` immediately deploys to production servers via rsync. There is no staging environment, no QA gate, and no human review step. A broken commit merging at 4pm on a Friday goes straight to prod.

### Problem 2: No Security Scanning
Dependencies, container images, and code are never scanned for vulnerabilities. A compromised PyPI package (supply chain attack) or a critical CVE in a dependency would be deployed silently.

### Problem 3: No Secrets Management: Credentials Are Likely in Env or Hardcoded
The rsync deploy presumably needs SSH credentials or server access. There's no evidence of secure secret injection. Credentials may be stored as unencrypted GitHub Secrets with no rotation policy, or worse, hardcoded.

### Problem 4: No Rollback Mechanism
Once deployed, there is no way to revert. If `pytest` passes but the app crashes in production (environment-specific bug, migration failure, config difference), we must manually re-deploy the previous version. Downtime is guaranteed during incident resolution.

### Problem 5: Tests Run Without Caching: Slow Feedback Loop
```yaml
- run: pip install -r requirements.txt
```
Dependencies are reinstalled from scratch on every pipeline run, even when `requirements.txt` hasn't changed. This adds 2–5 minutes of unnecessary wait time per run.

### Problem 6: Single-Stage Testing: No Integration or Smoke Tests
Only `pytest` unit tests run. There are no integration tests (does the app connect to the real DB?), no smoke tests post-deploy (is the `/health` endpoint responding?), and no load or performance regression checks.

---

## Proposed Production-Ready CI/CD Pipeline

```yaml
name: CI/CD — Backend Services

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
  workflow_dispatch:

env:
  PYTHON_VERSION: "3.11"
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}/backend

jobs:
  # ─────────────────────────────────────────────────────────
  # Stage 1: Security & Quality Checks (runs on every PR/push)
  # ─────────────────────────────────────────────────────────
  security-scan:
    name: Security Scanning
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - name: Dependency vulnerability scan (pip-audit)
        run: |
          pip install pip-audit
          pip-audit -r requirements.txt --fail-on-vuln

      - name: SAST — static analysis (bandit)
        run: |
          pip install bandit
          bandit -r . -ll --exclude ./tests

      - name: Secret detection (truffleHog)
        uses: trufflesecurity/trufflehog@main
        with:
          path: ./
          base: ${{ github.event.repository.default_branch }}

      - name: Container image scan (Trivy)
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: fs
          severity: CRITICAL,HIGH
          exit-code: 1

  # ─────────────────────────────────────────────────────────
  # Stage 2: Test Suite
  # ─────────────────────────────────────────────────────────
  test:
    name: Tests
    runs-on: ubuntu-latest
    needs: security-scan

    services:
      mysql:
        image: mysql:8.0
        env:
          MYSQL_ROOT_PASSWORD: testpass
          MYSQL_DATABASE: techkraft_test
        ports: ["3306:3306"]
        options: --health-cmd="mysqladmin ping" --health-interval=10s

    steps:
      - uses: actions/checkout@v6

      - uses: actions/setup-python@v6
        with:
          python-version: ${{ env.PYTHON_VERSION }}
          cache: pip          # ← Cache pip dependencies

      - name: Install dependencies
        run: pip install -r requirements.txt -r requirements-dev.txt

      - name: Unit tests with coverage
        run: |
          pytest tests/unit/ \
            --cov=app \
            --cov-report=xml \
            --cov-fail-under=80 \
            -v

      - name: Integration tests
        env:
          DATABASE_URL: mysql://root:testpass@localhost:3306/techkraft_test
        run: pytest tests/integration/ -v

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v5

  # ─────────────────────────────────────────────────────────
  # Stage 3: Build and push Docker image
  # ─────────────────────────────────────────────────────────
  build:
    name: Build Docker Image
    runs-on: ubuntu-latest
    needs: test
    outputs:
      image-tag: ${{ steps.meta.outputs.tags }}
      image-digest: ${{ steps.build.outputs.digest }}

    steps:
      - uses: actions/checkout@v6

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract image metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=sha,prefix=sha-
            type=ref,event=branch
            type=semver,pattern={{version}}

      - name: Build and push with provenance
        id: build
        uses: docker/build-push-action@v5
        with:
          context: .
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          provenance: true
          sbom: true           # Generate software bill of materials

  # ─────────────────────────────────────────────────────────
  # Stage 4: Deploy to STAGING (auto, on every merge to main)
  # ─────────────────────────────────────────────────────────
  deploy-staging:
    name: Deploy → Staging
    runs-on: ubuntu-latest
    needs: build
    if: github.ref == 'refs/heads/main'
    environment:
      name: staging
      url: https://staging.techkraft.com

    steps:
      - uses: actions/checkout@v6

      - name: Configure AWS credentials (OIDC — no long-lived keys)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/GHA-Deploy-Staging
          aws-region: us-east-1

      - name: Deploy to staging ECS
        run: |
          aws ecs update-service \
            --cluster techkraft-staging \
            --service backend \
            --force-new-deployment \
            --task-definition "backend:$(aws ecs register-task-definition \
              --family backend \
              --container-definitions "[{\"image\":\"${{ needs.build.outputs.image-tag }}\"}]" \
              --query 'taskDefinition.revision' --output text)"

      - name: Wait for deployment to stabilize
        run: |
          aws ecs wait services-stable \
            --cluster techkraft-staging \
            --services backend

      - name: Smoke test staging
        run: |
          sleep 10
          curl --fail --retry 3 --retry-delay 5 \
            https://staging.techkraft.com/health

  # ─────────────────────────────────────────────────────────
  # Stage 5: Deploy to PRODUCTION (manual approval required)
  # ─────────────────────────────────────────────────────────
  deploy-production:
    name: Deploy → Production
    runs-on: ubuntu-latest
    needs: deploy-staging
    if: github.ref == 'refs/heads/main'
    environment:
      name: production          # ← GitHub Environment with required reviewers
      url: https://api.techkraft.com

    steps:
      - uses: actions/checkout@v6

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/GHA-Deploy-Production
          aws-region: us-east-1

      - name: Record pre-deploy state (for rollback)
        id: pre-deploy
        run: |
          CURRENT_TASK=$(aws ecs describe-services \
            --cluster techkraft-prod \
            --services backend \
            --query 'services[0].taskDefinition' --output text)
          echo "previous-task-def=$CURRENT_TASK" >> $GITHUB_OUTPUT

      - name: Deploy to production ECS (rolling update)
        run: |
          aws ecs update-service \
            --cluster techkraft-prod \
            --service backend \
            --force-new-deployment \
            --deployment-configuration "minimumHealthyPercent=100,maximumPercent=200"

      - name: Wait for stable deployment
        run: |
          aws ecs wait services-stable \
            --cluster techkraft-prod \
            --services backend

      - name: Production smoke test
        run: |
          curl --fail --retry 5 --retry-delay 10 \
            https://api.techkraft.com/health

      # ── Rollback on failure ───────────────────────────────
      - name: Rollback on failure
        if: failure()
        run: |
          echo "Deploy failed — rolling back to ${{ steps.pre-deploy.outputs.previous-task-def }}"
          aws ecs update-service \
            --cluster techkraft-prod \
            --service backend \
            --task-definition "${{ steps.pre-deploy.outputs.previous-task-def }}" \
            --force-new-deployment
          # Notify team
          curl -X POST "${{ secrets.SLACK_WEBHOOK_URL }}" \
            -H 'Content-type: application/json' \
            --data '{"text":"🔴 Production deploy failed and rolled back. See: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"}'
```

---

## Key Improvements Summary

| Area | Current | Improved |
|---|---|---|
| **Security scanning** | None | pip-audit + bandit + Trivy + truffleHog on every PR |
| **Testing** | Unit tests only | Unit + Integration + smoke tests post-deploy |
| **Secrets** | Unknown | GitHub OIDC (no long-lived AWS keys ever stored) |
| **Approval gate** | None | GitHub Environment protection rules (2 reviewers for prod) |
| **Rollback** | Manual re-deploy | Automatic rollback to previous task definition on failure |
| **Environments** | 1 (prod only) | dev branch → staging (auto) → prod (manual approval) |
| **Image management** | rsync raw files | Immutable Docker images with digest pinning |
| **Dependency caching** | None | `actions/setup-python` pip cache (3–5min savings/run) |
| **Notifications** | None | Slack webhook on deploy failure |
| **Deploy method** | rsync (fragile) | ECS rolling update (zero-downtime, built-in health checks) |

---

## Environment Promotion Strategy

```
Feature branch → PR → [security scan + tests] → Review → Merge to main
                                                              │
                                                              ▼
                                                    Deploy to STAGING (auto)
                                                              │
                                                    Smoke tests pass?
                                                              │ Yes
                                                              ▼
                                               Awaiting approval (2 engineers)
                                                              │ Approved
                                                              ▼
                                                    Deploy to PRODUCTION
                                                              │
                                                    Smoke test fails?
                                                              │ Yes
                                                              ▼
                                                   AUTO ROLLBACK + Slack alert
```

> **Mentorship note for the team:** The environment protection rules in GitHub (Settings → Environments → Required reviewers) are the key mechanism that prevents anyone from bypassing the staging then approval to prod flow. Every engineer should understand *why* this gate exists — not to slow them down, but to make their deploys safer. Pair this with a blameless post-mortem culture so people learn from failures rather than hide them.