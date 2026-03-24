#!/bin/bash

# Blue-Green Demo - Switch Traffic to Blue
# This script updates the service selector to route traffic to blue

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
NAMESPACE=${NAMESPACE:-default}
SERVICE_NAME="bluegreen-demo"

echo -e "\n${YELLOW}Current service configuration:${NC}"
kubectl get svc ${SERVICE_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.selector}' | jq .

echo -e "\n${BLUE}Patching service to route to blue...${NC}"
kubectl patch svc ${SERVICE_NAME} -n ${NAMESPACE} -p '{"spec":{"selector":{"version":"blue"}}}'

echo -e "\n${GREEN}Traffic switched to blue!${NC}"

echo -e "\n${BLUE}New service configuration:${NC}"
kubectl get svc ${SERVICE_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.selector}' | jq .

echo -e "\n${BLUE}Service endpoints (should show blue pods):${NC}"
kubectl get endpoints ${SERVICE_NAME} -n ${NAMESPACE}

echo -e "\n${BLUE}Verifying version (wait a few seconds for DNS to propagate):${NC}"
sleep 3

# Try to curl the service if it's accessible
SERVICE_IP=$(kubectl get svc ${SERVICE_NAME} -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [ -z "$SERVICE_IP" ]; then
  SERVICE_IP=$(kubectl get svc ${SERVICE_NAME} -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
fi

if [ -n "$SERVICE_IP" ]; then
  echo -e "\n${BLUE}Testing endpoint:${NC}"
  curl -s http://${SERVICE_IP}/version | jq .
else
  echo -e "\n${YELLOW}To test locally:${NC}"
  echo "kubectl port-forward svc/${SERVICE_NAME} 8080:80 -n ${NAMESPACE}"
  echo "curl http://localhost:8080/version"
fi

echo -e "\n${GREEN}Done!${NC}"
