# Part 2B: Multi-Stage Dockerfile — TechKraft Flask API

## Files

```
part2B-Dockerization/
├── app.py
├── requirements.txt
└── Dockerfile
└── dockerization.md
```

## Dockerfile

```dockerfile
# Stage 1: Builder
FROM python:3.11-alpine AS builder

WORKDIR /build

# gcc + musl-dev needed only if any dep compiles C extensions
# flask and gunicorn are pure Python so these add nothing here —
# kept for forward compatibility if requirements.txt grows
RUN apk add --no-cache gcc musl-dev libffi-dev

COPY requirements.txt .

# Install into isolated directory — only this gets copied to final image
RUN pip install --no-cache-dir --target=/build/packages -r requirements.txt

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: Production
FROM python:3.11-alpine

# Create user first — WORKDIR created after will be owned by appuser
RUN adduser -D -u 1001 -g appuser appuser

WORKDIR /app

# Only the installed packages — no gcc, no pip cache, no build tools
COPY --chown=appuser:appuser --from=builder /build/packages /app/packages

COPY --chown=appuser:appuser app.py .

ENV PYTHONPATH=/app/packages \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=5000

USER appuser

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')"

CMD ["python", "/app/packages/bin/gunicorn", \
     "--bind", "0.0.0.0:5000", \
     "--workers", "2", \
     "--threads", "4", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "app:app"]
```

---

## Stage Breakdown

### Stage 1 — Builder (`python:3.11-alpine`)

The builder stage exists solely to install dependencies. Nothing from this
stage reaches the final image except the installed Python packages.

**System packages (`apk add --no-cache`):**

| Package | Purpose |
|---|---|
| `gcc` | C compiler for any package that compiles native extensions |
| `musl-dev` | Alpine's C standard library headers (replaces glibc on Alpine) |
| `libffi-dev` | Foreign Function Interface headers required by `cffi`, a common transitive dependency |

`--no-cache` tells apk not to write its package index to disk — no cleanup
step needed.

**Dependency installation (`--target=/build/packages`):**

```dockerfile
RUN pip install --no-cache-dir --target=/build/packages -r requirements.txt
```

`--target` installs all packages into a specific directory instead of the
system site-packages. This makes it possible to `COPY` just that one directory
into the production stage, leaving pip, setuptools, and the compiler behind.

`--no-cache-dir` prevents pip from writing a local wheel cache, keeping the
layer lean.

---

### Stage 2 — Production (`python:3.11-alpine`)

The production stage starts completely fresh from the same Alpine base. It
receives only the installed packages from Stage 1 — no compiler, no build
headers, no pip cache.

**Non-root user:**

```dockerfile
RUN adduser -D -u 1001 -g appuser appuser
```

`-D` creates the user with no password and no home directory. Running as a
non-root user (uid 1001) means that if the container is ever compromised, the
attacker has no root privileges on the host or within the container.

**Copying packages from builder:**

```dockerfile
COPY --from=builder /build/packages /app/packages
```

Only the compiled and installed Python packages are copied. The `gcc`,
`musl-dev`, `libffi-dev`, and all apk metadata stay in the builder layer which
Docker discards after the build completes.

**Environment variables:**

| Variable | Value | Reason |
|---|---|---|
| `PYTHONPATH` | `/app/packages` | Tells Python where to find packages installed with `--target` |
| `PYTHONDONTWRITEBYTECODE` | `1` | Prevents `.pyc` files being written at runtime |
| `PYTHONUNBUFFERED` | `1` | Flushes stdout/stderr immediately so logs appear in `docker logs` without delay |
| `PORT` | `5000` | Documents the expected port; can be consumed by orchestrators |

**Health check:**

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')"
```

| Flag | Value | Meaning |
|---|---|---|
| `--interval` | 30s | Check the container every 30 seconds |
| `--timeout` | 5s | Each check must complete within 5 seconds |
| `--start-period` | 10s | Grace period after container starts before failures count |
| `--retries` | 3 | Mark container unhealthy after 3 consecutive failures |

The check hits the `/health` endpoint already defined in `app.py`. If the
request raises an exception (connection refused, timeout, non-200 response),
Python exits non-zero and Docker marks the container unhealthy. No external
tools like `curl` or `wget` are needed.

**Startup command:**

```dockerfile
CMD ["python", "/app/packages/bin/gunicorn", \
     "--bind", "0.0.0.0:5000", \
     "--workers", "2", \
     "--threads", "4", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "app:app"]
```

`gunicorn` is invoked via its full path because it was installed into
`/app/packages` rather than the system `PATH`. The exec form (`["..."]`) is
used instead of shell form so that signals like `SIGTERM` are delivered
directly to the gunicorn process, enabling graceful shutdown during rolling
deploys.

| Flag | Value | Reason |
|---|---|---|
| `--bind` | `0.0.0.0:5000` | Listen on all interfaces inside the container |
| `--workers` | `2` | Two worker processes handle requests in parallel |
| `--threads` | `4` | Four threads per worker for concurrent I/O-bound requests |
| `--access-logfile` | `-` | Access logs to stdout, captured by Docker/ECS/Kubernetes log drivers |
| `--error-logfile` | `-` | Error logs to stderr |

Flask's built-in development server is single-threaded and explicitly warns
against production use. `gunicorn` is the standard WSGI server for production
Flask deployments.

---

## Build and Run

```bash
# Build
docker build -t techkraft-backend:latest .

# Run locally
docker run -p 5000:5000 techkraft-backend:latest

# Test endpoints
curl http://localhost:5000/health
curl http://localhost:5000/

# Check container health status
docker inspect --format='{{.State.Health.Status}}' <container_id>
```

---

## Adding Dependencies That Need C Extensions

If `requirements.txt` later adds packages that compile native code, add the
corresponding Alpine library to the **builder stage only**:

| Package | Extra apk dependency |
|---|---|
| `psycopg2` | `postgresql-dev` |
| `mysqlclient` | `mariadb-dev` |
| `cryptography` | `openssl-dev` |
| `Pillow` | `jpeg-dev zlib-dev` |

The production stage never needs these libraries — only the compiled `.so`
files are copied across via `COPY --from=builder`.