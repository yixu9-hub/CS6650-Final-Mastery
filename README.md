# CS6650 HW7 - Asynchronous Order Processing with AWS ECS

## Project Overview
This project implements a scalable asynchronous order processing system using AWS ECS and SQS.

## Architecture

### ECS + SQS Architecture
- **Order Receiver** (ECS Fargate): Handles `/orders/sync` and `/orders/async` endpoints
- **Order Processor** (ECS Fargate): Polls SQS and processes orders with configurable concurrency
- **Message Flow**: API → SNS → SQS → ECS Processor

## Infrastructure Components
- **VPC**: 10.0.0.0/16 with public (10.0.1.0/24, 10.0.2.0/24) and private subnets (10.0.10.0/24, 10.0.11.0/24)
- **ALB**: Application Load Balancer for order receiver service
- **ECR**: Docker image repositories for receiver and processor
- **SNS/SQS**: Message queue infrastructure

## Project Structure
```
HW7/
├── infra/                 # Terraform infrastructure
│   ├── main.tf           # Provider and locals
│   ├── vpc.tf            # VPC, subnets, NAT gateway
│   ├── alb.tf            # Application Load Balancer
│   ├── ecs.tf            # ECS cluster, task definitions, services
│   ├── ecr.tf            # Container registries
│   ├── messaging.tf      # SNS and SQS
│   ├── lambda.tf         # Lambda function (Part III)
│   └── security_groups.tf # Security groups
├── src/
│   ├── receiver/          # Order receiver service
│   │   ├── main.go       # Go HTTP server with sync/async endpoints
│   │   ├── Dockerfile    # Container image
│   │   ├── locust_sync.py    # Load test for sync endpoint
│   │   └── locust_async.py   # Load test for async endpoint
│   └── processor/         # ECS order processor
│       ├── main.go       # SQS poller with goroutine workers
│       └── Dockerfile    # Container image
└── scripts/
    └── deploy_images_and_update.ps1  # Docker build/push helper
```

## Deployment

### Prerequisites
- AWS CLI configured
- Terraform installed
- Docker installed
- Go 1.23+

### Terraform Automated Deployment
The infrastructure is configured to automatically:
- Create ECR repositories
- Build Docker images from source code
- Push images to ECR with `:latest` tag
- Deploy ECS services with automatic updates when code changes

**Key Features:**
- **Zero-touch deployment**: Single `terraform apply` command
- **Automatic image updates**: Code changes trigger new builds
- **Immutable deployments**: Uses `:latest` tag for rolling updates
- **Dependency management**: Services wait for images before deployment

**Triggers for rebuilds:**
- Changes to `src/receiver/main.go` or `Dockerfile`
- Changes to `src/processor/main.go` or `Dockerfile`

### Manual Deployment (Alternative)
```bash
# 1. Build and push Docker images manually
cd src/receiver
docker build -t ordersystem-receiver:local .
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 211125751164.dkr.ecr.us-west-2.amazonaws.com
docker tag ordersystem-receiver:local 211125751164.dkr.ecr.us-west-2.amazonaws.com/order-api:latest
docker push 211125751164.dkr.ecr.us-west-2.amazonaws.com/order-api:latest

cd ../processor
docker build -t ordersystem-processor:local .
docker tag ordersystem-processor:local 211125751164.dkr.ecr.us-west-2.amazonaws.com/order-processor:latest
docker push 211125751164.dkr.ecr.us-west-2.amazonaws.com/order-processor:latest

# 2. Deploy infrastructure
cd ../../infra
terraform init
terraform apply

# 3. Get ALB DNS name
terraform output alb_dns_name
```

## Testing

### Health Check
```bash
curl http://<ALB-DNS>/health
# Expected: OK (200)
```

### Synchronous Order Processing
```bash
curl -X POST http://<ALB-DNS>/orders/sync \
  -H "Content-Type: application/json" \
  -d '{"order_id":"001","customer_id":123,"items":[{"product_id":"SKU-001","quantity":1,"price":19.99}]}'
# Expected: 200 OK after ~3 seconds
```

### Asynchronous Order Processing
```bash
curl -X POST http://<ALB-DNS>/orders/async \
  -H "Content-Type: application/json" \
  -d '{"order_id":"002","customer_id":123,"items":[{"product_id":"SKU-001","quantity":1,"price":19.99}]}'
# Expected: 202 Accepted immediately
```

### Load Testing with Locust
```bash
cd src/receiver

# Test sync endpoint
locust -f locust_sync.py --host http://<ALB-DNS> --headless --users 20 --spawn-rate 1 --run-time 60s

# Test async endpoint
locust -f locust_async.py --host http://<ALB-DNS> --headless --users 30 --spawn-rate 10 --run-time 60s
```

## Monitoring

### SQS Queue Depth
```bash
aws sqs get-queue-attributes \
  --queue-url https://sqs.us-west-2.amazonaws.com/211125751164/order-processing-queue \
  --attribute-names ApproximateNumberOfMessages \
  --region us-west-2
```

### ECS Processor Logs
```bash
# From PowerShell (recommended)
aws logs tail /ecs/order-processor --region us-west-2 --since 5m

# Or specify the full log group name
aws logs tail "/ecs/order-processor" --region us-west-2 --since 5m
```

## Configuration

### Scaling Processor Concurrency (Part II)
Update `PROCESSOR_CONCURRENCY` environment variable:
```bash
aws ecs update-service \
  --cluster ordersystem-cluster \
  --service order-processor-svc \
  --force-new-deployment \
  --region us-west-2
```

Or modify `infra/variables.tf`:
```hcl
variable "processor_concurrency" {
  default = 100  # Adjust based on load testing
}
```

## Performance Analysis

### Processing Capacity
- **1 worker**: 0.33 orders/sec (1 order per 3s)
- **20 workers**: 6.67 orders/sec
- **100 workers**: 33.3 orders/sec

### Cost Estimate (10,000 orders/month)
- **ECS**: ~$17/month (2 tasks always running)

## Key Learnings
1. **Sync vs Async**: Async architecture accepts orders 100x faster but requires queue management
2. **Queue Management**: Monitor `ApproximateNumberOfMessagesVisible` to prevent backlog
3. **Worker Scaling**: Match processing capacity to ingestion rate (need ~60 workers for 60 orders/sec at 3s processing time)
4. **Concurrency Tuning**: Adjust `PROCESSOR_CONCURRENCY` environment variable to scale processing capacity

## Cleanup
```bash
cd infra
terraform destroy -auto-approve
```

## License
Educational project for CS6650 - Building Scalable Distributed Systems
