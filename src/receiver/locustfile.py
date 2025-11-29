from locust import HttpUser, task, between
import uuid
import random


def make_order():
    return {
        "order_id": str(uuid.uuid4()),
        "customer_id": random.randint(1, 1000),
        "items": [
            {"product_id": "prod-" + str(i), "quantity": random.randint(
                1, 5), "price": round(random.random() * 100, 2)}
            for i in range(1, random.randint(2, 4))
        ]
    }


class OrdersUser(HttpUser):
    # wait_time between requests: random between 100ms and 500ms
    wait_time = between(0.1, 0.5)

    @task(1)
    def post_order_sync(self):
        order = make_order()
        # If the request doesn't complete within 8s it will be recorded as a failure
        self.client.post("/orders/sync", json=order, timeout=8)
