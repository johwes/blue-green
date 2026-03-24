#!/bin/bash

# Blue-Green Demo - Switch Traffic to Blue (OpenShift)
# This script updates the service selector to route traffic to blue (rollback)

set -e

echo "======================================="
echo "Switching Traffic to Blue Environment"
echo "======================================="

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SERVICE_NAME="bluegreen-demo"

echo -e "\n${YELLOW}Current service configuration:${NC}"
oc get svc ${SERVICE_NAME} -o jsonpath='{.spec.selector}' | jq .

echo -e "\n${BLUE}Patching service to route to blue...${NC}"
oc patch svc ${SERVICE_NAME} -p '{"spec":{"selector":{"version":"blue"}}}'

echo -e "\n${GREEN}Traffic switched to blue!${NC}"

echo -e "\n${BLUE}New service configuration:${NC}"
oc get svc ${SERVICE_NAME} -o jsonpath='{.spec.selector}' | jq .

echo -e "\n${BLUE}Service endpoints (should show blue pods):${NC}"
oc get endpoints ${SERVICE_NAME}

echo -e "\n${BLUE}Verifying version:${NC}"
sleep 2

# Get the route URL
ROUTE=$(oc get route ${SERVICE_NAME} -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [ -n "$ROUTE" ]; then
  echo -e "\n${BLUE}Testing endpoint:${NC}"
  curl -s http://${ROUTE}/version | jq .
  echo ""
  echo -e "${GREEN}Application is now serving BLUE (v1.0)${NC}"
  echo "Full URL: http://${ROUTE}"
else
  echo -e "\n${YELLOW}Route not found. Check with:${NC}"
  echo "oc get route ${SERVICE_NAME}"
fi

echo -e "\n${GREEN}Done!${NC}"
