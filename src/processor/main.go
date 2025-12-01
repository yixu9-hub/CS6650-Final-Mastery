package main

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/sqs/types"
	"github.com/cs6650/final-mastery/processor/metrics"
)

type Item struct {
	ProductID string  `json:"product_id"`
	Quantity  int     `json:"quantity"`
	Price     float64 `json:"price"`
}

type Order struct {
	OrderID    string `json:"order_id"`
	CustomerID int    `json:"customer_id"`
	Status     string `json:"status"`
	Items      []Item `json:"items"`
	CreatedAt  int64  `json:"created_at"` // Unix timestamp in milliseconds
}

var queueDepth int64 // Track approximate queue depth

func main() {
	queueURL := os.Getenv("SQS_QUEUE_URL")
	if queueURL == "" {
		log.Fatal("SQS_QUEUE_URL must be set")
	}

	environment := os.Getenv("ENVIRONMENT")
	if environment == "" {
		environment = "aws"
	}

	concurrency := 1
	if s := os.Getenv("PROCESSOR_CONCURRENCY"); s != "" {
		if v, err := strconv.Atoi(s); err == nil && v > 0 {
			concurrency = v
		}
	}

	paymentSimSeconds := 3
	if s := os.Getenv("PAYMENTSIM_SECONDS"); s != "" {
		if v, err := strconv.Atoi(s); err == nil && v > 0 {
			paymentSimSeconds = v
		}
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Initialize metrics collector
	metricsCollector := metrics.NewCollector(environment)
	defer func() {
		if err := metricsCollector.Flush(); err != nil {
			log.Printf("failed to flush metrics: %v", err)
		}
	}()

	// handle shutdown
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigs
		log.Println("shutdown signal received")
		cancel()
	}()

	// Load AWS config with optional custom endpoint
	awsEndpoint := os.Getenv("AWS_ENDPOINT")
	var cfg aws.Config
	var err error
	if awsEndpoint != "" {
		resolver := aws.EndpointResolverWithOptionsFunc(func(service, region string, options ...interface{}) (aws.Endpoint, error) {
			return aws.Endpoint{URL: awsEndpoint, SigningRegion: os.Getenv("AWS_REGION")}, nil
		})
		cfg, err = config.LoadDefaultConfig(ctx, config.WithEndpointResolverWithOptions(resolver))
	} else {
		cfg, err = config.LoadDefaultConfig(ctx)
	}
	if err != nil {
		log.Fatalf("failed to load AWS config: %v", err)
	}

	client := sqs.NewFromConfig(cfg)

	// concurrency semaphore and waitgroup to wait for in-flight messages on shutdown
	sem := make(chan struct{}, concurrency)
	var wg sync.WaitGroup

	log.Printf("starting processor: queue=%s concurrency=%d paymentsim=%ds", queueURL, concurrency, paymentSimSeconds)

	// Poll loop
	for {
		select {
		case <-ctx.Done():
			log.Println("context cancelled, waiting for in-flight messages")
			wg.Wait()
			log.Println("processor shutdown complete")
			return
		default:
		}

		// Receive messages (long polling)
		out, err := client.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
			QueueUrl:            &queueURL,
			MaxNumberOfMessages: 10,
			WaitTimeSeconds:     20,
			VisibilityTimeout:   60,
		})
		if err != nil {
			// Log and backoff
			log.Printf("receive error: %v", err)
			time.Sleep(2 * time.Second)
			continue
		}

		if len(out.Messages) == 0 {
			// no messages, continue
			continue
		}

		for _, msg := range out.Messages {
			// acquire semaphore
			sem <- struct{}{}
			wg.Add(1)
			atomic.AddInt64(&queueDepth, 1)

			go func(m types.Message) {
				defer func() {
					<-sem
					wg.Done()
					atomic.AddInt64(&queueDepth, -1)
				}()

				fetchTime := time.Now()

				// process message (expect SNS envelope with Message field)
				type SNSMessage struct {
					Message string `json:"Message"`
				}

				var snsMsg SNSMessage
				if err := json.Unmarshal([]byte(*m.Body), &snsMsg); err != nil {
					log.Printf("failed to unmarshal SNS wrapper: %v; body=%s", err, *m.Body)
					// delete bad message to avoid poison messages; consider DLQ in production
					if _, derr := client.DeleteMessage(ctx, &sqs.DeleteMessageInput{QueueUrl: &queueURL, ReceiptHandle: m.ReceiptHandle}); derr != nil {
						log.Printf("failed to delete malformed message: %v", derr)
					}
					return
				}

				var ord Order
				if err := json.Unmarshal([]byte(snsMsg.Message), &ord); err != nil {
					log.Printf("failed to unmarshal order: %v; message=%s", err, snsMsg.Message)
					if _, derr := client.DeleteMessage(ctx, &sqs.DeleteMessageInput{QueueUrl: &queueURL, ReceiptHandle: m.ReceiptHandle}); derr != nil {
						log.Printf("failed to delete malformed message: %v", derr)
					}
					return
				}

				// Record fetched metric
				queueLatency := fetchTime.UnixMilli() - ord.CreatedAt
				currentDepth := int(atomic.LoadInt64(&queueDepth))
				metricsCollector.Record(ord.OrderID, "fetched", float64(queueLatency), currentDepth)

				log.Printf("processing order %s (customer=%d) queue_latency=%dms", ord.OrderID, ord.CustomerID, queueLatency)

				processStart := time.Now()
				// Simulate payment verification / processing
				time.Sleep(time.Duration(paymentSimSeconds) * time.Second)
				processLatency := time.Since(processStart).Milliseconds()

				// Record processed metric
				metricsCollector.Record(ord.OrderID, "processed", float64(processLatency), currentDepth)

				totalLatency := time.Since(fetchTime).Milliseconds()
				endToEndLatency := time.Now().UnixMilli() - ord.CreatedAt
				log.Printf("completed order %s - process_latency=%dms total_latency=%dms end_to_end=%dms",
					ord.OrderID, processLatency, totalLatency, endToEndLatency)

				// Record completed metric
				metricsCollector.Record(ord.OrderID, "completed", float64(endToEndLatency), currentDepth)

				// delete message after success
				if _, derr := client.DeleteMessage(ctx, &sqs.DeleteMessageInput{QueueUrl: &queueURL, ReceiptHandle: m.ReceiptHandle}); derr != nil {
					log.Printf("failed to delete message: %v", derr)
				}
			}(msg)
		}
	}
}
