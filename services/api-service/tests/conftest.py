"""Shared test fixtures — uses an in-memory SQLite database."""

import asyncio
import os
import uuid

import pytest

# Configure test environment before any app imports
os.environ.setdefault("ENVIRONMENT", "test")
os.environ.setdefault("SQS_QUEUE_URL", "")
os.environ.setdefault("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")
os.environ.setdefault("DATABASE_URL", "sqlite+aiosqlite:///:memory:")
os.environ.setdefault("SECRET_KEY", "test-secret-key-do-not-use-in-production")

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine  # noqa: E402

from src.database import Base, get_db  # noqa: E402
from src.main import app  # noqa: E402

# In-memory SQLite — shared engine across all tests
_TEST_DB_URL = "sqlite+aiosqlite:///:memory:"
_test_engine = create_async_engine(_TEST_DB_URL, connect_args={"check_same_thread": False})
_TestSession = async_sessionmaker(bind=_test_engine, class_=AsyncSession, expire_on_commit=False)


async def _init_test_db():
    async with _test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def _reset_test_db():
    """Drop and recreate all tables to isolate each test."""
    async with _test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)


async def _get_test_db():
    async with _TestSession() as session:
        yield session


# Override the DB dependency globally
app.dependency_overrides[get_db] = _get_test_db

# Create tables once before any tests run
asyncio.run(_init_test_db())


@pytest.fixture(autouse=True)
def reset_db():
    """Reset the database before each test for full isolation."""
    asyncio.run(_reset_test_db())
    yield


@pytest.fixture(scope="function")
def client():
    """Test client backed by the in-memory test database."""
    with TestClient(app, raise_server_exceptions=True) as c:
        yield c


@pytest.fixture
def auth_headers(client: TestClient):
    """Register a unique test user and return Authorization headers."""
    unique_email = f"test-{uuid.uuid4().hex[:8]}@example.com"
    resp = client.post("/api/auth/register", json={
        "full_name": "Test User",
        "email": unique_email,
        "password": "securepassword123",
    })
    assert resp.status_code == 201, resp.text
    token = resp.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}
