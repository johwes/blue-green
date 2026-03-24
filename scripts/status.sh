#!/bin/bash

# Blue-Green Demo - Show Current Status (OpenShift)
# This script displays the current state of the deployment

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
SERVICE_NAME="bluegreen-demo"

echo "======================================="
echo "Blue-Green Deployment Status"
echo "======================================="

echo -e "\n${BLUE}Service Configuration:${NC}"
oc get svc ${SERVICE_NAME} -o wide 2>/dev/null || echo "Service not found"

ACTIVE_VERSION=$(oc get svc ${SERVICE_NAME} -o jsonpath='{.spec.selector.version}' 2>/dev/null || echo "unknown")
echo -e "\n${GREEN}Active Version: ${ACTIVE_VERSION}${NC}"

echo -e "\n${BLUE}Route (External Access):${NC}"
oc get route ${SERVICE_NAME} 2>/dev/null || echo "Route not found"
ROUTE=$(oc get route ${SERVICE_NAME} -o jsonpath='{.spec.host}' 2>/dev/null || echo "not-created")
if [ "$ROUTE" != "not-created" ]; then
  echo "URL: http://$ROUTE"
fi

echo -e "\n${BLUE}Blue Deployment:${NC}"
oc get deployment bluegreen-demo-blue 2>/dev/null || echo "Blue deployment not found"
oc get pods -l app=bluegreen-demo,version=blue --show-labels 2>/dev/null || echo "No blue pods"

echo -e "\n${BLUE}Green Deployment:${NC}"
oc get deployment bluegreen-demo-green 2>/dev/null || echo "Green deployment not found"
oc get pods -l app=bluegreen-demo,version=green --show-labels 2>/dev/null || echo "No green pods"

echo -e "\n${BLUE}ConfigMaps:${NC}"
oc get configmap -l app=bluegreen-demo 2>/dev/null || echo "No ConfigMaps found"

echo -e "\n${BLUE}Service Endpoints:${NC}"
oc get endpoints ${SERVICE_NAME} 2>/dev/null || echo "No endpoints found"

echo -e "\n${YELLOW}To test the service:${NC}"
if [ "$ROUTE" != "not-created" ]; then
  echo "curl http://$ROUTE/version"
  echo "curl http://$ROUTE/config"
else
  echo "Route not created yet. Run: oc expose service ${SERVICE_NAME}"
fi
