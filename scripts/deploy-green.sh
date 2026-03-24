#!/bin/bash

# Blue-Green Demo - Deploy Green Environment for OpenShift
# This script deploys the green version (v2.0)

set -e

echo "===================================="
echo "Deploying Green Environment (v2.0)"
echo "===================================="

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT=$(oc project -q)
IMAGE_NAME="bluegreen-demo"
VERSION="v2.0"
REGISTRY="image-registry.openshift-image-registry.svc:5000"

echo -e "\n${BLUE}Step 1: Deploying green ConfigMap${NC}"
oc apply -f ../openshift/configmap-green.yaml

echo -e "\n${BLUE}Step 2: Deploying green deployment${NC}"
oc apply -f ../openshift/deployment-green.yaml

echo -e "\n${BLUE}Step 3: Setting image to use OpenShift registry${NC}"
oc set image deployment/bluegreen-demo-green \
  app=${REGISTRY}/${PROJECT}/${IMAGE_NAME}:${VERSION}

echo -e "\n${BLUE}Step 4: Waiting for green deployment to be ready${NC}"
oc rollout status deployment/bluegreen-demo-green

echo -e "\n${GREEN}Green environment deployed successfully!${NC}"

echo -e "\n${BLUE}Current pods:${NC}"
oc get pods -l app=bluegreen-demo,version=green

echo -e "\n${BLUE}Configuration loaded:${NC}"
oc get configmap bluegreen-demo-config-green

echo -e "\n${BLUE}To test the green environment before switching:${NC}"
ROUTE=$(oc get route bluegreen-demo -o jsonpath='{.spec.host}' 2>/dev/null || echo "not-yet-created")
if [ "$ROUTE" != "not-yet-created" ]; then
  echo "Current route still points to blue: http://$ROUTE"
  echo ""
  echo -e "${BLUE}To compare configurations:${NC}"
  echo "curl http://$ROUTE/config  # Shows blue config (currently active)"
  echo ""
  echo -e "${BLUE}To switch traffic to green:${NC}"
  echo "./switch-to-green.sh"
else
  echo "Route not created yet. Blue must be deployed first."
fi
