"""
Enterprise API Service — Main Application

Production-grade FastAPI application with:
- Structured JSON logging
- OpenTelemetry tracing and metrics
- Graceful shutdown handling
- Health and readiness endpoints
- Error handling middleware
"""

import json
import logging
import os
import signal
import sys
import time

from fastapi import FastAPI, Request, Response, status
from fastapi.responses import JSONResponse

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

# Suppress noisy third-party loggers
logging.getLogger("uvicorn.access").setLevel(logging.WARNING)

# ──────────────────────────────────────────────
# Application Setup
# ──────────────────────────────────────────────

app = FastAPI(
    title="Enterprise API Service",
    version="1.0.0",
    docs_url="/docs" if os.getenv("ENVIRONMENT") != "production" else None,
)

@app.on_event("startup")
async def startup_event():
    logger.info("Application starting up")

# ──────────────────────────────────────────────
# OpenTelemetry Instrumentation
# ──────────────────────────────────────────────

try:
    from src.otel_setup import setup_telemetry, instrument_app

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
# Mount Routers
# ──────────────────────────────────────────────

from src.order_processor import router as orders_router  # noqa: E402

app.include_router(orders_router)

# ──────────────────────────────────────────────
# Error Handling Middleware
# ──────────────────────────────────────────────

@app.middleware("http")
async def error_handling_middleware(request: Request, call_next):
    try:
        response = await call_next(request)
        return response
    except Exception as exc:
        logger.exception(f"Unhandled exception on {request.method} {request.url.path}")
        return JSONResponse(
            status_code=500,
            content={"detail": "Internal server error"},
        )


# ──────────────────────────────────────────────
# Request Timing Middleware
# ──────────────────────────────────────────────

@app.middleware("http")
async def timing_middleware(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    duration_ms = (time.perf_counter() - start) * 1000
    response.headers["X-Response-Time-Ms"] = f"{duration_ms:.2f}"
    return response


# ──────────────────────────────────────────────
# Graceful Shutdown
# ──────────────────────────────────────────────

def signal_handler(sig, frame):
    logger.info("SIGTERM received — initiating graceful shutdown")
    sys.exit(0)


signal.signal(signal.SIGTERM, signal_handler)

# ──────────────────────────────────────────────
# Health & Readiness Endpoints
# ──────────────────────────────────────────────

_start_time = time.time()


@app.get("/health", tags=["system"])
def health_check():
    """Liveness probe — returns healthy if the process is running."""
    return {
        "status": "healthy",
        "uptime_seconds": round(time.time() - _start_time, 1),
    }


@app.get("/ready", tags=["system"])
def readiness_check():
    """Readiness probe — returns ready when all dependencies are available."""
    # Extend with actual dependency checks (DB, cache, queues)
    return {"status": "ready"}


# /metrics is now handled by the Instrumentator


# ──────────────────────────────────────────────
# Application Endpoints
# ──────────────────────────────────────────────

@app.get("/", tags=["app"])
def read_root():
    logger.info("Root endpoint accessed")
    return {"message": "Enterprise API Service", "version": "1.0.0"}


@app.get("/items/{item_id}", tags=["app"])
def read_item(item_id: int):
    logger.info(f"Item {item_id} requested")
    return {"item_id": item_id}
