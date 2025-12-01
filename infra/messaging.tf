// Messaging: SNS topic + SQS queue
resource "aws_sns_topic" "order_events" {
  name = "order-processing-events-${var.environment}"

  tags = {
    Environment = var.environment
    Purpose     = "Order processing experiments"
  }
}

// Dead Letter Queue for failed messages
resource "aws_sqs_queue" "order_dlq" {
  name                      = "order-processing-dlq-${var.environment}"
  message_retention_seconds = 1209600 // 14 days

  tags = {
    Environment = var.environment
    Purpose     = "Order processing DLQ"
  }
}

resource "aws_sqs_queue" "order_queue" {
  name                       = "order-processing-queue-${var.environment}"
  visibility_timeout_seconds = var.visibility_timeout
  message_retention_seconds  = var.message_retention_period
  receive_wait_time_seconds  = var.receive_wait_time

  // Configure Dead Letter Queue
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.order_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Environment = var.environment
    Purpose     = "Order processing experiments"
  }
}

// Allow SNS topic to send messages to the SQS queue
data "aws_iam_policy_document" "sqs_allow_sns" {
  statement {
    principals {
      type = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    actions = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.order_queue.arn]
    condition {
      test = "ArnEquals"
      values = [aws_sns_topic.order_events.arn]
      variable = "aws:SourceArn"
    }
  }
}

resource "aws_sqs_queue_policy" "allow_sns" {
  queue_url = aws_sqs_queue.order_queue.id
  policy    = data.aws_iam_policy_document.sqs_allow_sns.json
}

resource "aws_sns_topic_subscription" "sns_to_sqs" {
  topic_arn = aws_sns_topic.order_events.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.order_queue.arn
  raw_message_delivery = false  // Keep SNS envelope for processor to parse
}
