# LocalStack Pro Environment Configuration
environment              = "localstack"
region                   = "us-west-2"
aws_endpoint             = "http://localhost:4566"
visibility_timeout       = 30
message_retention_period = 3600
receive_wait_time        = 20
payment_sim_seconds      = 3
processor_concurrency    = 2

# LocalStack Pro
create_alb               = true
create_ecr               = true
create_ecs               = true
create_vpc               = true
