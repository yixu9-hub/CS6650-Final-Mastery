output "sns_topic_arn" {
  description = "SNS topic ARN"
  value       = aws_sns_topic.order_events.arn
}

output "sqs_queue_url" {
  description = "SQS queue URL"
  value       = aws_sqs_queue.order_queue.id
}

output "sqs_queue_arn" {
  description = "SQS queue ARN"
  value       = aws_sqs_queue.order_queue.arn
}

output "sqs_dlq_url" {
  description = "Dead Letter Queue URL"
  value       = aws_sqs_queue.order_dlq.id
}

output "sqs_dlq_arn" {
  description = "Dead Letter Queue ARN"
  value       = aws_sqs_queue.order_dlq.arn
}

output "ecs_cluster_name" {
  value = var.create_ecs ? aws_ecs_cluster.cluster[0].name : "N/A"
}

output "alb_dns_name" {
  description = "ALB DNS name (present only if create_alb = true)"
  value       = var.create_alb ? aws_lb.alb[0].dns_name : ""
}

output "order_api_repo_url" {
  description = "ECR repository URL for the order API"
  value       = var.create_ecr ? aws_ecr_repository.order_api[0].repository_url : "N/A"
}

output "order_processor_repo_url" {
  description = "ECR repository URL for the order processor"
  value       = var.create_ecr ? aws_ecr_repository.order_processor[0].repository_url : "N/A"
}
