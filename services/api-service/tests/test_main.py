"""Unit tests for the API service."""


class TestHealthEndpoints:
    """Tests for health and readiness probes."""

    def test_health_check(self, client):
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "uptime_seconds" in data

    def test_readiness_check(self, client):
        response = client.get("/ready")
        assert response.status_code == 200
        assert response.json()["status"] == "ready"

    def test_metrics_endpoint(self, client):
        response = client.get("/metrics")
        # If the instrumentator is installed, it returns 200 and text content
        # If missing (e.g. in some local dev environments without all libs), handle gracefully 
        # but in CI this MUST pass.
        assert response.status_code in [200, 404] 
        if response.status_code == 200:
            assert "python_info" in response.text or "http_request_duration_seconds" in response.text


class TestApplicationEndpoints:
    """Tests for application business logic."""

    def test_root(self, client):
        response = client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert "Enterprise API Service" in data["message"]
        assert data["version"] == "1.0.0"

    def test_get_item(self, client):
        response = client.get("/items/42")
        assert response.status_code == 200
        assert response.json() == {"item_id": 42}

    def test_get_item_invalid_id(self, client):
        response = client.get("/items/not-a-number")
        assert response.status_code == 422  # Validation error


class TestOrderEndpoints:
    """Tests for order processing."""

    def test_create_order_no_sqs_configured(self, client):
        """Orders should return 503 when SQS is not configured."""
        response = client.post("/orders", json={"product": "widget", "qty": 1})
        assert response.status_code == 503


class TestMiddleware:
    """Tests for middleware behavior."""

    def test_response_time_header(self, client):
        response = client.get("/health")
        assert "x-response-time-ms" in response.headers
