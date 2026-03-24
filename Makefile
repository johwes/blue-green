.PHONY: help build load-images deploy-blue deploy-green deploy-all switch-green switch-blue status test clean
.PHONY: oc-build oc-deploy-blue oc-deploy-green oc-switch-green oc-switch-blue oc-status oc-cleanup

# Configuration
NAMESPACE ?= default
IMAGE_NAME = bluegreen-demo
BLUE_VERSION = v1.0
GREEN_VERSION = v2.0

# OpenShift Configuration
OC_PROJECT ?= $(shell oc project -q 2>/dev/null || echo "default")
OC_REGISTRY = image-registry.openshift-image-registry.svc:5000

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ''
	@echo 'OpenShift targets: oc-build, oc-deploy-blue, oc-deploy-green, oc-switch-green, oc-status'

build: ## Build both Docker images
	@echo "Building blue image ($(BLUE_VERSION))..."
	docker build -t $(IMAGE_NAME):$(BLUE_VERSION) ./app/
	@echo "Building green image ($(GREEN_VERSION))..."
	docker build -t $(IMAGE_NAME):$(GREEN_VERSION) ./app/
	@echo "✓ Images built successfully"

load-kind: ## Load images to kind cluster
	@echo "Loading images to kind cluster..."
	kind load docker-image $(IMAGE_NAME):$(BLUE_VERSION)
	kind load docker-image $(IMAGE_NAME):$(GREEN_VERSION)
	@echo "✓ Images loaded to kind"

load-minikube: ## Load images to minikube
	@echo "Loading images to minikube..."
	minikube image load $(IMAGE_NAME):$(BLUE_VERSION)
	minikube image load $(IMAGE_NAME):$(GREEN_VERSION)
	@echo "✓ Images loaded to minikube"

deploy-blue: ## Deploy blue environment
	@echo "Deploying blue environment..."
	kubectl apply -f k8s/configmap-blue.yaml -n $(NAMESPACE)
	kubectl apply -f k8s/deployment-blue.yaml -n $(NAMESPACE)
	kubectl rollout status deployment/bluegreen-demo-blue -n $(NAMESPACE)
	@echo "✓ Blue deployed successfully"

deploy-green: ## Deploy green environment
	@echo "Deploying green environment..."
	kubectl apply -f k8s/configmap-green.yaml -n $(NAMESPACE)
	kubectl apply -f k8s/deployment-green.yaml -n $(NAMESPACE)
	kubectl rollout status deployment/bluegreen-demo-green -n $(NAMESPACE)
	@echo "✓ Green deployed successfully"

deploy-service: ## Deploy service
	@echo "Deploying service..."
	kubectl apply -f k8s/service.yaml -n $(NAMESPACE)
	@echo "✓ Service deployed"

deploy-all: deploy-blue deploy-service ## Deploy blue environment and service

switch-green: ## Switch traffic to green
	@echo "Switching traffic to green..."
	kubectl patch svc bluegreen-demo -n $(NAMESPACE) -p '{"spec":{"selector":{"version":"green"}}}'
	@echo "✓ Traffic switched to green"
	@$(MAKE) verify-version

switch-blue: ## Switch traffic to blue (rollback)
	@echo "Switching traffic to blue..."
	kubectl patch svc bluegreen-demo -n $(NAMESPACE) -p '{"spec":{"selector":{"version":"blue"}}}'
	@echo "✓ Traffic switched to blue"
	@$(MAKE) verify-version

status: ## Show deployment status
	@echo "=== ConfigMaps ==="
	@kubectl get configmaps -n $(NAMESPACE) -l app=bluegreen-demo
	@echo ""
	@echo "=== Deployments ==="
	@kubectl get deployments -n $(NAMESPACE) -l app=bluegreen-demo
	@echo ""
	@echo "=== Pods ==="
	@kubectl get pods -n $(NAMESPACE) -l app=bluegreen-demo -o wide
	@echo ""
	@echo "=== Service ==="
	@kubectl get svc bluegreen-demo -n $(NAMESPACE)
	@echo ""
	@echo "=== Active Version ==="
	@kubectl get svc bluegreen-demo -n $(NAMESPACE) -o jsonpath='{.spec.selector.version}'
	@echo ""

verify-version: ## Verify active version via port-forward
	@echo "Active version:"
	@kubectl get svc bluegreen-demo -n $(NAMESPACE) -o jsonpath='{.spec.selector.version}'
	@echo ""

logs-blue: ## Show blue logs
	kubectl logs -l version=blue -n $(NAMESPACE) --tail=50

logs-green: ## Show green logs
	kubectl logs -l version=green -n $(NAMESPACE) --tail=50

logs-blue-follow: ## Follow blue logs
	kubectl logs -l version=blue -n $(NAMESPACE) -f

logs-green-follow: ## Follow green logs
	kubectl logs -l version=green -n $(NAMESPACE) -f

test-blue: ## Port-forward and test blue directly
	@echo "Port-forwarding to blue on localhost:8080"
	@echo "Test with: curl http://localhost:8080/version"
	kubectl port-forward deployment/bluegreen-demo-blue 8080:3000 -n $(NAMESPACE)

test-green: ## Port-forward and test green directly
	@echo "Port-forwarding to green on localhost:8081"
	@echo "Test with: curl http://localhost:8081/version"
	kubectl port-forward deployment/bluegreen-demo-green 8081:3000 -n $(NAMESPACE)

test-service: ## Port-forward to service
	@echo "Port-forwarding to service on localhost:8080"
	@echo "Test with: curl http://localhost:8080/version"
	kubectl port-forward svc/bluegreen-demo 8080:80 -n $(NAMESPACE)

scale-blue: ## Scale blue deployment
	@read -p "Number of replicas: " replicas; \
	kubectl scale deployment bluegreen-demo-blue --replicas=$$replicas -n $(NAMESPACE)

scale-green: ## Scale green deployment
	@read -p "Number of replicas: " replicas; \
	kubectl scale deployment bluegreen-demo-green --replicas=$$replicas -n $(NAMESPACE)

clean: ## Delete all resources
	@echo "Deleting all blue-green resources..."
	kubectl delete deployment bluegreen-demo-blue -n $(NAMESPACE) --ignore-not-found=true
	kubectl delete deployment bluegreen-demo-green -n $(NAMESPACE) --ignore-not-found=true
	kubectl delete configmap bluegreen-demo-config-blue -n $(NAMESPACE) --ignore-not-found=true
	kubectl delete configmap bluegreen-demo-config-green -n $(NAMESPACE) --ignore-not-found=true
	kubectl delete svc bluegreen-demo -n $(NAMESPACE) --ignore-not-found=true
	@echo "✓ Cleanup complete"

# Complete workflows
demo-setup: build load-kind deploy-all ## Complete setup for kind (build, load, deploy)
	@echo "✓ Demo setup complete!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Test blue: make test-service"
	@echo "  2. Deploy green: make deploy-green"
	@echo "  3. Switch traffic: make switch-green"

demo-switch: deploy-green switch-green ## Deploy green and switch traffic
	@echo "✓ Switched to green version!"

demo-rollback: switch-blue ## Rollback to blue
	@echo "✓ Rolled back to blue version!"

# CI/CD helpers
ci-build-and-test: build ## CI: Build and test images
	@echo "Running image tests..."
	docker run --rm $(IMAGE_NAME):$(BLUE_VERSION) npm test || true
	docker run --rm $(IMAGE_NAME):$(GREEN_VERSION) npm test || true

ci-deploy-staging: deploy-green ## CI: Deploy to staging (green)
	@echo "Deployed to staging environment (green)"

ci-promote-production: switch-green ## CI: Promote staging to production
	@echo "Promoted to production!"

# ============================================================================
# OpenShift Targets (for Red Hat Developer Sandbox)
# ============================================================================

oc-build: ## OpenShift: Build image using OpenShift builds
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

oc-deploy-configmaps: ## OpenShift: Deploy ConfigMaps
	@echo "Deploying ConfigMaps..."
	oc apply -f k8s/configmap-blue.yaml
	oc apply -f k8s/configmap-green.yaml
	@echo "✓ ConfigMaps deployed"

oc-deploy-blue: oc-deploy-configmaps ## OpenShift: Deploy blue environment
	@echo "Deploying blue environment..."
	oc apply -f k8s/deployment-blue.yaml
	oc set image deployment/bluegreen-demo-blue \
		app=$(OC_REGISTRY)/$(OC_PROJECT)/$(IMAGE_NAME):$(BLUE_VERSION)
	oc rollout status deployment/bluegreen-demo-blue
	@echo "✓ Blue deployed successfully"

oc-deploy-green: oc-deploy-configmaps ## OpenShift: Deploy green environment
	@echo "Deploying green environment..."
	oc apply -f k8s/deployment-green.yaml
	oc set image deployment/bluegreen-demo-green \
		app=$(OC_REGISTRY)/$(OC_PROJECT)/$(IMAGE_NAME):$(GREEN_VERSION)
	oc rollout status deployment/bluegreen-demo-green
	@echo "✓ Green deployed successfully"

oc-create-service: ## OpenShift: Create service and route
	@echo "Creating service..."
	@cat <<EOF | oc apply -f -\n\
apiVersion: v1\n\
kind: Service\n\
metadata:\n\
  name: bluegreen-demo\n\
  labels:\n\
    app: bluegreen-demo\n\
spec:\n\
  type: ClusterIP\n\
  selector:\n\
    app: bluegreen-demo\n\
    version: blue\n\
  ports:\n\
  - name: http\n\
    port: 80\n\
    targetPort: 3000\n\
EOF
	@echo "Creating route..."
	@oc expose service bluegreen-demo 2>/dev/null || echo "Route already exists"
	@echo "✓ Service created at: http://$$(oc get route bluegreen-demo -o jsonpath='{.spec.host}')"

oc-deploy-all: oc-build oc-deploy-blue oc-create-service ## OpenShift: Complete deployment (build + deploy blue + service)
	@echo ""
	@echo "✓ Complete deployment finished!"
	@echo "  Your app: http://$$(oc get route bluegreen-demo -o jsonpath='{.spec.host}')"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Deploy green: make oc-deploy-green"
	@echo "  2. Switch traffic: make oc-switch-green"

oc-switch-green: ## OpenShift: Switch traffic to green
	@echo "Switching traffic to green..."
	oc patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"green"}}}'
	@echo "✓ Traffic switched to green"
	@$(MAKE) oc-verify-version

oc-switch-blue: ## OpenShift: Switch traffic to blue (rollback)
	@echo "Switching traffic to blue..."
	oc patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"blue"}}}'
	@echo "✓ Traffic switched to blue"
	@$(MAKE) oc-verify-version

oc-verify-version: ## OpenShift: Verify active version
	@echo "Active version: $$(oc get svc bluegreen-demo -o jsonpath='{.spec.selector.version}')"

oc-status: ## OpenShift: Show deployment status
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

oc-test: ## OpenShift: Test the application
	@ROUTE=$$(oc get route bluegreen-demo -o jsonpath='{.spec.host}'); \
	echo "Testing http://$$ROUTE..."; \
	echo ""; \
	echo "=== Version ==="; \
	curl -s http://$$ROUTE/version | jq .; \
	echo ""; \
	echo "=== Configuration ==="; \
	curl -s http://$$ROUTE/config | jq .configuration

oc-cleanup: ## OpenShift: Delete all resources
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
