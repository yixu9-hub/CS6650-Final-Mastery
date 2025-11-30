param(
    [string]$AwsAccountId = '211125751164',
    [string]$Region = 'us-west-2'
)

Set-Location -Path "$PSScriptRoot/.."

$registry = "$AwsAccountId.dkr.ecr.$Region.amazonaws.com"

Write-Host "Building receiver image..."
Set-Location -Path "src/receiver"
docker build -t ordersystem-receiver:latest -f Dockerfile .

Write-Host "Building processor image..."
Set-Location -Path "../processor"
docker build -t ordersystem-processor:latest -f Dockerfile .

Write-Host "Ensuring ECR repositories exist..."
aws ecr create-repository --repository-name order-api --region $Region 2>$null | Out-Null
aws ecr create-repository --repository-name order-processor --region $Region 2>$null | Out-Null

Write-Host "Logging in to ECR..."
aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $registry

Write-Host "Tagging images..."
docker tag ordersystem-receiver:latest $registry/order-api:latest
docker tag ordersystem-processor:latest $registry/order-processor:latest

Write-Host "Pushing images to ECR..."
docker push $registry/order-api:latest
docker push $registry/order-processor:latest

Write-Host "Forcing ECS services to pick up new images (if cluster/services exist)..."
$clusterName = 'ordersystem-cluster'
aws ecs update-service --cluster $clusterName --service order-receiver-svc --force-new-deployment --region $Region
aws ecs update-service --cluster $clusterName --service order-processor-svc --force-new-deployment --region $Region

Write-Host "Done. Check ECS console or run 'aws ecs describe-services' to verify deployments."
