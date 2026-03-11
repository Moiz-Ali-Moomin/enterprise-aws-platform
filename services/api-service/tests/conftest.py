"""Shared test fixtures."""

import os
import pytest

# Set test environment before importing app
os.environ["ENVIRONMENT"] = "test"
os.environ["SQS_QUEUE_URL"] = ""
os.environ["OTEL_EXPORTER_OTLP_ENDPOINT"] = "http://localhost:4317"

from fastapi.testclient import TestClient  # noqa: E402
from src.main import app  # noqa: E402


@pytest.fixture
def client():
    """Create a test client for the FastAPI application."""
    with TestClient(app) as c:
        yield c
