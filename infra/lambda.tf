// Lambda function for order processing (Part III)
// This Lambda function subscribes directly to SNS, eliminating the need for SQS and ECS workers

resource "aws_lambda_function" "order_processor_lambda" {
  count = fileexists("${path.module}/../lambda/lambda.zip") ? 1 : 0
  
  filename         = "${path.module}/../lambda/lambda.zip"
  function_name    = "order-processor-lambda"
  role            = var.ecs_task_role_arn
  handler         = "bootstrap"  // Go custom runtime uses "bootstrap" as handler
  runtime         = "provided.al2"  // Go custom runtime
  memory_size     = 512
  timeout         = 10  // 10 seconds (3s processing + buffer)

  source_code_hash = fileexists("${path.module}/../lambda/lambda.zip") ? filebase64sha256("${path.module}/../lambda/lambda.zip") : null

  environment {
    variables = {
      PAYMENT_SIM_SECONDS = "3"
    }
  }

  tags = {
    project = "ordersystem"
    env     = "dev"
    part    = "III"
  }
}

// Allow SNS to invoke Lambda
resource "aws_lambda_permission" "allow_sns" {
  count = length(aws_lambda_function.order_processor_lambda) > 0 ? 1 : 0
  
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.order_processor_lambda[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.order_events.arn
}

// Subscribe Lambda to SNS topic
resource "aws_sns_topic_subscription" "lambda_subscription" {
  count = length(aws_lambda_function.order_processor_lambda) > 0 ? 1 : 0
  
  topic_arn = aws_sns_topic.order_events.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.order_processor_lambda[0].arn
}

// CloudWatch Log Group for Lambda (retention: 7 days)
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count = length(aws_lambda_function.order_processor_lambda) > 0 ? 1 : 0
  
  name              = "/aws/lambda/${aws_lambda_function.order_processor_lambda[0].function_name}"
  retention_in_days = 7

  tags = {
    project = "ordersystem"
    env     = "dev"
  }
}
