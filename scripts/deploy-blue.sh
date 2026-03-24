#!/bin/bash

# Blue-Green Demo - Deploy Blue Environment for OpenShift
# This script deploys the blue version (v1.0)

set -e

echo "==================================="
echo "Deploying Blue Environment (v1.0)"
echo "==================================="

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT=$(oc project -q)
IMAGE_NAME="bluegreen-demo"
VERSION="v1.0"
REGISTRY="image-registry.openshift-image-registry.svc:5000"

echo -e "\n${BLUE}Step 1: Deploying blue ConfigMap${NC}"
oc apply -f ../openshift/configmap-blue.yaml

echo -e "\n${BLUE}Step 2: Deploying blue deployment${NC}"
oc apply -f ../openshift/deployment-blue.yaml

echo -e "\n${BLUE}Step 3: Setting image to use OpenShift registry${NC}"
oc set image deployment/bluegreen-demo-blue \
  app=${REGISTRY}/${PROJECT}/${IMAGE_NAME}:${VERSION}

echo -e "\n${BLUE}Step 4: Waiting for blue deployment to be ready${NC}"
oc rollout status deployment/bluegreen-demo-blue

echo -e "\n${GREEN}Blue environment deployed successfully!${NC}"

echo -e "\n${BLUE}Current pods:${NC}"
oc get pods -l app=bluegreen-demo,version=blue

echo -e "\n${BLUE}Configuration loaded:${NC}"
oc get configmap bluegreen-demo-config-blue

echo -e "\n${BLUE}To view the application:${NC}"
ROUTE=$(oc get route bluegreen-demo -o jsonpath='{.spec.host}' 2>/dev/null || echo "not-yet-created")
if [ "$ROUTE" != "not-yet-created" ]; then
  echo "http://$ROUTE"
  echo ""
  echo -e "${BLUE}To view configuration:${NC}"
  echo "curl http://$ROUTE/config"
else
  echo "Route not created yet. Run: oc expose service bluegreen-demo"
fi
