"""Order and stats endpoint tests."""


class TestOrders:
    def test_list_orders_empty(self, client, auth_headers):
        resp = client.get("/api/orders", headers=auth_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["items"] == []
        assert data["total"] == 0

    def test_create_order(self, client, auth_headers):
        resp = client.post("/api/orders", headers=auth_headers, json={
            "product_name": "Enterprise SSD",
            "quantity": 2,
            "unit_price": 149.99,
        })
        assert resp.status_code == 201
        data = resp.json()
        assert data["product_name"] == "Enterprise SSD"
        assert data["quantity"] == 2
        assert data["unit_price"] == 149.99
        assert abs(data["total_amount"] - 299.98) < 0.01
        assert data["status"] == "pending"

    def test_list_orders_after_create(self, client, auth_headers):
        client.post("/api/orders", headers=auth_headers, json={
            "product_name": "Widget", "quantity": 1, "unit_price": 10.0,
        })
        resp = client.get("/api/orders", headers=auth_headers)
        assert resp.status_code == 200
        assert resp.json()["total"] == 1

    def test_get_order_by_id(self, client, auth_headers):
        created = client.post("/api/orders", headers=auth_headers, json={
            "product_name": "Gadget", "quantity": 3, "unit_price": 25.0,
        }).json()
        resp = client.get(f"/api/orders/{created['id']}", headers=auth_headers)
        assert resp.status_code == 200
        assert resp.json()["id"] == created["id"]

    def test_get_order_not_found(self, client, auth_headers):
        resp = client.get("/api/orders/nonexistent-id", headers=auth_headers)
        assert resp.status_code == 404

    def test_update_order_status(self, client, auth_headers):
        created = client.post("/api/orders", headers=auth_headers, json={
            "product_name": "Item", "quantity": 1, "unit_price": 5.0,
        }).json()
        resp = client.put(f"/api/orders/{created['id']}", headers=auth_headers, json={"status": "processing"})
        assert resp.status_code == 200
        assert resp.json()["status"] == "processing"

    def test_cancel_order(self, client, auth_headers):
        created = client.post("/api/orders", headers=auth_headers, json={
            "product_name": "CancelMe", "quantity": 1, "unit_price": 1.0,
        }).json()
        resp = client.delete(f"/api/orders/{created['id']}", headers=auth_headers)
        assert resp.status_code == 204

    def test_cancel_order_twice(self, client, auth_headers):
        created = client.post("/api/orders", headers=auth_headers, json={
            "product_name": "CancelTwice", "quantity": 1, "unit_price": 1.0,
        }).json()
        client.delete(f"/api/orders/{created['id']}", headers=auth_headers)
        resp = client.delete(f"/api/orders/{created['id']}", headers=auth_headers)
        assert resp.status_code == 409

    def test_orders_require_auth(self, client):
        resp = client.get("/api/orders")
        assert resp.status_code == 401

    def test_status_filter(self, client, auth_headers):
        client.post("/api/orders", headers=auth_headers, json={
            "product_name": "Pending Item", "quantity": 1, "unit_price": 1.0,
        })
        resp = client.get("/api/orders?status=completed", headers=auth_headers)
        assert resp.status_code == 200
        assert resp.json()["total"] == 0

    def test_order_invalid_quantity(self, client, auth_headers):
        resp = client.post("/api/orders", headers=auth_headers, json={
            "product_name": "Bad", "quantity": 0, "unit_price": 10.0,
        })
        assert resp.status_code == 422


class TestStats:
    def test_stats_empty(self, client, auth_headers):
        resp = client.get("/api/stats", headers=auth_headers)
        assert resp.status_code == 200
        data = resp.json()
        assert data["total_orders"] == 0
        assert data["total_revenue"] == 0.0

    def test_stats_with_orders(self, client, auth_headers):
        client.post("/api/orders", headers=auth_headers, json={
            "product_name": "P1", "quantity": 2, "unit_price": 100.0,
        })
        resp = client.get("/api/stats", headers=auth_headers)
        data = resp.json()
        assert data["total_orders"] == 1
        assert data["pending"] == 1

    def test_stats_require_auth(self, client):
        resp = client.get("/api/stats")
        assert resp.status_code == 401
