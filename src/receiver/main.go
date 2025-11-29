package main

import (
    "context"
    "encoding/json"
    "log"
    "net/http"
    "os"
    "strconv"
    "time"

    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/config"
    "github.com/aws/aws-sdk-go-v2/service/sns"
)

// concurrency limit for synchronous payment processing in /orders/sync
var paymentProcessorLimit = make(chan struct{}, 20) // default 20 concurrent payments

type Item struct {
    ProductID string  `json:"product_id"`
    Quantity  int     `json:"quantity"`
    Price     float64 `json:"price"`
}

type Order struct {
    OrderID    string    `json:"order_id"`
    CustomerID int       `json:"customer_id"`
    Status     string    `json:"status"`
    Items      []Item    `json:"items"`
    CreatedAt  time.Time `json:"created_at"`
}

// AWS SNS client and topic ARN (used by /orders/async)
var snsClient *sns.Client
var topicArn string
var publishTimeout = 5 * time.Second

func initSNS() {
    topicArn = os.Getenv("SNS_TOPIC_ARN")
    if topicArn == "" {
        log.Printf("SNS_TOPIC_ARN not set: /orders/async will return 503")
        return
    }
    // allow override of timeout
    if s := os.Getenv("SNS_PUBLISH_TIMEOUT_SECONDS"); s != "" {
        if v, err := strconv.Atoi(s); err == nil && v > 0 {
            publishTimeout = time.Duration(v) * time.Second
        }
    }

    // Support an optional local endpoint (e.g., LocalStack) via AWS_ENDPOINT env var.
    awsEndpoint := os.Getenv("AWS_ENDPOINT")
    var cfg aws.Config
    var err error
    if awsEndpoint != "" {
        resolver := aws.EndpointResolverWithOptionsFunc(func(service, region string, options ...interface{}) (aws.Endpoint, error) {
            return aws.Endpoint{URL: awsEndpoint, SigningRegion: os.Getenv("AWS_REGION")}, nil
        })
        cfg, err = config.LoadDefaultConfig(context.Background(), config.WithEndpointResolverWithOptions(resolver))
    } else {
        cfg, err = config.LoadDefaultConfig(context.Background())
    }
    if err != nil {
        log.Printf("unable to load AWS SDK config: %v", err)
        // leave snsClient nil; async will fail with 503
        return
    }
    snsClient = sns.NewFromConfig(cfg)
    log.Printf("SNS client initialized (topic: %s)", topicArn)
}

func newRouter() http.Handler {
    mux := http.NewServeMux()
    mux.HandleFunc("/health", healthHandler)
    mux.HandleFunc("/orders/sync", ordersSyncHandler)
    mux.HandleFunc("/orders/async", ordersAsyncHandler)
    return mux
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    _, _ = w.Write([]byte("OK"))
}

func ordersSyncHandler(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
        return
    }

    defer r.Body.Close()
    var ord Order
    if err := json.NewDecoder(r.Body).Decode(&ord); err != nil {
        http.Error(w, "Invalid request", http.StatusBadRequest)
        return
    }

    if ord.Status == "" {
        ord.Status = "pending"
    }
    if ord.CreatedAt.IsZero() {
        ord.CreatedAt = time.Now().UTC()
    }

    ord.Status = "processing"

    paymentProcessorLimit <- struct{}{}
    defer func() { <-paymentProcessorLimit }()

    // Simulate payment verification (3s)
    time.Sleep(3 * time.Second)

    ord.Status = "completed"

    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusOK)
    _ = json.NewEncoder(w).Encode(ord)
}

// ordersAsyncHandler publishes order to SNS and returns 202 Accepted
func ordersAsyncHandler(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
        return
    }

    // Test-only bypass: when ASYNC_TEST_MODE=true we accept without contacting SNS.
    if os.Getenv("ASYNC_TEST_MODE") == "true" {
        w.WriteHeader(http.StatusAccepted)
        return
    }

    if snsClient == nil || topicArn == "" {
        http.Error(w, "async endpoint not configured", http.StatusServiceUnavailable)
        return
    }

    defer r.Body.Close()
    var order Order
    if err := json.NewDecoder(r.Body).Decode(&order); err != nil {
        http.Error(w, "Invalid request", http.StatusBadRequest)
        return
    }

    order.Status = "pending"
    if order.CreatedAt.IsZero() {
        order.CreatedAt = time.Now().UTC()
    }

    payload, err := json.Marshal(order)
    if err != nil {
        log.Printf("failed to marshal order: %v", err)
        http.Error(w, "failed to accept order", http.StatusInternalServerError)
        return
    }

    ctx, cancel := context.WithTimeout(context.Background(), publishTimeout)
    defer cancel()

    result, err := snsClient.Publish(ctx, &sns.PublishInput{
        TopicArn: aws.String(topicArn),
        Message:  aws.String(string(payload)),
    })

    if err != nil {
        log.Printf("Failed to publish: %v", err)
        http.Error(w, "Failed to accept order", http.StatusServiceUnavailable)
        return
    }

    msgID := ""
    if result != nil && result.MessageId != nil {
        msgID = *result.MessageId
    }
    log.Printf("Published order %s (MessageID: %s)", order.OrderID, msgID)

    w.WriteHeader(http.StatusAccepted)
}

func main() {
    // optionally override concurrency via env
    if s := os.Getenv("PAYMENT_CONCURRENCY"); s != "" {
        if v, err := strconv.Atoi(s); err == nil && v > 0 {
            paymentProcessorLimit = make(chan struct{}, v)
        }
    }

    initSNS()

    addr := ":8080"
    if p := os.Getenv("PORT"); p != "" {
        addr = ":" + p
    }

    srv := &http.Server{
        Addr:    addr,
        Handler: newRouter(),
    }

    log.Printf("starting receiver on %s (payment processor limit: %d concurrent)", addr, cap(paymentProcessorLimit))
    if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
        log.Fatalf("server failed: %v", err)
    }
}