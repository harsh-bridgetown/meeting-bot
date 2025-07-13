#!/usr/bin/env bash

# Deploy Attendee to AWS using ECS Fargate.
# Prerequisites:
#   - AWS CLI and Docker installed
#   - AWS credentials configured (via environment variables or AWS profile)
#   - An ECS cluster and service already created to run the container
#   - An IAM execution role and task role for ECS tasks

set -euo pipefail

# Configuration
AWS_REGION=${AWS_REGION:-us-east-1}
ECR_REPO_NAME=${ECR_REPO_NAME:-attendee}
IMAGE_TAG=${IMAGE_TAG:-latest}
ECS_CLUSTER=${ECS_CLUSTER:-attendee-cluster}
ECS_SERVICE=${ECS_SERVICE:-attendee-service}
ECS_TASK_FAMILY=${ECS_TASK_FAMILY:-attendee-task}
EXECUTION_ROLE_ARN=${EXECUTION_ROLE_ARN:?Set EXECUTION_ROLE_ARN}
TASK_ROLE_ARN=${TASK_ROLE_ARN:?Set TASK_ROLE_ARN}

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
IMAGE_URI="$ECR_URI/$ECR_REPO_NAME:$IMAGE_TAG"

# Create ECR repository if it doesn't exist
if ! aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    aws ecr create-repository --repository-name "$ECR_REPO_NAME" --region "$AWS_REGION"
fi

# Authenticate Docker to ECR
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_URI"

# Build and push Docker image
docker build -t "$ECR_REPO_NAME:$IMAGE_TAG" .
docker tag "$ECR_REPO_NAME:$IMAGE_TAG" "$IMAGE_URI"
docker push "$IMAGE_URI"

echo "Registering new task definition..."

TASK_DEF=$(cat <<TASK
{
  "family": "$ECS_TASK_FAMILY",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "$EXECUTION_ROLE_ARN",
  "taskRoleArn": "$TASK_ROLE_ARN",
  "containerDefinitions": [
    {
      "name": "attendee",
      "image": "$IMAGE_URI",
      "essential": true,
      "portMappings": [
        {"containerPort": 8000, "hostPort": 8000, "protocol": "tcp"}
      ],
      "command": ["gunicorn", "attendee.wsgi", "-b", "0.0.0.0:8000"],
      "environment": [
        {"name": "DJANGO_SETTINGS_MODULE", "value": "attendee.settings.production"}
      ]
    },
    {
      "name": "celery-worker",
      "image": "$IMAGE_URI",
      "essential": false,
      "command": ["celery", "-A", "attendee", "worker", "-l", "INFO"]
    },
    {
      "name": "celery-scheduler",
      "image": "$IMAGE_URI",
      "essential": false,
      "command": ["python", "manage.py", "run_scheduler"]
    }
  ]
}
TASK
)

TASK_DEF_ARN=$(aws ecs register-task-definition --cli-input-json "$TASK_DEF" --query 'taskDefinition.taskDefinitionArn' --output text)

echo "Updating ECS service..."
aws ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" --task-definition "$TASK_DEF_ARN"

echo "Deployment initiated for task definition: $TASK_DEF_ARN"
