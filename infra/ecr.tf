// ECR repositories for the ordersystem project
resource "aws_ecr_repository" "order_api" {
  name                 = "order-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  tags = {
    project = "ordersystem"
    env     = "dev"
  }
}

resource "aws_ecr_repository" "order_processor" {
  name                 = "order-processor"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  tags = {
    project = "ordersystem"
    env     = "dev"
  }
}

// Build and push Docker images
resource "null_resource" "build_and_push_images" {
  depends_on = [aws_ecr_repository.order_api, aws_ecr_repository.order_processor]

  triggers = {
    receiver_source = filemd5("../src/receiver/main.go")
    processor_source = filemd5("../src/processor/main.go")
    receiver_dockerfile = filemd5("../src/receiver/Dockerfile")
    processor_dockerfile = filemd5("../src/processor/Dockerfile")
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command = <<-EOT
      # Build and push receiver image
      Set-Location ../src/receiver
      docker build -t ${aws_ecr_repository.order_api.repository_url}:latest .
      aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin ${split("/", aws_ecr_repository.order_api.repository_url)[0]}
      docker push ${aws_ecr_repository.order_api.repository_url}:latest

      # Build and push processor image
      Set-Location ../src/processor
      docker build -t ${aws_ecr_repository.order_processor.repository_url}:latest .
      docker push ${aws_ecr_repository.order_processor.repository_url}:latest
    EOT
  }
}
