"""
Enterprise API Service — Main Application

Production-grade FastAPI application with:
- Structured JSON logging
- OpenTelemetry tracing and metrics
- JWT Authentication & User management
- Async SQLAlchemy database layer
- Graceful shutdown via lifespan context manager
- Health and readiness endpoints (with real DB check)
- React SPA static file serving
"""

import json
import logging
import os
import signal
import sys
import time
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from src.database import engine, init_db

# ──────────────────────────────────────────────
# Structured Logging
# ──────────────────────────────────────────────

class JsonFormatter(logging.Formatter):
    """JSON log formatter for structured logging in CloudWatch."""

    def format(self, record):
        log_record = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "message": record.getMessage(),
            "service": "api-service",
            "environment": os.getenv("ENVIRONMENT", "production"),
            "logger": record.name,
        }
        if record.exc_info and record.exc_info[0]:
            log_record["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_record)


logger = logging.getLogger("api-service")
log_handler = logging.StreamHandler(sys.stdout)
log_handler.setFormatter(JsonFormatter())
logger.addHandler(log_handler)
logger.setLevel(logging.INFO)
logging.getLogger("uvicorn.access").setLevel(logging.WARNING)

# ──────────────────────────────────────────────
# Graceful Shutdown
# ──────────────────────────────────────────────

def _signal_handler(sig, frame):
    logger.info("SIGTERM received — initiating graceful shutdown")
    sys.exit(0)

signal.signal(signal.SIGTERM, _signal_handler)

# ──────────────────────────────────────────────
# Lifespan — replaces deprecated @app.on_event
# ──────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Application starting up")
    await init_db()
    logger.info("Database initialized")
    yield
    logger.info("Application shutting down")
    await engine.dispose()

# ──────────────────────────────────────────────
# Application Setup
# ──────────────────────────────────────────────

ENVIRONMENT = os.getenv("ENVIRONMENT", "production")

app = FastAPI(
    title="Enterprise API Service",
    version="2.0.0",
    docs_url="/api/docs" if ENVIRONMENT != "production" else None,
    redoc_url="/api/redoc" if ENVIRONMENT != "production" else None,
    lifespan=lifespan,
)

# ──────────────────────────────────────────────
# OpenTelemetry Instrumentation
# ──────────────────────────────────────────────

try:
    from src.otel_setup import instrument_app, setup_telemetry
    setup_telemetry()
    instrument_app(app)
    logger.info("OpenTelemetry instrumentation initialized")
except Exception as e:
    logger.warning(f"OpenTelemetry initialization failed (non-fatal): {e}")

# ──────────────────────────────────────────────
# Prometheus Metrics
# ──────────────────────────────────────────────

try:
    from prometheus_fastapi_instrumentator import Instrumentator
    Instrumentator().instrument(app).expose(app, endpoint="/metrics")
    logger.info("Prometheus metrics initialized")
except Exception as e:
    logger.warning(f"Prometheus initialization failed: {e}")

# ──────────────────────────────────────────────
# Middleware
# ──────────────────────────────────────────────

@app.middleware("http")
async def error_handling_middleware(request: Request, call_next):
    try:
        return await call_next(request)
    except Exception:
        logger.exception(f"Unhandled exception on {request.method} {request.url.path}")
        return JSONResponse(status_code=500, content={"detail": "Internal server error"})


@app.middleware("http")
async def timing_middleware(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    response.headers["X-Response-Time-Ms"] = f"{(time.perf_counter() - start) * 1000:.2f}"
    return response

# ──────────────────────────────────────────────
# API Routers
# ──────────────────────────────────────────────

from src.routers.auth_router import router as auth_router      # noqa: E402
from src.routers.orders_router import router as orders_router  # noqa: E402
from src.routers.stats_router import router as stats_router    # noqa: E402

app.include_router(auth_router)
app.include_router(orders_router)
app.include_router(stats_router)

# ──────────────────────────────────────────────
# Health & Readiness Endpoints
# ──────────────────────────────────────────────

_start_time = time.time()


@app.get("/health", tags=["system"])
def health_check():
    """Liveness probe — returns healthy if the process is running."""
    return {"status": "healthy", "uptime_seconds": round(time.time() - _start_time, 1)}


@app.get("/ready", tags=["system"])
async def readiness_check():
    """Readiness probe — verifies the database is reachable."""
    from sqlalchemy import text
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        return {"status": "ready"}
    except Exception as exc:
        logger.warning(f"Readiness check failed: {exc}")
        from fastapi import status as http_status
        return JSONResponse(
            status_code=http_status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"status": "not ready", "detail": "Database unavailable"},
        )


# ──────────────────────────────────────────────
# Static Files (React SPA)
# ──────────────────────────────────────────────

STATIC_DIR = Path(__file__).parent.parent / "static"

if STATIC_DIR.exists():
    assets_dir = STATIC_DIR / "assets"
    if assets_dir.exists():
        app.mount("/assets", StaticFiles(directory=str(assets_dir)), name="assets")

    @app.get("/{full_path:path}", include_in_schema=False)
    async def spa_fallback(full_path: str):
        """Serve the React SPA index.html for all non-API routes."""
        index = STATIC_DIR / "index.html"
        if index.exists():
            return FileResponse(str(index))
        return JSONResponse({"message": "Enterprise API Service", "version": "2.0.0"})
else:
    @app.get("/", tags=["app"])
    def read_root():
        return {"message": "Enterprise API Service", "version": "2.0.0"}
