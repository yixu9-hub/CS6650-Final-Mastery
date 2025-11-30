// ECS Cluster
resource "aws_ecs_cluster" "cluster" {
  name = "ordersystem-cluster"
}

// ECS Task Definitions (placeholders for container definitions)
resource "aws_ecs_task_definition" "order_receiver" {
  family                   = "order-receiver"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn

  container_definitions = jsonencode([
    {
      name  = "order-receiver"
      image = "${aws_ecr_repository.order_api.repository_url}:latest"
      essential = true
      portMappings = [ { containerPort = 8080, hostPort = 8080, protocol = "tcp" } ]
      environment = [ { name = "SNS_TOPIC_ARN", value = aws_sns_topic.order_events.arn } ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/order-receiver"
          "awslogs-region"        = "us-west-2"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "order_processor" {
  family                   = "order-processor"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn

  container_definitions = jsonencode([
    {
      name  = "order-processor"
      image = "${aws_ecr_repository.order_processor.repository_url}:latest"
      essential = true
      environment = [ 
        { name = "SQS_QUEUE_URL", value = aws_sqs_queue.order_queue.id },
        { name = "PROCESSOR_CONCURRENCY", value = tostring(var.processor_concurrency) }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/order-processor"
          "awslogs-region"        = "us-west-2"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

// ECS Services
resource "aws_ecs_service" "order_receiver_svc" {
  depends_on = [null_resource.build_and_push_images]

  name            = "order-receiver-svc"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.order_receiver.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.create_alb ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.orders_api_tg[0].arn
      container_name   = "order-receiver"
      container_port   = 8080
    }
  }

  triggers = {
    redeployment = aws_ecs_task_definition.order_receiver.revision
  }
}

resource "aws_ecs_service" "order_processor_svc" {
  depends_on = [null_resource.build_and_push_images]

  name            = "order-processor-svc"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.order_processor.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  triggers = {
    redeployment = aws_ecs_task_definition.order_processor.revision
  }
}
