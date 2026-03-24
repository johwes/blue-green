# Blue-Green Deployment Tutorial

A comprehensive step-by-step guide to understanding and implementing blue-green deployments on Kubernetes.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Understanding Blue-Green Deployment](#understanding-blue-green-deployment)
3. [Setting Up Your Environment](#setting-up-your-environment)
4. [Part 1: Building the Application](#part-1-building-the-application)
5. [Part 2: Deploying the Blue Environment](#part-2-deploying-the-blue-environment)
6. [Part 3: Deploying the Green Environment](#part-3-deploying-the-green-environment)
7. [Part 4: Switching Traffic](#part-4-switching-traffic)
8. [Part 5: Rollback Scenario](#part-5-rollback-scenario)
9. [Advanced Topics](#advanced-topics)
10. [Troubleshooting](#troubleshooting)
11. [Best Practices](#best-practices)

---

## Prerequisites

Before starting this tutorial, ensure you have:

- **Kubernetes cluster** (minikube, kind, or cloud provider)
- **kubectl** CLI tool installed and configured
- **Docker** installed for building images
- **Basic knowledge** of Kubernetes concepts (pods, deployments, services)
- **jq** (optional, for JSON parsing in scripts)

### Verify Your Setup

```bash
# Check kubectl is working
kubectl version --client

# Check cluster access
kubectl cluster-info

# Check Docker
docker --version
```

---

## Understanding Blue-Green Deployment

### What is Blue-Green Deployment?

Blue-green deployment is a release strategy where two identical production environments run simultaneously:

- **Blue**: Current production version
- **Green**: New version being deployed

Only one environment receives production traffic at a time. Traffic is switched instantly by updating the routing configuration.

### Key Concepts

**Deployments**: Separate Kubernetes Deployments for blue and green versions
- `bluegreen-demo-blue` runs v1.0
- `bluegreen-demo-green` runs v2.0

**Service**: Single Kubernetes Service that routes traffic
- Uses label selectors to choose blue OR green
- Traffic switch = update service selector

**Zero Downtime**: Both versions run simultaneously
- New version fully deployed before receiving traffic
- Instant cutover by changing service selector

### Benefits vs. Traditional Deployment

| Aspect | Traditional Rolling Update | Blue-Green |
|--------|----------------------------|------------|
| Downtime | Minimal (pods restart) | Zero |
| Rollback Speed | Slow (redeploy previous) | Instant (flip selector) |
| Testing | Production testing limited | Full production test before switch |
| Resource Usage | Efficient (gradual) | High (2x during switch) |
| Complexity | Low | Medium |

### When to Use Blue-Green

**Good fit:**
- Mission-critical applications requiring zero downtime
- Need to test in production before go-live
- Instant rollback is essential
- Database migrations can be backward compatible

**Not ideal when:**
- Resource-constrained (need to run 2x pods)
- Frequent deployments (high resource churn)
- Complex database schema changes
- Stateful applications with data synchronization issues

---

## Setting Up Your Environment

### Option 1: Using Minikube

```bash
# Start minikube
minikube start --cpus=4 --memory=8192

# Enable LoadBalancer support
minikube tunnel  # Run in separate terminal
```

### Option 2: Using kind (Kubernetes in Docker)

```bash
# Create cluster
kind create cluster --name bluegreen-demo

# Install MetalLB for LoadBalancer support
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml

# Configure IP range (adjust for your Docker network)
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.18.255.200-172.18.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advert
  namespace: metallb-system
EOF
```

### Option 3: Using a Cloud Provider

If using GKE, EKS, or AKS, your cluster already has LoadBalancer support. Just ensure you have cluster access configured.

### Create Namespace (Optional)

```bash
kubectl create namespace bluegreen-demo
kubectl config set-context --current --namespace=bluegreen-demo
```

Or use the provided manifest:

```bash
kubectl apply -f k8s/namespace.yaml
```

---

## Part 1: Building the Application

### Understanding the Demo Application

The sample application is a simple Node.js Express server that exposes version information.

**Key Endpoints:**
- `GET /` - Returns application info including version and color
- `GET /version` - Returns just version and color
- `GET /health` - Health check for liveness probe
- `GET /ready` - Readiness check for readiness probe

**Environment Variables:**
- `VERSION` - Application version (v1.0 or v2.0)
- `COLOR` - Environment color (blue or green)
- `PORT` - Server port (default: 3000)

### Build Docker Images

Navigate to the project root and build both versions:

```bash
# Build Blue version (v1.0)
docker build -t bluegreen-demo:v1.0 ./app/

# Build Green version (v2.0)
docker build -t bluegreen-demo:v2.0 ./app/
```

### Load Images to Your Cluster

**For minikube:**
```bash
minikube image load bluegreen-demo:v1.0
minikube image load bluegreen-demo:v2.0
```

**For kind:**
```bash
kind load docker-image bluegreen-demo:v1.0 --name bluegreen-demo
kind load docker-image bluegreen-demo:v2.0 --name bluegreen-demo
```

**For cloud providers:**
```bash
# Push to container registry (example for Docker Hub)
docker tag bluegreen-demo:v1.0 your-username/bluegreen-demo:v1.0
docker tag bluegreen-demo:v2.0 your-username/bluegreen-demo:v2.0
docker push your-username/bluegreen-demo:v1.0
docker push your-username/bluegreen-demo:v2.0

# Update k8s/*.yaml files to use your registry images
```

### Verify Images

```bash
# For minikube
minikube ssh docker images | grep bluegreen-demo

# For kind
docker exec -it bluegreen-demo-control-plane crictl images | grep bluegreen-demo
```

---

## Part 2: Deploying the Blue Environment

### Step 1: Examine the Blue Deployment Manifest

Open `k8s/deployment-blue.yaml` and review:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bluegreen-demo-blue
  labels:
    app: bluegreen-demo
    version: blue
spec:
  replicas: 3
  selector:
    matchLabels:
      app: bluegreen-demo
      version: blue  # Specific to blue
  template:
    metadata:
      labels:
        app: bluegreen-demo
        version: blue  # Pod label
    spec:
      containers:
      - name: app
        image: bluegreen-demo:v1.0  # Blue uses v1.0
        env:
        - name: VERSION
          value: "v1.0"
        - name: COLOR
          value: "blue"
```

**Key points:**
- Label `version: blue` distinguishes this deployment
- Environment variables set version and color
- 3 replicas for high availability
- Health and readiness probes ensure pod health

### Step 2: Deploy Blue

```bash
kubectl apply -f k8s/deployment-blue.yaml
```

Or use the helper script:

```bash
cd scripts
chmod +x *.sh
./deploy-blue.sh
```

### Step 3: Verify Blue Deployment

```bash
# Check deployment status
kubectl get deployments

# Check pods are running
kubectl get pods -l version=blue

# Wait for rollout to complete
kubectl rollout status deployment/bluegreen-demo-blue

# Describe a pod to see details
kubectl describe pod -l version=blue | head -30
```

Expected output:
```
NAME                                    READY   STATUS    RESTARTS   AGE
bluegreen-demo-blue-xxxxx-xxxxx        1/1     Running   0          30s
bluegreen-demo-blue-xxxxx-xxxxx        1/1     Running   0          30s
bluegreen-demo-blue-xxxxx-xxxxx        1/1     Running   0          30s
```

### Step 4: Test Blue Directly

Before creating the service, test the blue pods directly:

```bash
# Port forward to one blue pod
kubectl port-forward deployment/bluegreen-demo-blue 8080:3000

# In another terminal, test the endpoint
curl http://localhost:8080/
curl http://localhost:8080/version
```

Expected response:
```json
{
  "application": "Blue-Green Demo",
  "version": "v1.0",
  "color": "blue",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "hostname": "bluegreen-demo-blue-xxxxx-xxxxx"
}
```

### Step 5: Create the Service

Examine `k8s/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: bluegreen-demo
spec:
  type: LoadBalancer
  selector:
    app: bluegreen-demo
    version: blue  # Routes to blue initially
  ports:
  - port: 80
    targetPort: 3000
```

Deploy the service:

```bash
kubectl apply -f k8s/service.yaml
```

### Step 6: Access the Service

```bash
# Get service details
kubectl get svc bluegreen-demo

# Get external IP (may take a minute)
kubectl get svc bluegreen-demo -w
```

**For cloud providers:** Use the EXTERNAL-IP

```bash
EXTERNAL_IP=$(kubectl get svc bluegreen-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$EXTERNAL_IP/version
```

**For minikube:**

```bash
minikube service bluegreen-demo --url
# Use the URL provided
```

**For kind or local testing:**

```bash
kubectl port-forward svc/bluegreen-demo 8080:80
curl http://localhost:8080/version
```

You should see the blue version (v1.0) response.

---

## Part 3: Deploying the Green Environment

### Step 1: Examine the Green Deployment

Open `k8s/deployment-green.yaml` and note the differences from blue:

```yaml
metadata:
  name: bluegreen-demo-green
  labels:
    version: green  # Changed from blue

spec:
  selector:
    matchLabels:
      version: green  # Changed from blue

  template:
    metadata:
      labels:
        version: green  # Changed from blue
    spec:
      containers:
      - name: app
        image: bluegreen-demo:v2.0  # Different image version
        env:
        - name: VERSION
          value: "v2.0"  # Different version
        - name: COLOR
          value: "green"  # Different color
```

### Step 2: Deploy Green

While blue is still running and serving traffic, deploy green:

```bash
kubectl apply -f k8s/deployment-green.yaml
```

Or use the script:

```bash
./deploy-green.sh
```

### Step 3: Verify Green Deployment

```bash
# Check both deployments
kubectl get deployments

# Check green pods
kubectl get pods -l version=green

# Wait for green rollout
kubectl rollout status deployment/bluegreen-demo-green
```

You should now see both blue and green running:

```bash
kubectl get pods -l app=bluegreen-demo
```

Expected output:
```
NAME                                    READY   STATUS    RESTARTS   AGE
bluegreen-demo-blue-xxxxx-xxxxx        1/1     Running   0          5m
bluegreen-demo-blue-xxxxx-xxxxx        1/1     Running   0          5m
bluegreen-demo-blue-xxxxx-xxxxx        1/1     Running   0          5m
bluegreen-demo-green-xxxxx-xxxxx       1/1     Running   0          30s
bluegreen-demo-green-xxxxx-xxxxx       1/1     Running   0          30s
bluegreen-demo-green-xxxxx-xxxxx       1/1     Running   0          30s
```

### Step 4: Test Green Directly

The service still routes to blue. Test green directly:

```bash
# Port forward to green
kubectl port-forward deployment/bluegreen-demo-green 8081:3000

# In another terminal
curl http://localhost:8081/version
```

Expected response:
```json
{
  "version": "v2.0",
  "color": "green"
}
```

### Step 5: Verify Service Still Routes to Blue

```bash
# The service should still show blue
curl http://localhost:8080/version  # If using port-forward to service

# Check service selector
kubectl get svc bluegreen-demo -o jsonpath='{.spec.selector}' | jq .
```

Output should show:
```json
{
  "app": "bluegreen-demo",
  "version": "blue"
}
```

---

## Part 4: Switching Traffic

This is the critical moment - the actual blue-green switch!

### Understanding the Switch

The traffic switch is accomplished by updating the service's selector from `version: blue` to `version: green`. This is a metadata change that happens instantly.

### Step 1: Prepare for the Switch

Before switching, ensure:

1. Green deployment is healthy:
```bash
kubectl get deployment bluegreen-demo-green
# Should show 3/3 READY
```

2. All green pods are ready:
```bash
kubectl get pods -l version=green
# All should be Running with 1/1 READY
```

3. Green passes readiness checks:
```bash
kubectl describe pods -l version=green | grep -A 5 "Readiness"
```

### Step 2: Perform the Switch

Use the helper script:

```bash
./switch-to-green.sh
```

Or manually with kubectl:

```bash
# Update the service selector
kubectl patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"green"}}}'
```

### Step 3: Verify the Switch

```bash
# Check service selector changed
kubectl get svc bluegreen-demo -o jsonpath='{.spec.selector}' | jq .
```

Should now show:
```json
{
  "app": "bluegreen-demo",
  "version": "green"
}
```

Check endpoints point to green pods:

```bash
kubectl get endpoints bluegreen-demo
```

The IP addresses should match green pod IPs:

```bash
# Get green pod IPs
kubectl get pods -l version=green -o wide

# Compare with endpoints
kubectl get endpoints bluegreen-demo -o yaml
```

### Step 4: Test the Service

```bash
# Test the service (it should now return green/v2.0)
curl http://localhost:8080/version

# Or if using external IP
curl http://$EXTERNAL_IP/version
```

Expected response:
```json
{
  "version": "v2.0",
  "color": "green"
}
```

### Step 5: Monitor the Traffic

Run multiple requests to ensure consistency:

```bash
# Run 10 requests and check all return green
for i in {1..10}; do
  curl -s http://localhost:8080/version | jq -r .color
done
```

All responses should say "green".

### Step 6: Check Application Logs

```bash
# Blue should stop receiving traffic (no new logs)
kubectl logs -l version=blue --tail=20

# Green should receive traffic (new logs)
kubectl logs -l version=green --tail=20 -f
```

---

## Part 5: Rollback Scenario

One of the key benefits of blue-green deployment is instant rollback capability.

### Scenario: Issue Detected in Green

Imagine you've discovered a critical bug in the green (v2.0) version after switching traffic.

### Step 1: Immediate Rollback

Simply switch back to blue:

```bash
./switch-to-blue.sh
```

Or manually:

```bash
kubectl patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"blue"}}}'
```

### Step 2: Verify Rollback

```bash
# Check service selector
kubectl get svc bluegreen-demo -o jsonpath='{.spec.selector}' | jq .

# Test endpoint
curl http://localhost:8080/version
```

Should return:
```json
{
  "version": "v1.0",
  "color": "blue"
}
```

**Rollback time:** Typically 1-2 seconds!

### Step 3: Investigate the Issue

Green is still running, so you can investigate:

```bash
# Check green logs
kubectl logs -l version=green --tail=100

# Connect to a green pod for debugging
kubectl exec -it deployment/bluegreen-demo-green -- /bin/sh

# Inside the pod
wget -O- localhost:3000/version
exit
```

### Step 4: Fix and Redeploy

After fixing the issue:

1. Build new image:
```bash
docker build -t bluegreen-demo:v2.1 ./app/
```

2. Update green deployment to use v2.1

3. Test thoroughly in green environment

4. Switch traffic again when ready

### Step 5: Clean Up Old Environment

Once green is stable, you can scale down or delete blue:

```bash
# Scale down blue (keep deployment for future use)
kubectl scale deployment bluegreen-demo-blue --replicas=0

# Or delete blue entirely
kubectl delete deployment bluegreen-demo-blue
```

---

## Advanced Topics

### Database Migrations

Blue-green deployments with database changes require careful planning:

**Approach 1: Backward-compatible migrations**

1. Deploy green with migration that's compatible with blue
2. Switch traffic to green
3. Remove backward-compatibility code in next release

**Approach 2: Expand-contract pattern**

1. **Expand**: Add new columns/tables (blue and green both work)
2. **Migrate**: Dual-write to old and new schema
3. **Contract**: Remove old columns/tables after switch complete

Example:
```sql
-- Step 1: Expand (before green deployment)
ALTER TABLE users ADD COLUMN email_verified BOOLEAN DEFAULT false;

-- Blue continues using old logic
-- Green uses new column

-- Step 2: After switch, migrate data
UPDATE users SET email_verified = (verified_at IS NOT NULL);

-- Step 3: Contract (next release)
ALTER TABLE users DROP COLUMN verified_at;
```

### Using ConfigMaps and Secrets

Separate configuration from deployment:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-blue
data:
  FEATURE_FLAG: "false"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-green
data:
  FEATURE_FLAG: "true"  # New feature enabled in green
```

Reference in deployment:

```yaml
spec:
  containers:
  - name: app
    envFrom:
    - configMapRef:
        name: app-config-green  # or app-config-blue
```

### Health Checks Deep Dive

**Liveness Probe**: Detects if app is alive (restart if fails)

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 3000
  initialDelaySeconds: 10  # Wait 10s after start
  periodSeconds: 10        # Check every 10s
  timeoutSeconds: 3        # 3s timeout
  failureThreshold: 3      # Restart after 3 failures
```

**Readiness Probe**: Detects if app can serve traffic (remove from service if fails)

```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 3000
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 2     # Remove after 2 failures
```

**Why both?**
- Liveness: "Is the app running?"
- Readiness: "Is the app ready to serve traffic?"

During startup, readiness may fail while liveness passes (app is running but not ready).

### Monitoring the Switch

Use kubectl events and metrics:

```bash
# Watch events during switch
kubectl get events --watch

# Monitor endpoints in real-time
watch kubectl get endpoints bluegreen-demo

# Use stern for log streaming (if installed)
stern bluegreen-demo
```

### Automation with Scripts

The provided scripts can be enhanced:

**Add smoke tests:**
```bash
# In switch-to-green.sh
echo "Running smoke tests..."
RESPONSE=$(curl -s http://$SERVICE_IP/health)
if [[ $(echo $RESPONSE | jq -r .status) != "healthy" ]]; then
  echo "Smoke test failed! Rolling back..."
  ./switch-to-blue.sh
  exit 1
fi
```

**Add metric collection:**
```bash
# Before switch
INITIAL_REQUEST_COUNT=$(curl -s http://$METRICS_ENDPOINT | grep request_count)

# After switch
sleep 30
NEW_REQUEST_COUNT=$(curl -s http://$METRICS_ENDPOINT | grep request_count)
```

---

## Troubleshooting

### Service Not Switching

**Symptoms:** Service still routes to old version after patch

**Diagnosis:**
```bash
# Check if patch was applied
kubectl get svc bluegreen-demo -o yaml | grep -A 5 selector

# Check endpoints
kubectl describe endpoints bluegreen-demo
```

**Solutions:**
- Ensure labels match exactly (case-sensitive)
- Verify pods with new version have matching labels
- Check if pods are ready (readiness probe must pass)

### Pods Not Ready

**Symptoms:** Pods stuck in ContainerCreating or not ready

**Diagnosis:**
```bash
# Check pod status
kubectl get pods -l app=bluegreen-demo

# Describe problematic pod
kubectl describe pod <pod-name>

# Check logs
kubectl logs <pod-name>
```

**Common causes:**
- Image pull failures (check imagePullPolicy)
- Health check failures (check probe configuration)
- Resource constraints (check node resources)

**Solutions:**
```bash
# For image pull issues
kubectl describe pod <pod-name> | grep -A 5 "Events"

# For resource issues
kubectl top nodes
kubectl describe node <node-name>
```

### Service Not Accessible

**Symptoms:** Cannot reach service externally

**Diagnosis:**
```bash
# Check service type and external IP
kubectl get svc bluegreen-demo

# Check service endpoints exist
kubectl get endpoints bluegreen-demo

# Test from within cluster
kubectl run test-pod --rm -it --image=curlimages/curl -- sh
# Inside pod: curl http://bluegreen-demo/version
```

**Solutions:**

For minikube:
```bash
minikube service bluegreen-demo --url
```

For kind (needs MetalLB or port-forward):
```bash
kubectl port-forward svc/bluegreen-demo 8080:80
```

For cloud providers:
- Wait a few minutes for LoadBalancer provisioning
- Check cloud provider console for LB status
- Verify security groups/firewall rules

### Both Blue and Green Receiving Traffic

**Symptoms:** Random mix of v1.0 and v2.0 responses

**Diagnosis:**
```bash
# Check service selector
kubectl get svc bluegreen-demo -o jsonpath='{.spec.selector}'

# This should show ONLY one version
```

**Cause:** Service selector matches both blue and green (missing version label)

**Solution:**
```bash
# Ensure service has version selector
kubectl patch svc bluegreen-demo -p '{"spec":{"selector":{"app":"bluegreen-demo","version":"blue"}}}'
```

### DNS Caching Issues

**Symptoms:** Still seeing old version after switch

**Cause:** DNS caching at client or intermediate proxy

**Solutions:**
- Wait 30-60 seconds for DNS TTL to expire
- Test directly with IP address instead of hostname
- Use kubectl port-forward to bypass DNS
- Check if using session affinity (disable if not needed)

---

## Best Practices

### 1. Always Test Green Before Switching

```bash
# Deploy green
kubectl apply -f k8s/deployment-green.yaml

# Wait for ready
kubectl rollout status deployment/bluegreen-demo-green

# Test green directly (before switching service)
kubectl port-forward deployment/bluegreen-demo-green 8081:3000
curl http://localhost:8081/health
curl http://localhost:8081/version

# Run smoke tests
./run-smoke-tests.sh http://localhost:8081

# Only then switch traffic
./switch-to-green.sh
```

### 2. Implement Proper Health Checks

- **Liveness probe:** Check application is running
- **Readiness probe:** Check application can serve traffic
- **Startup probe:** For slow-starting applications

```yaml
startupProbe:  # For slow starts
  httpGet:
    path: /health
    port: 3000
  failureThreshold: 30
  periodSeconds: 10  # Allow up to 5 minutes for startup
```

### 3. Use Resource Limits

Prevent resource exhaustion:

```yaml
resources:
  requests:
    memory: "64Mi"
    cpu: "100m"
  limits:
    memory: "128Mi"
    cpu: "200m"
```

### 4. Implement Graceful Shutdown

Handle SIGTERM properly:

```javascript
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down gracefully');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});
```

Set appropriate termination grace period:

```yaml
spec:
  terminationGracePeriodSeconds: 30
```

### 5. Monitor During Switches

- Watch application logs
- Monitor error rates
- Check response times
- Verify endpoint health

```bash
# Monitor in real-time during switch
watch -n 1 'curl -s http://localhost:8080/version | jq .'
```

### 6. Automate Rollback Criteria

Define automatic rollback triggers:

- Error rate > threshold
- Response time > threshold
- Health check failures > threshold

### 7. Version Control Your Manifests

- Use Git to track all changes
- Tag releases in Git matching image tags
- Use GitOps tools like Argo CD for automation

### 8. Document Your Process

Create runbooks for:
- Deployment procedures
- Rollback procedures
- Troubleshooting steps
- Emergency contacts

### 9. Plan for Database Migrations

- Use backward-compatible changes
- Test migrations in staging
- Have rollback plan for data
- Consider blue-green for databases too

### 10. Clean Up Unused Environments

After successful switch and monitoring period:

```bash
# Scale down old environment
kubectl scale deployment bluegreen-demo-blue --replicas=0

# Or delete after confidence period (e.g., 24 hours)
kubectl delete deployment bluegreen-demo-blue
```

---

## Next Steps

Congratulations! You've completed the blue-green deployment tutorial.

### Enhance This Demo

1. **Add Ingress**
   - Use Ingress controller for HTTP routing
   - Implement host-based or path-based routing

2. **Add Monitoring**
   - Prometheus for metrics
   - Grafana for dashboards
   - Track deployment success rates

3. **Implement Canary Deployments**
   - Gradually shift traffic (10%, 25%, 50%, 100%)
   - Use service mesh (Istio/Linkerd) for advanced traffic splitting

4. **Automate with CI/CD**
   - GitHub Actions, GitLab CI, or Jenkins
   - Automated testing before traffic switch
   - Automated rollback on failures

5. **Add Feature Flags**
   - Enable/disable features without deployment
   - A/B testing capabilities
   - Progressive rollout of features

### Explore Related Patterns

- **Canary Deployments**: Gradual traffic shifting
- **Rolling Updates**: Progressive pod replacement
- **A/B Testing**: Split traffic for testing
- **Shadow Deployments**: Duplicate traffic for testing

### Additional Learning Resources

- Kubernetes Official Documentation
- CNCF Cloud Native Glossary
- 12-Factor App Methodology
- Site Reliability Engineering (SRE) books
- Progressive Delivery patterns

---

## Summary

You've learned:

- Blue-green deployment concepts and benefits
- How to build and containerize applications
- Kubernetes deployments and services
- Traffic switching using label selectors
- Instant rollback capabilities
- Testing and monitoring strategies
- Troubleshooting common issues
- Best practices for production use

The blue-green deployment pattern is powerful for achieving zero-downtime deployments with instant rollback capability. While it requires more resources, the benefits for production systems often outweigh the costs.

Happy deploying!
