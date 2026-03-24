#!/bin/bash

# Blue-Green Demo - Deploy Blue Environment
# This script builds and deploys the blue version (v1.0)

set -e

echo "==================================="
echo "Deploying Blue Environment (v1.0)"
echo "==================================="

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE=${NAMESPACE:-default}
IMAGE_NAME="bluegreen-demo"
VERSION="v1.0"

echo -e "\n${BLUE}Step 1: Building Docker image${NC}"
docker build -t ${IMAGE_NAME}:${VERSION} ../app/

echo -e "\n${BLUE}Step 2: Loading image to Kubernetes cluster (if using kind/minikube)${NC}"
# Uncomment the appropriate line for your cluster type:
# kind load docker-image ${IMAGE_NAME}:${VERSION}
# minikube image load ${IMAGE_NAME}:${VERSION}
echo "Skipping - update script for your cluster type"

echo -e "\n${BLUE}Step 3: Deploying blue ConfigMap${NC}"
kubectl apply -f ../k8s/configmap-blue.yaml -n ${NAMESPACE}

echo -e "\n${BLUE}Step 4: Deploying blue deployment${NC}"
kubectl apply -f ../k8s/deployment-blue.yaml -n ${NAMESPACE}

echo -e "\n${BLUE}Step 5: Waiting for blue deployment to be ready${NC}"
kubectl rollout status deployment/bluegreen-demo-blue -n ${NAMESPACE}

echo -e "\n${GREEN}Blue environment deployed successfully!${NC}"

echo -e "\n${BLUE}Current pods:${NC}"
kubectl get pods -l app=bluegreen-demo,version=blue -n ${NAMESPACE}

echo -e "\n${BLUE}Configuration loaded:${NC}"
kubectl get configmap bluegreen-demo-config-blue -n ${NAMESPACE}

echo -e "\n${BLUE}To access the blue environment directly:${NC}"
echo "kubectl port-forward deployment/bluegreen-demo-blue 8080:3000 -n ${NAMESPACE}"
echo "Then visit: http://localhost:8080"
echo ""
echo -e "${BLUE}To view configuration:${NC}"
echo "curl http://localhost:8080/config"
