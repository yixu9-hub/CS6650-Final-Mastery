package main

import (
    "bytes"
    "encoding/json"
    "net/http"
    "net/http/httptest"
    "os"
    "testing"
    "time"
)

func TestHealth(t *testing.T) {
    ts := httptest.NewServer(newRouter())
    defer ts.Close()

    resp, err := http.Get(ts.URL + "/health")
    if err != nil {
        t.Fatalf("health request failed: %v", err)
    }
    defer resp.Body.Close()

    if resp.StatusCode != http.StatusOK {
        t.Fatalf("expected 200 OK, got %d", resp.StatusCode)
    }
}

func TestOrdersSyncDelay(t *testing.T) {
    ts := httptest.NewServer(newRouter())
    defer ts.Close()

    payload := map[string]interface{}{
        "order_id": "ord-123",
        "customer_id": 42,
        "items": []map[string]interface{}{
            {"product_id": "prod-1", "quantity": 2, "price": 5.0},
        },
    }
    b, _ := json.Marshal(payload)

    start := time.Now()
    resp, err := http.Post(ts.URL+"/orders/sync", "application/json", bytes.NewReader(b))
    if err != nil {
        t.Fatalf("post request failed: %v", err)
    }
    defer resp.Body.Close()
    elapsed := time.Since(start)

    if resp.StatusCode != http.StatusOK {
        t.Fatalf("expected 200 OK, got %d", resp.StatusCode)
    }

    if elapsed < 3*time.Second {
        t.Fatalf("expected at least 3s delay, got %v", elapsed)
    }
    if elapsed > 6*time.Second {
        t.Fatalf("expected delay not to exceed 6s, got %v", elapsed)
    }

    // decode returned order and ensure status is completed
    var ordResp Order
    if err := json.NewDecoder(resp.Body).Decode(&ordResp); err != nil {
        t.Fatalf("failed decoding response: %v", err)
    }
    if ordResp.Status != "completed" {
        t.Fatalf("expected order status completed, got %s", ordResp.Status)
    }
}

func TestOrdersAsyncAccept(t *testing.T) {
    // enable test mode so async handler doesn't require real SNS
    _ = os.Setenv("ASYNC_TEST_MODE", "true")
    defer os.Unsetenv("ASYNC_TEST_MODE")

    ts := httptest.NewServer(newRouter())
    defer ts.Close()

    payload := map[string]interface{}{
        "order_id": "ord-async-1",
        "customer_id": 99,
        "items": []map[string]interface{}{
            {"product_id": "prod-async", "quantity": 1, "price": 1.0},
        },
    }
    b, _ := json.Marshal(payload)

    start := time.Now()
    resp, err := http.Post(ts.URL+"/orders/async", "application/json", bytes.NewReader(b))
    if err != nil {
        t.Fatalf("post async request failed: %v", err)
    }
    defer resp.Body.Close()
    elapsed := time.Since(start)

    if resp.StatusCode != http.StatusAccepted {
        t.Fatalf("expected 202 Accepted, got %d", resp.StatusCode)
    }
    if elapsed > 2*time.Second {
        t.Fatalf("expected async handler to return quickly (<2s), got %v", elapsed)
    }
}
