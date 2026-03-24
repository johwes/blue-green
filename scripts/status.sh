#!/bin/bash

# Blue-Green Demo - Show Current Status
# This script displays the current state of the deployment

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE=${NAMESPACE:-default}
SERVICE_NAME="bluegreen-demo"

echo "======================================="
echo "Blue-Green Deployment Status"
echo "======================================="

echo -e "\n${BLUE}Service Configuration:${NC}"
kubectl get svc ${SERVICE_NAME} -n ${NAMESPACE} -o wide 2>/dev/null || echo "Service not found"

ACTIVE_VERSION=$(kubectl get svc ${SERVICE_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.selector.version}' 2>/dev/null || echo "unknown")
echo -e "\n${GREEN}Active Version: ${ACTIVE_VERSION}${NC}"

echo -e "\n${BLUE}Blue Deployment:${NC}"
kubectl get deployment bluegreen-demo-blue -n ${NAMESPACE} 2>/dev/null || echo "Blue deployment not found"
kubectl get pods -l app=bluegreen-demo,version=blue -n ${NAMESPACE} --show-labels 2>/dev/null || echo "No blue pods"

echo -e "\n${BLUE}Green Deployment:${NC}"
kubectl get deployment bluegreen-demo-green -n ${NAMESPACE} 2>/dev/null || echo "Green deployment not found"
kubectl get pods -l app=bluegreen-demo,version=green -n ${NAMESPACE} --show-labels 2>/dev/null || echo "No green pods"

echo -e "\n${BLUE}Service Endpoints:${NC}"
kubectl get endpoints ${SERVICE_NAME} -n ${NAMESPACE} 2>/dev/null || echo "No endpoints found"

echo -e "\n${BLUE}Recent Events:${NC}"
kubectl get events -n ${NAMESPACE} --sort-by='.lastTimestamp' | tail -10

echo -e "\n${YELLOW}To test the service:${NC}"
echo "kubectl port-forward svc/${SERVICE_NAME} 8080:80 -n ${NAMESPACE}"
echo "curl http://localhost:8080/version"
