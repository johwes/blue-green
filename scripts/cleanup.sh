#!/bin/bash

# Blue-Green Demo - Cleanup (OpenShift)
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

echo -e "\n${YELLOW}This will delete:${NC}"
echo "  - Blue deployment"
echo "  - Green deployment"
echo "  - Blue ConfigMap"
echo "  - Green ConfigMap"
echo "  - Service"
echo "  - Route"
echo "  - BuildConfig"
echo "  - ImageStream"
echo ""
read -p "Are you sure you want to continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cancelled"
  exit 1
fi

echo -e "\n${RED}Deleting deployments...${NC}"
oc delete deployment bluegreen-demo-blue --ignore-not-found=true
oc delete deployment bluegreen-demo-green --ignore-not-found=true

echo -e "\n${RED}Deleting ConfigMaps...${NC}"
oc delete configmap bluegreen-demo-config-blue --ignore-not-found=true
oc delete configmap bluegreen-demo-config-green --ignore-not-found=true

echo -e "\n${RED}Deleting service and route...${NC}"
oc delete svc bluegreen-demo --ignore-not-found=true
oc delete route bluegreen-demo --ignore-not-found=true

echo -e "\n${RED}Deleting build resources...${NC}"
oc delete buildconfig bluegreen-demo --ignore-not-found=true
oc delete imagestream bluegreen-demo --ignore-not-found=true

echo -e "\n${GREEN}Cleanup complete!${NC}"

echo -e "\n${YELLOW}Remaining resources:${NC}"
oc get all,configmap -l app=bluegreen-demo
