variable "environment" {
  description = "Environment name: localstack or aws"
  type        = string
  default     = "aws"
}

variable "aws_endpoint" {
  description = "AWS endpoint URL (for LocalStack, e.g., http://localhost:4566)"
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "create_alb" {
  description = "Whether to create an Application Load Balancer"
  type        = bool
  default     = true
}

variable "lab_role_arn" {
  description = "ARN of the Lab-provided IAM role. Use this for ECS task and execution roles (lab provided)."
  type        = string
  default     = "arn:aws:iam::211125751164:role/LabRole"
}

variable "ecs_task_execution_role_arn" {
  description = "Execution role ARN for ECS tasks (provided by lab)."
  type        = string
  default     = "arn:aws:iam::211125751164:role/LabRole"
}

variable "ecs_task_role_arn" {
  description = "Task role ARN for ECS tasks (provided by lab)."
  type        = string
  default     = "arn:aws:iam::211125751164:role/LabRole"
}

variable "processor_concurrency" {
  description = "Number of concurrent workers the processor should run by default"
  type        = number
  default     = 2
}

variable "visibility_timeout" {
  description = "Visibility timeout for SQS messages (seconds)"
  type        = number
  default     = 30
}

variable "message_retention_period" {
  description = "Message retention period (seconds)"
  type        = number
  default     = 3600
}

variable "receive_wait_time" {
  description = "Long polling wait time (seconds)"
  type        = number
  default     = 20
}

variable "payment_sim_seconds" {
  description = "Payment simulation duration in seconds"
  type        = number
  default     = 3
}

variable "create_ecr" {
  description = "Whether to create ECR repositories"
  type        = bool
  default     = true
}

variable "create_ecs" {
  description = "Whether to create ECS cluster and services"
  type        = bool
  default     = true
}

variable "create_vpc" {
  description = "Whether to create VPC and networking resources"
  type        = bool
  default     = true
}
