#!/bin/bash

# Blue-Green Demo - Deploy Green Environment
# This script builds and deploys the green version (v2.0)

set -e

echo "===================================="
echo "Deploying Green Environment (v2.0)"
echo "===================================="

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE=${NAMESPACE:-default}
IMAGE_NAME="bluegreen-demo"
VERSION="v2.0"

echo -e "\n${BLUE}Step 1: Building Docker image${NC}"
docker build -t ${IMAGE_NAME}:${VERSION} ../app/

echo -e "\n${BLUE}Step 2: Loading image to Kubernetes cluster (if using kind/minikube)${NC}"
# Uncomment the appropriate line for your cluster type:
# kind load docker-image ${IMAGE_NAME}:${VERSION}
# minikube image load ${IMAGE_NAME}:${VERSION}
echo "Skipping - update script for your cluster type"

echo -e "\n${BLUE}Step 3: Deploying green ConfigMap${NC}"
kubectl apply -f ../k8s/configmap-green.yaml -n ${NAMESPACE}

echo -e "\n${BLUE}Step 4: Deploying green deployment${NC}"
kubectl apply -f ../k8s/deployment-green.yaml -n ${NAMESPACE}

echo -e "\n${BLUE}Step 5: Waiting for green deployment to be ready${NC}"
kubectl rollout status deployment/bluegreen-demo-green -n ${NAMESPACE}

echo -e "\n${GREEN}Green environment deployed successfully!${NC}"

echo -e "\n${BLUE}Current pods:${NC}"
kubectl get pods -l app=bluegreen-demo,version=green -n ${NAMESPACE}

echo -e "\n${BLUE}Configuration loaded:${NC}"
kubectl get configmap bluegreen-demo-config-green -n ${NAMESPACE}

echo -e "\n${BLUE}To test the green environment before switching:${NC}"
echo "kubectl port-forward deployment/bluegreen-demo-green 8081:3000 -n ${NAMESPACE}"
echo "Then visit: http://localhost:8081"
echo ""
echo -e "${BLUE}To compare configurations:${NC}"
echo "curl http://localhost:8081/config  # Green config"
echo "# Compare with blue by port-forwarding to blue on 8080"
echo ""
echo -e "${BLUE}To switch traffic to green:${NC}"
echo "./switch-to-green.sh"
