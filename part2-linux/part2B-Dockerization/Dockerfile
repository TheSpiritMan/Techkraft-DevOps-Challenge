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