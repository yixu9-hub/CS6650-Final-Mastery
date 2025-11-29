from locust import HttpUser, task, between
import random
import uuid


def make_order():
    return {
        "order_id": str(uuid.uuid4()),
        "customer_id": random.randint(1, 1000),
        "items": [{"product_id": "sku-1", "quantity": 1, "price": 9.99}],
    }


class AsyncUser(HttpUser):
    """Locust user to test the fast-accept /orders/async endpoint."""
    wait_time = between(0.1, 0.5)
    weight = 1

    @task
    def post_async_order(self):
        order = make_order()
        # /orders/async should return quickly with 202
        with self.client.post("/orders/async", json=order, timeout=5, catch_response=True) as resp:
            if resp.status_code != 202:
                resp.failure(f"unexpected status {resp.status_code}")
