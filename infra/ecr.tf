// ECR repositories for the ordersystem project
resource "aws_ecr_repository" "order_api" {
  count                = var.create_ecr ? 1 : 0
  name                 = "order-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  tags = {
    project = "ordersystem"
    env     = "dev"
  }
}

resource "aws_ecr_repository" "order_processor" {
  count                = var.create_ecr ? 1 : 0
  name                 = "order-processor"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  tags = {
    project = "ordersystem"
    env     = "dev"
  }
}

// Build and push Docker images
// Note: Terraform's local-exec has issues with PowerShell piping for Docker login
// Images must be pushed manually using: .\scripts\push-images-to-ecr.ps1
// This null_resource is kept only as a dependency placeholder
resource "null_resource" "build_and_push_images" {
  count      = var.create_ecr ? 1 : 0
  depends_on = [aws_ecr_repository.order_api, aws_ecr_repository.order_processor]

  triggers = {
    receiver_source = filemd5("../src/receiver/main.go")
    processor_source = filemd5("../src/processor/main.go")
    receiver_dockerfile = filemd5("../src/receiver/Dockerfile")
    processor_dockerfile = filemd5("../src/processor/Dockerfile")
    # Add manual trigger to skip auto-build
    manual_push = "true"
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    working_dir = path.module
    command = <<-EOT
      Write-Host "========================================" -ForegroundColor Cyan
      Write-Host "ECR Image Push Required" -ForegroundColor Yellow
      Write-Host "========================================" -ForegroundColor Cyan
      Write-Host ""
      Write-Host "Please run the following command to push images:" -ForegroundColor Yellow
      Write-Host "  cd .." -ForegroundColor White
      Write-Host "  .\scripts\push-images-to-ecr.ps1" -ForegroundColor White
      Write-Host ""
      Write-Host "Then re-run terraform apply" -ForegroundColor Yellow
      Write-Host ""
      
      # Check if images already exist in ECR
      $apiImages = aws ecr list-images --repository-name order-api --region us-west-2 --query 'imageIds[?imageTag==``latest``]' --output json | ConvertFrom-Json
      $procImages = aws ecr list-images --repository-name order-processor --region us-west-2 --query 'imageIds[?imageTag==``latest``]' --output json | ConvertFrom-Json
      
      if ($apiImages.Count -gt 0 -and $procImages.Count -gt 0) {
        Write-Host "✓ Images found in ECR - continuing deployment" -ForegroundColor Green
        exit 0
      } else {
        Write-Host "✗ Images not found in ECR - please push images first" -ForegroundColor Red
        Write-Host "Run: .\scripts\push-images-to-ecr.ps1" -ForegroundColor Yellow
        # Don't fail - just warn
        exit 0
      }
    EOT
  }
}
