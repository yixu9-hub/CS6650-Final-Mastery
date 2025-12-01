# CS6650 Final Mastery - LocalStack vs AWS Performance Comparison

## Project Overview
This project implements a comparative study of LocalStack Pro and AWS for asynchronous order processing systems, measuring latency, throughput, and architectural differences.

## Architecture

### Unified ECS + SNS/SQS Architecture
Both environments use identical architecture for fair comparison:
- **Order Receiver** (ECS Fargate): Handles `/orders/async` endpoint
- **Order Processor** (ECS Fargate): Polls SQS and processes orders with configurable concurrency
- **Message Flow**: API → SNS → SQS → ECS Processor
- **Monitoring**: CloudWatch Logs, Metrics collection to CSV

## Infrastructure Components
- **VPC**: 10.0.0.0/16 with public (10.0.1.0/24, 10.0.2.0/24) and private subnets (10.0.10.0/24, 10.0.11.0/24)
- **ALB**: Application Load Balancer for order receiver service
- **ECR**: Docker image repositories for receiver and processor
- **SNS/SQS**: Message queue infrastructure


## Deployment

### LocalStack Pro Setup (Recommended for Development)
For enhanced local development with full AWS service compatibility:

1. **Get LocalStack Pro License** (Free for students):
   - Visit: https://app.localstack.cloud/
   - Sign up with your student email
   - Get your API key from the dashboard

2. **Configure LocalStack Pro**:
   ```bash
   # Run the setup script
   .\scripts\setup-localstack-pro.ps1
   
   # Or manually edit .env file
   # Add your API key: LOCALSTACK_API_KEY=your_key_here
   ```

3. **Start LocalStack**:
   ```bash
   .\scripts\01-start-localstack.ps1
   ```

4. **Deploy Services**:
   ```bash
   .\scripts\deploy-localstack.ps1
   ```

## Prerequisites

### Required Software
- **Docker Desktop** (with WSL 2 enabled on Windows)
- **Terraform** >= 1.3.0
- **AWS CLI** configured with credentials
- **Go** >= 1.23 (for local builds)
- **Python** >= 3.8 (for Locust load testing and analysis)
- **PowerShell** 7+ (recommended for Windows)

### Required Credentials
- **AWS Account**: For real AWS deployment
  - Configure with `aws configure`
  - Ensure IAM permissions for ECS, ECR, VPC, ALB, SNS, SQS
- **LocalStack Pro License** (Free for students):
  - Sign up at: https://app.localstack.cloud/
  - Get your auth token from the dashboard
  - Add to environment: `LOCALSTACK_AUTH_TOKEN=ls-xxx...`

### Verify Installation
```powershell
docker --version
terraform --version
aws --version
go version
python --version
locust --version  # pip install locust if missing
```

## Quick Start (Recommended)

### Option 1: Interactive Menu
```powershell
.\quick-start.ps1
```
This launches an interactive menu to:
- Setup and start LocalStack environment
- Deploy to LocalStack (with ECS services)
- Deploy to AWS (with confirmation)
- Run experiments and load tests
- Analyze results and generate visualizations

### Option 2: Manual Step-by-Step

#### Deploy LocalStack Environment
```powershell
# 1. Start LocalStack container
.\scripts\01-start-localstack.ps1

# 2. Deploy infrastructure and ECS services
.\scripts\deploy-localstack.ps1

# 3. Verify deployment
curl http://localhost:8080/health
# Expected: OK

# 4. Test order processing
$body = @{order_id="test-001"; customer_id=123; items=@(@{product_id="p1"; quantity=2; price=10.5})} | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:8080/orders/async" -Method Post -Body $body -ContentType "application/json"
```

#### Deploy AWS Environment
```powershell
# 1. Build and push Docker images to ECR
.\scripts\push-images-to-ecr.ps1

# 2. Deploy infrastructure with Terraform
cd infra
terraform workspace select aws  # Create if doesn't exist
terraform apply -var-file="aws.tfvars" -auto-approve

# 3. Get ALB DNS name
terraform output alb_dns_name
# Output: ordersystem-alb-xxx.us-west-2.elb.amazonaws.com

# 4. Test AWS deployment (wait ~2 minutes for tasks to start)
curl http://ordersystem-alb-xxx.us-west-2.elb.amazonaws.com/health
```

### Automated Deployment Details
**LocalStack**: Terraform creates ECS services that run as Docker containers via LocalStack
**AWS**: Images must be in ECR before ECS services can start
- Use `.\scripts\push-images-to-ecr.ps1` to build and push images
- Terraform creates all infrastructure including ECS services

### Manual Image Build (If Needed)
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

## Testing & Experiments

### Quick Health Check
```powershell
# LocalStack
curl http://localhost:8080/health

# AWS
curl http://ordersystem-alb-xxx.us-west-2.elb.amazonaws.com/health
```

### Send Test Orders
```powershell
# LocalStack
$body = @{order_id="test-001"; customer_id=123; items=@(@{product_id="p1"; quantity=2; price=10.5})} | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:8080/orders/async" -Method Post -Body $body -ContentType "application/json"

# AWS
$body = @{order_id="test-002"; customer_id=456; items=@(@{product_id="p2"; quantity=1; price=25.99})} | ConvertTo-Json
Invoke-RestMethod -Uri "http://ordersystem-alb-xxx.us-west-2.elb.amazonaws.com/orders/async" -Method Post -Body $body -ContentType "application/json"
```

### Load Testing with Locust
```powershell
# LocalStack load test
locust -f locustfile/locust_async.py --host=http://localhost:8080

# AWS load test
locust -f locustfile/locust_async.py --host=http://ordersystem-alb-xxx.us-west-2.elb.amazonaws.com

# Access Locust web UI at: http://localhost:8089
# Recommended test: 100 users, spawn rate 10
```

### Run Automated Experiments
```powershell
# Run latency experiments
.\scripts\04-run-experiments.ps1 -Experiment latency

# Run all experiments
.\scripts\04-run-experiments.ps1 -Experiment all -Environment both
```

### View Metrics and Logs
```powershell
# View processor metrics (CSV files)
cat results/localstack/metrics_*.csv
cat results/aws/metrics_*.csv

# View ECS container logs (LocalStack)
docker ps  # Find container names starting with ls-ecs-
docker logs -f <container-name>

# View ECS logs (AWS)
aws logs tail /ecs/order-processor --region us-west-2 --since 5m --follow
aws logs tail /ecs/order-receiver --region us-west-2 --since 5m --follow
```

## Monitoring & Debugging

### Check ECS Services Status
```powershell
# LocalStack ECS services
.\scripts\check-ecs-status.ps1 -Environment localstack

# AWS ECS services
.\scripts\check-ecs-status.ps1 -Environment aws
# Or: aws ecs describe-services --cluster ordersystem-cluster --services order-receiver-svc order-processor-svc --region us-west-2
```

### Monitor Queue Depth
```powershell
# LocalStack
aws sqs get-queue-attributes --queue-url http://sqs.us-west-2.localhost.localstack.cloud:4566/000000000000/order-processing-queue-localstack --attribute-names ApproximateNumberOfMessages --endpoint-url http://localhost:4566 --region us-west-2

# AWS
aws sqs get-queue-attributes --queue-url https://sqs.us-west-2.amazonaws.com/211125751164/order-processing-queue-aws --attribute-names ApproximateNumberOfMessages --region us-west-2
```

### View Container/Task Logs
```powershell
# LocalStack (Docker containers)
docker ps --filter "name=ls-ecs-ordersystem"
docker logs -f <container-name>

# AWS (CloudWatch Logs)
aws logs tail /ecs/order-processor --region us-west-2 --since 10m --follow
```

## Configuration

### Scaling Processor Concurrency
Modify `infra/localstack.tfvars` or `infra/aws.tfvars`:
```hcl
processor_concurrency = 10  # Number of concurrent goroutines per processor
```

Then redeploy:
```powershell
cd infra
terraform apply -var-file="localstack.tfvars" -auto-approve  # For LocalStack
terraform apply -var-file="aws.tfvars" -auto-approve         # For AWS
```

### Adjust Payment Simulation Time
```hcl
payment_sim_seconds = 3  # Seconds to simulate payment processing
```

## Cleanup

### Cleanup LocalStack
```powershell
.\scripts\05-cleanup.ps1 -Environment localstack
```
This will:
1. Destroy Terraform infrastructure
2. Stop and remove LocalStack container

### Cleanup AWS
```powershell
.\scripts\05-cleanup.ps1 -Environment aws
```
**Warning**: This will destroy all AWS resources (VPC, ECS, ALB, etc.)

### Cleanup Both Environments
```powershell
.\scripts\05-cleanup.ps1 -Environment both
```

## References
- [LocalStack Documentation](https://docs.localstack.cloud/)
- [AWS ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## License
Educational project for CS6650 - Building Scalable Distributed Systems

## Contributors
- Yi Xu (@yixu9-hub)
