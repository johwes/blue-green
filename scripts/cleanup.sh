#!/bin/bash

# Blue-Green Demo - Cleanup
# This script removes all resources created by the demo

set -e

echo "======================================="
echo "Cleaning Up Blue-Green Demo Resources"
echo "======================================="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE=${NAMESPACE:-default}

echo -e "\n${YELLOW}This will delete:${NC}"
echo "  - Blue deployment"
echo "  - Green deployment"
echo "  - Service"
echo ""
read -p "Are you sure you want to continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cancelled"
  exit 1
fi

echo -e "\n${RED}Deleting service...${NC}"
kubectl delete svc bluegreen-demo -n ${NAMESPACE} --ignore-not-found=true

echo -e "\n${RED}Deleting blue deployment...${NC}"
kubectl delete deployment bluegreen-demo-blue -n ${NAMESPACE} --ignore-not-found=true

echo -e "\n${RED}Deleting green deployment...${NC}"
kubectl delete deployment bluegreen-demo-green -n ${NAMESPACE} --ignore-not-found=true

echo -e "\n${GREEN}Cleanup complete!${NC}"

echo -e "\n${YELLOW}Remaining resources:${NC}"
kubectl get all -l app=bluegreen-demo -n ${NAMESPACE}
