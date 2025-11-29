# Orders Sync Service (Go)

Simple HTTP service with two endpoints:

- GET /health -> returns 200 OK
- POST /orders/sync -> simulates synchronous payment verification (3s delay), returns 200 OK JSON

Run locally (PowerShell):

```powershell
# run tests
go test -v

# build and run server
go build -o ordersync.exe
.\ordersync.exe

# or directly
go run .
```

The POST /orders/sync expects an `Order` JSON and returns the updated `Order` after a synchronous 3s payment verification.

Example request body:

```json
{
	"order_id": "ord-123",
	"customer_id": 42,
	"items": [ { "sku": "sku-1", "quantity": 2, "price": 5.0 } ]
}
```

Example response body:

```json
{
	"order_id": "ord-123",
	"customer_id": 42,
	"status": "completed",
	"items": [ { "sku": "sku-1", "quantity": 2, "price": 5.0 } ],
	"created_at": "2025-10-24T...Z"
}
```

Locust load test (requires Python & locust):

Install Locust (recommend inside virtualenv):

```powershell
python -m pip install locust
```

Run Locust from this project folder. The `locustfile.py` targets POST `/orders/sync` only and uses a random wait of 100–500ms between requests.

Recommended spawn configurations:

- Normal: spawn rate 1 user/sec
- Flash: spawn rate 10 users/sec

You can control spawn-rate and total users from the CLI. Examples (PowerShell):

```powershell
# Normal: spawn 1 user/sec, 100 total users
locust -f locustfile.py --host=http://localhost:8080 --users 100 --spawn-rate 1

# Flash: spawn 10 users/sec, 100 total users
locust -f locustfile.py --host=http://localhost:8080 --users 100 --spawn-rate 10
```

Or use the helper scripts included:

```powershell
.\run_locust_normal.ps1
.\run_locust_flash.ps1
```

Open http://localhost:8089 in your browser to view the Locust UI and start/monitor the test.
