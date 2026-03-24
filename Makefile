.PHONY: help build deploy-blue deploy-green deploy-all switch-green switch-blue status test cleanup

# Configuration
IMAGE_NAME = bluegreen-demo
BLUE_VERSION = v1.0
GREEN_VERSION = v2.0

# OpenShift Configuration
OC_PROJECT ?= $(shell oc project -q 2>/dev/null || echo "default")
OC_REGISTRY = image-registry.openshift-image-registry.svc:5000

help: ## Show this help message
	@echo 'Blue-Green Deployment for Red Hat OpenShift'
	@echo ''
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build: ## Build image using OpenShift builds
	@echo "Building image in OpenShift..."
	@if ! oc get bc $(IMAGE_NAME) >/dev/null 2>&1; then \
		echo "Creating BuildConfig..."; \
		oc new-build --name=$(IMAGE_NAME) --binary --strategy=docker; \
	fi
	@echo "Starting build from app directory..."
	oc start-build $(IMAGE_NAME) --from-dir=./app --follow
	@echo "Tagging images..."
	oc tag $(IMAGE_NAME):latest $(IMAGE_NAME):$(BLUE_VERSION)
	oc tag $(IMAGE_NAME):latest $(IMAGE_NAME):$(GREEN_VERSION)
	@echo "✓ Images built and tagged successfully"

deploy-configmaps: ## Deploy ConfigMaps
	@echo "Deploying ConfigMaps..."
	oc apply -f openshift/configmap-blue.yaml
	oc apply -f openshift/configmap-green.yaml
	@echo "✓ ConfigMaps deployed"

deploy-blue: deploy-configmaps ## Deploy blue environment
	@echo "Deploying blue environment..."
	oc apply -f openshift/deployment-blue.yaml
	oc set image deployment/bluegreen-demo-blue \
		app=$(OC_REGISTRY)/$(OC_PROJECT)/$(IMAGE_NAME):$(BLUE_VERSION)
	oc rollout status deployment/bluegreen-demo-blue
	@echo "✓ Blue deployed successfully"

deploy-green: deploy-configmaps ## Deploy green environment
	@echo "Deploying green environment..."
	oc apply -f openshift/deployment-green.yaml
	oc set image deployment/bluegreen-demo-green \
		app=$(OC_REGISTRY)/$(OC_PROJECT)/$(IMAGE_NAME):$(GREEN_VERSION)
	oc rollout status deployment/bluegreen-demo-green
	@echo "✓ Green deployed successfully"

create-service: ## Create service and route
	@echo "Creating service..."
	@oc create service clusterip bluegreen-demo --tcp=80:3000 2>/dev/null || echo "Service already exists"
	@oc patch svc bluegreen-demo -p '{"spec":{"selector":{"app":"bluegreen-demo","version":"blue"}}}'
	@echo "Creating route..."
	@oc expose service bluegreen-demo 2>/dev/null || echo "Route already exists"
	@echo "✓ Service created at: http://$$(oc get route bluegreen-demo -o jsonpath='{.spec.host}')"

deploy-all: build deploy-blue create-service ## Complete deployment (build + deploy blue + service)
	@echo ""
	@echo "✓ Complete deployment finished!"
	@echo "  Your app: http://$$(oc get route bluegreen-demo -o jsonpath='{.spec.host}')"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Deploy green: make deploy-green"
	@echo "  2. Switch traffic: make switch-green"
	@echo "  3. Check status: make status"

switch-green: ## Switch traffic to green
	@echo "Switching traffic to green..."
	oc patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"green"}}}'
	@echo "✓ Traffic switched to green"
	@$(MAKE) verify-version

switch-blue: ## Switch traffic to blue (rollback)
	@echo "Switching traffic to blue..."
	oc patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"blue"}}}'
	@echo "✓ Traffic switched to blue"
	@$(MAKE) verify-version

verify-version: ## Verify active version
	@echo "Active version: $$(oc get svc bluegreen-demo -o jsonpath='{.spec.selector.version}')"

status: ## Show deployment status
	@echo "=== ConfigMaps ==="
	@oc get configmaps -l app=bluegreen-demo
	@echo ""
	@echo "=== Deployments ==="
	@oc get deployments -l app=bluegreen-demo
	@echo ""
	@echo "=== Pods ==="
	@oc get pods -l app=bluegreen-demo -o wide
	@echo ""
	@echo "=== Service ==="
	@oc get svc bluegreen-demo
	@echo ""
	@echo "=== Route ==="
	@oc get route bluegreen-demo
	@echo ""
	@echo "=== Active Version ==="
	@echo "Active: $$(oc get svc bluegreen-demo -o jsonpath='{.spec.selector.version}')"
	@echo ""
	@echo "=== Application URL ==="
	@echo "http://$$(oc get route bluegreen-demo -o jsonpath='{.spec.host}')"

test: ## Test the application
	@ROUTE=$$(oc get route bluegreen-demo -o jsonpath='{.spec.host}'); \
	echo "Testing http://$$ROUTE..."; \
	echo ""; \
	echo "=== Version ==="; \
	curl -s http://$$ROUTE/version | jq .; \
	echo ""; \
	echo "=== Configuration ==="; \
	curl -s http://$$ROUTE/config | jq .configuration

logs-blue: ## Show blue logs
	@oc logs -l version=blue --tail=50

logs-green: ## Show green logs
	@oc logs -l version=green --tail=50

logs-blue-follow: ## Follow blue logs
	@oc logs -l version=blue -f

logs-green-follow: ## Follow green logs
	@oc logs -l version=green -f

cleanup: ## Delete all resources
	@echo "Deleting all blue-green resources..."
	oc delete deployment bluegreen-demo-blue --ignore-not-found=true
	oc delete deployment bluegreen-demo-green --ignore-not-found=true
	oc delete configmap bluegreen-demo-config-blue --ignore-not-found=true
	oc delete configmap bluegreen-demo-config-green --ignore-not-found=true
	oc delete svc bluegreen-demo --ignore-not-found=true
	oc delete route bluegreen-demo --ignore-not-found=true
	oc delete buildconfig bluegreen-demo --ignore-not-found=true
	oc delete imagestream bluegreen-demo --ignore-not-found=true
	@echo "✓ Cleanup complete"
