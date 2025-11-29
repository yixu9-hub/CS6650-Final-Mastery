output "sns_topic_arn" {
  description = "SNS topic ARN"
  value       = aws_sns_topic.order_events.arn
}

output "sqs_queue_url" {
  description = "SQS queue URL"
  value       = aws_sqs_queue.order_queue.id
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.cluster.name
}

output "alb_dns_name" {
  description = "ALB DNS name (present only if create_alb = true)"
  value       = var.create_alb ? aws_lb.alb[0].dns_name : ""
}

output "order_api_repo_url" {
  description = "ECR repository URL for the order API"
  value       = aws_ecr_repository.order_api.repository_url
}

output "order_processor_repo_url" {
  description = "ECR repository URL for the order processor"
  value       = aws_ecr_repository.order_processor.repository_url
}
