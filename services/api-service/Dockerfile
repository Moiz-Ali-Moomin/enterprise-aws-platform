# ==============================================
# Stage 1: Node.js — Build React frontend
# ==============================================
FROM node:20-slim AS web-builder

WORKDIR /web
COPY web/package.json web/package-lock.json* ./
RUN npm ci --silent
COPY web/ ./
RUN npm run build
# Build output → /web/dist (vite outDir: 'dist')

# ==============================================
# Stage 2: Python — Install dependencies
# ==============================================
FROM python:3.11-slim@sha256:73934f07bb8a04a601dc621379796e680a618426176a6b5791722e9e24806a66 AS python-builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ==============================================
# Stage 3: Runtime — Minimal production image
# ==============================================
FROM python:3.11-slim@sha256:73934f07bb8a04a601dc621379796e680a618426176a6b5791722e9e24806a66 AS runtime

ARG BUILD_DATE
ARG GIT_SHA
LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.title="enterprise-api-service" \
      org.opencontainers.image.vendor="enterprise-platform"

WORKDIR /app

# Python packages from builder
COPY --from=python-builder /install /usr/local

# Application source
COPY src/ ./src/

# React SPA build — served as static files by FastAPI
COPY --from=web-builder /web/dist ./static/

# Non-root user
RUN useradd --no-create-home --shell /bin/false appuser && \
    chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

ENV UVICORN_WORKERS=2

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD uvicorn src.main:app --host 0.0.0.0 --port 8000 --log-level info --access-log --workers ${UVICORN_WORKERS}
