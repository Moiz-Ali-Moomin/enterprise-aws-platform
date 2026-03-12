"""Unit tests — system endpoints and middleware."""


class TestHealthEndpoints:
    def test_health_check(self, client):
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "uptime_seconds" in data

    def test_readiness_check(self, client):
        """Readiness probe should return 200 when the test DB is reachable."""
        response = client.get("/ready")
        assert response.status_code == 200
        assert response.json()["status"] == "ready"

    def test_metrics_endpoint(self, client):
        response = client.get("/metrics")
        assert response.status_code in [200, 404]
        if response.status_code == 200:
            assert "python_info" in response.text or "http_request_duration_seconds" in response.text


class TestMiddleware:
    def test_response_time_header(self, client):
        response = client.get("/health")
        assert "x-response-time-ms" in response.headers

    def test_response_time_is_numeric(self, client):
        response = client.get("/health")
        val = response.headers.get("x-response-time-ms", "")
        assert float(val) >= 0
