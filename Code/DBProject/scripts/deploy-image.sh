#!/bin/bash
# =============================================================
# deploy-image.sh — Deploy DBProject to AWS EKS
# Application: Clinic Management System (ASP.NET Web Forms)
# Target: AWS EKS (Windows node group)
# Usage: ./scripts/deploy-image.sh
# Run from repository root directory
# =============================================================
set -e
set -o pipefail

APP_NAME="dbproject"
NAMESPACE="dbproject"
K8S_DIR="Code/DBProject/kubernetes"

echo "=============================================="
echo " DBProject — AWS EKS Deployment"
echo "=============================================="
echo ""

# ── AWS / EKS configuration ───────────────────────────────────
read -rp "Enter AWS Region (e.g. us-east-1): " AWS_REGION
if [ -z "$AWS_REGION" ]; then
  echo "ERROR: AWS Region is required."
  exit 1
fi

read -rp "Enter EKS Cluster Name: " CLUSTER_NAME
if [ -z "$CLUSTER_NAME" ]; then
  echo "ERROR: EKS Cluster Name is required."
  exit 1
fi

# ── Docker image URI ──────────────────────────────────────────
read -rp "Enter full Docker image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/dbproject:latest): " IMAGE_URI
if [ -z "$IMAGE_URI" ]; then
  echo "ERROR: Docker image URI is required."
  exit 1
fi

echo ""
echo "── Application Environment Variables ──"
echo "Press Enter to skip any variable (placeholder will remain in manifest)."
echo ""

read -rp "Enter DB_CONNECTION_STRING (or press Enter to skip): " DB_CONNECTION_STRING
read -rp "Enter DB_HOST (or press Enter to skip): " DB_HOST
read -rp "Enter DB_NAME [DBProject]: " DB_NAME
DB_NAME="${DB_NAME:-DBProject}"
read -rp "Enter DB_USER (or press Enter to skip): " DB_USER
read -rsp "Enter DB_PASSWORD (or press Enter to skip): " DB_PASSWORD
echo ""
read -rp "Enter REDIS_HOST (or press Enter to skip): " REDIS_HOST
read -rp "Enter REDIS_PORT [6379]: " REDIS_PORT
REDIS_PORT="${REDIS_PORT:-6379}"
read -rsp "Enter REDIS_ACCESS_KEY (or press Enter to skip): " REDIS_ACCESS_KEY
echo ""
read -rp "Enter APPINSIGHTS_INSTRUMENTATIONKEY (or press Enter to skip): " APPINSIGHTS_INSTRUMENTATIONKEY

echo ""
echo "── Configuring kubectl for EKS ──"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: Cannot connect to EKS cluster."; exit 1; }

echo ""
echo "── Updating Kubernetes manifests ──"

# Work on copies to avoid modifying originals
cp -r "$K8S_DIR" /tmp/dbproject-k8s-deploy

# Replace image placeholder
sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g" /tmp/dbproject-k8s-deploy/deployment.yaml

# Replace environment variable placeholders
sed -i "s|{{DB_CONNECTION_STRING}}|${DB_CONNECTION_STRING}|g" /tmp/dbproject-k8s-deploy/deployment.yaml
sed -i "s|{{DB_HOST}}|${DB_HOST}|g"                           /tmp/dbproject-k8s-deploy/deployment.yaml
sed -i "s|{{DB_NAME}}|${DB_NAME}|g"                           /tmp/dbproject-k8s-deploy/deployment.yaml
sed -i "s|{{DB_USER}}|${DB_USER}|g"                           /tmp/dbproject-k8s-deploy/deployment.yaml
sed -i "s|{{DB_PASSWORD}}|${DB_PASSWORD}|g"                   /tmp/dbproject-k8s-deploy/deployment.yaml
sed -i "s|{{REDIS_HOST}}|${REDIS_HOST}|g"                     /tmp/dbproject-k8s-deploy/deployment.yaml
sed -i "s|{{REDIS_PORT}}|${REDIS_PORT}|g"                     /tmp/dbproject-k8s-deploy/deployment.yaml
sed -i "s|{{REDIS_ACCESS_KEY}}|${REDIS_ACCESS_KEY}|g"         /tmp/dbproject-k8s-deploy/deployment.yaml
sed -i "s|{{APPINSIGHTS_INSTRUMENTATIONKEY}}|${APPINSIGHTS_INSTRUMENTATIONKEY}|g" /tmp/dbproject-k8s-deploy/deployment.yaml

echo ""
echo "── Applying Kubernetes manifests ──"

echo "1/4 Applying namespace..."
kubectl apply -f /tmp/dbproject-k8s-deploy/namespace.yaml

echo "2/4 Applying deployment..."
kubectl apply -f /tmp/dbproject-k8s-deploy/deployment.yaml

echo "3/4 Applying service..."
kubectl apply -f /tmp/dbproject-k8s-deploy/service.yaml

echo "4/4 Applying ingress..."
kubectl apply -f /tmp/dbproject-k8s-deploy/ingress.yaml

echo ""
echo "── Waiting for deployment rollout ──"
kubectl rollout status deployment/"$APP_NAME" -n "$NAMESPACE" --timeout=300s

echo ""
echo "── Verifying deployed resources ──"
kubectl get pods,svc,ingress -n "$NAMESPACE"

echo ""
echo "── Application Access URL ──"
INGRESS_HOST=$(kubectl get ingress "${APP_NAME}-ingress" -n "$NAMESPACE" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "<pending>")
echo "  Application URL: http://${INGRESS_HOST}"
echo "  Health Check   : http://${INGRESS_HOST}/health"
echo ""
echo "  NOTE: If the URL shows '<pending>', wait a few minutes for the"
echo "        AWS Load Balancer to be provisioned, then run:"
echo "        kubectl get ingress -n $NAMESPACE"
echo ""

# Cleanup temp files
rm -rf /tmp/dbproject-k8s-deploy

echo "=============================================="
echo " Deployment Complete!"
echo " Namespace : $NAMESPACE"
echo " Image     : $IMAGE_URI"
echo "=============================================="
echo ""
echo "Rollback command (if needed):"
echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
