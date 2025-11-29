from locust import HttpUser, task, between
import random
import uuid


def make_order():
    return {
        "order_id": str(uuid.uuid4()),
        "customer_id": random.randint(1, 1000),
        "items": [{"product_id": "sku-1", "quantity": 1, "price": 9.99}],
    }


class SyncUser(HttpUser):
    """Locust user to test the blocking /orders/sync endpoint."""
    wait_time = between(0.1, 0.5)
    weight = 1

    @task
    def post_sync_order(self):
        order = make_order()
        # /orders/sync simulates ~3s processing; set timeout > 3s
        with self.client.post("/orders/sync", json=order, timeout=10, catch_response=True) as resp:
            if resp.status_code != 200:
                resp.failure(f"unexpected status {resp.status_code}")
            # Optionally inspect body for completed status
