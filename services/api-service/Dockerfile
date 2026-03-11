# Stage 1: Builder — Install dependencies
# ==============================================
FROM python:3.11-slim@sha256:73934f07bb8a04a601dc621379796e680a618426176a6b5791722e9e24806a66 AS builder

WORKDIR /build

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ==============================================
# Stage 2: Runtime — Minimal production image
# ==============================================
FROM python:3.11-slim@sha256:73934f07bb8a04a601dc621379796e680a618426176a6b5791722e9e24806a66 AS runtime

# Build metadata
ARG BUILD_DATE
ARG GIT_SHA
LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.title="enterprise-api-service" \
      org.opencontainers.image.vendor="enterprise-platform"

WORKDIR /app

# Copy only the installed packages from builder
COPY --from=builder /install /usr/local

# Copy source code
COPY src/ ./src/

# Create non-root user
RUN useradd --no-create-home --shell /bin/false appuser && \
    chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

# Default workers — overridden by UVICORN_WORKERS env var from ECS task definition
ENV UVICORN_WORKERS=2

# Container-level health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# Graceful shutdown with uvicorn — workers controlled by env var
CMD uvicorn src.main:app --host 0.0.0.0 --port 8000 --log-level info --access-log --workers ${UVICORN_WORKERS}
