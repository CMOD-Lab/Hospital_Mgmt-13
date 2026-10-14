#!/bin/bash
# =============================================================
# build-push.sh — Build and push Docker image for DBProject
# Application: Clinic Management System (ASP.NET Web Forms)
# Usage: ./scripts/build-push.sh
# Run from repository root directory
# =============================================================
set -e

PROJECT_NAME="dbproject"
DOCKERFILE_PATH="Code/DBProject/Dockerfile"

echo "=============================================="
echo " DBProject — Docker Build & Push"
echo "=============================================="
echo ""

# ── Sanitize project name for Docker tag compliance ──────────
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

# ── Prompt for image tag ──────────────────────────────────────
read -rp "Enter image tag [latest]: " IMAGE_TAG_INPUT
IMAGE_TAG=$(echo "${IMAGE_TAG_INPUT:-latest}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//')
if [ -z "$IMAGE_TAG" ]; then
  IMAGE_TAG="latest"
fi
echo "  Image tag: $IMAGE_TAG"
echo ""

# ── Registry selection ────────────────────────────────────────
echo "Select container registry:"
echo "  1. AWS ECR"
echo "  2. Docker Hub"
read -rp "Enter choice [1]: " REGISTRY_CHOICE
REGISTRY_CHOICE="${REGISTRY_CHOICE:-1}"

if [ "$REGISTRY_CHOICE" = "1" ]; then
  # ── AWS ECR ──────────────────────────────────────────────────
  echo ""
  echo "── AWS ECR Configuration ──"
  read -rp "Enter AWS Region (e.g. us-east-1): " AWS_REGION
  read -rp "Enter AWS Account ID: " AWS_ACCOUNT_ID
  read -rp "Enter ECR repository name [$IMAGE_NAME]: " ECR_REPO_INPUT
  ECR_REPO="${ECR_REPO_INPUT:-$IMAGE_NAME}"

  REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"

  echo ""
  echo "Logging in to AWS ECR..."
  aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$REGISTRY_URL"

  # Auto-create ECR repository if it does not exist
  echo "Checking ECR repository '$ECR_REPO'..."
  aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"
  echo "ECR repository ready."

elif [ "$REGISTRY_CHOICE" = "2" ]; then
  # ── Docker Hub ───────────────────────────────────────────────
  echo ""
  echo "── Docker Hub Configuration ──"
  read -rp "Enter Docker Hub username: " DOCKER_USERNAME
  read -rsp "Enter Docker Hub password/token: " DOCKER_PASSWORD
  echo ""
  read -rp "Enter Docker Hub repository [$DOCKER_USERNAME/$IMAGE_NAME]: " DOCKERHUB_REPO_INPUT
  DOCKERHUB_REPO="${DOCKERHUB_REPO_INPUT:-$DOCKER_USERNAME/$IMAGE_NAME}"

  FULL_IMAGE_NAME="${DOCKERHUB_REPO}:${IMAGE_TAG}"

  echo ""
  echo "Logging in to Docker Hub..."
  echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin

else
  echo "ERROR: Invalid registry choice '$REGISTRY_CHOICE'. Exiting."
  exit 1
fi

echo ""
echo "Building Docker image..."
echo "  Image : $FULL_IMAGE_NAME"
echo "  Context: . (repository root)"
echo "  Dockerfile: $DOCKERFILE_PATH"
echo ""

docker build \
  -f "$DOCKERFILE_PATH" \
  -t "$FULL_IMAGE_NAME" \
  .

echo ""
echo "Pushing image to registry..."
docker push "$FULL_IMAGE_NAME"

echo ""
echo "=============================================="
echo " Build & Push Complete!"
echo " Image: $FULL_IMAGE_NAME"
echo "=============================================="
