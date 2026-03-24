# Blue-Green Deployment Quick Reference

A one-page cheat sheet for quick deployment and troubleshooting.

## Quick Start Commands

```bash
# 1. Build images
docker build -t bluegreen-demo:v1.0 ./app/
docker build -t bluegreen-demo:v2.0 ./app/

# 2. Load to cluster (kind)
kind load docker-image bluegreen-demo:v1.0
kind load docker-image bluegreen-demo:v2.0

# 3. Deploy blue
kubectl apply -f k8s/deployment-blue.yaml
kubectl apply -f k8s/service.yaml

# 4. Deploy green
kubectl apply -f k8s/deployment-green.yaml

# 5. Switch to green
kubectl patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"green"}}}'

# 6. Rollback to blue
kubectl patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"blue"}}}'
```

## Helper Scripts

```bash
cd scripts
chmod +x *.sh

./deploy-blue.sh          # Build and deploy blue
./deploy-green.sh         # Build and deploy green
./switch-to-blue.sh       # Switch traffic to blue
./switch-to-green.sh      # Switch traffic to green
./status.sh               # Show current status
./cleanup.sh              # Delete all resources
```

## Essential kubectl Commands

### Viewing Resources

```bash
# Get all resources
kubectl get all -l app=bluegreen-demo

# Get specific deployment
kubectl get deployment bluegreen-demo-blue
kubectl get deployment bluegreen-demo-green

# Get pods by version
kubectl get pods -l version=blue
kubectl get pods -l version=green

# Get service
kubectl get svc bluegreen-demo

# Get endpoints
kubectl get endpoints bluegreen-demo
```

### Checking Status

```bash
# Check deployment rollout
kubectl rollout status deployment/bluegreen-demo-blue
kubectl rollout status deployment/bluegreen-demo-green

# Describe service
kubectl describe svc bluegreen-demo

# Check which version is active
kubectl get svc bluegreen-demo -o jsonpath='{.spec.selector.version}'

# View service selector
kubectl get svc bluegreen-demo -o jsonpath='{.spec.selector}' | jq .
```

### Logs and Debugging

```bash
# View logs
kubectl logs -l version=blue --tail=50
kubectl logs -l version=green --tail=50

# Follow logs
kubectl logs -l version=green -f

# Exec into pod
kubectl exec -it deployment/bluegreen-demo-green -- sh

# Events
kubectl get events --sort-by='.lastTimestamp' | tail -20
```

### Testing

```bash
# Port forward to test
kubectl port-forward deployment/bluegreen-demo-blue 8080:3000
kubectl port-forward deployment/bluegreen-demo-green 8081:3000
kubectl port-forward svc/bluegreen-demo 8080:80

# Test endpoints
curl http://localhost:8080/
curl http://localhost:8080/version
curl http://localhost:8080/health
```

## Traffic Switching

### Switch to Green

```bash
# Method 1: Using script
./scripts/switch-to-green.sh

# Method 2: Using kubectl patch
kubectl patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"green"}}}'

# Method 3: Using kubectl set
kubectl set selector svc bluegreen-demo 'app=bluegreen-demo,version=green'

# Verify
kubectl get svc bluegreen-demo -o jsonpath='{.spec.selector}' | jq .
```

### Switch to Blue (Rollback)

```bash
# Method 1: Using script
./scripts/switch-to-blue.sh

# Method 2: Using kubectl patch
kubectl patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"blue"}}}'

# Verify
kubectl get svc bluegreen-demo -o jsonpath='{.spec.selector}' | jq .
```

## Scaling

```bash
# Scale blue
kubectl scale deployment bluegreen-demo-blue --replicas=5

# Scale green
kubectl scale deployment bluegreen-demo-green --replicas=5

# Scale down (after successful switch)
kubectl scale deployment bluegreen-demo-blue --replicas=0
```

## Troubleshooting

### Check Pod Status

```bash
# Wide output with node info
kubectl get pods -l app=bluegreen-demo -o wide

# Describe problematic pod
kubectl describe pod <pod-name>

# Check pod logs
kubectl logs <pod-name>
kubectl logs <pod-name> --previous  # Previous container logs
```

### Service Not Routing

```bash
# Check service selector
kubectl get svc bluegreen-demo -o yaml | grep -A 3 selector

# Check endpoints (should match active pods)
kubectl get endpoints bluegreen-demo -o yaml

# Compare pod labels with service selector
kubectl get pods --show-labels -l app=bluegreen-demo
```

### Image Pull Issues

```bash
# Check image pull status
kubectl describe pod <pod-name> | grep -A 10 Events

# List images in cluster (kind)
docker exec -it kind-control-plane crictl images

# Manually load image (kind)
kind load docker-image bluegreen-demo:v2.0
```

### Health Check Failures

```bash
# Check probe configuration
kubectl get deployment bluegreen-demo-green -o yaml | grep -A 10 Probe

# Test health endpoint directly
kubectl port-forward pod/<pod-name> 9090:3000
curl http://localhost:9090/health
curl http://localhost:9090/ready
```

## Cleanup

```bash
# Delete specific deployment
kubectl delete deployment bluegreen-demo-blue
kubectl delete deployment bluegreen-demo-green

# Delete service
kubectl delete svc bluegreen-demo

# Delete everything
kubectl delete all -l app=bluegreen-demo

# Or use script
./scripts/cleanup.sh
```

## Common Patterns

### Deploy New Version Workflow

```bash
# 1. Deploy new version to idle environment (green)
kubectl apply -f k8s/deployment-green.yaml

# 2. Wait for rollout
kubectl rollout status deployment/bluegreen-demo-green

# 3. Test green directly
kubectl port-forward deployment/bluegreen-demo-green 8081:3000
curl http://localhost:8081/version

# 4. Run smoke tests (your custom tests)
./run-smoke-tests.sh http://localhost:8081

# 5. Switch traffic
./scripts/switch-to-green.sh

# 6. Monitor for issues
kubectl logs -l version=green -f

# 7. If issues, rollback immediately
./scripts/switch-to-blue.sh

# 8. If stable, scale down old version
kubectl scale deployment bluegreen-demo-blue --replicas=0
```

### Emergency Rollback

```bash
# Immediate rollback
kubectl patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"blue"}}}'

# Verify
for i in {1..10}; do curl -s http://localhost:8080/version | jq -r .version; done
```

## Verification Checklist

Before switching traffic:

- [ ] New deployment shows READY (kubectl get deployment)
- [ ] All pods are Running and 1/1 Ready (kubectl get pods)
- [ ] Readiness probe passes (kubectl describe pods)
- [ ] Health endpoint responds (curl via port-forward)
- [ ] Smoke tests pass
- [ ] No error logs (kubectl logs)

After switching traffic:

- [ ] Service selector updated (kubectl get svc -o yaml)
- [ ] Endpoints point to new pods (kubectl get endpoints)
- [ ] Version endpoint returns new version (curl)
- [ ] No increase in error rate
- [ ] Response times acceptable
- [ ] Logs show traffic on new version

## Useful Aliases

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgd='kubectl get deployments'
alias kdp='kubectl describe pod'
alias kl='kubectl logs'
alias klf='kubectl logs -f'
alias kex='kubectl exec -it'
alias kpf='kubectl port-forward'

# Blue-Green specific
alias bg-status='kubectl get all -l app=bluegreen-demo'
alias bg-blue='kubectl get pods -l version=blue'
alias bg-green='kubectl get pods -l version=green'
alias bg-active='kubectl get svc bluegreen-demo -o jsonpath="{.spec.selector.version}"'
```

## Environment Variables for Scripts

```bash
# Set namespace
export NAMESPACE=bluegreen-demo

# Run scripts with custom namespace
NAMESPACE=production ./scripts/switch-to-green.sh
```

## Monitoring Commands

```bash
# Watch pod status
watch kubectl get pods -l app=bluegreen-demo

# Watch service endpoints
watch kubectl get endpoints bluegreen-demo

# Continuous version check
watch -n 1 'curl -s http://localhost:8080/version | jq .'

# Monitor resource usage
kubectl top pods -l app=bluegreen-demo
kubectl top nodes
```

## JSON Path Examples

```bash
# Get service external IP
kubectl get svc bluegreen-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Get active version
kubectl get svc bluegreen-demo -o jsonpath='{.spec.selector.version}'

# Get pod IPs
kubectl get pods -l version=green -o jsonpath='{.items[*].status.podIP}'

# Get container image
kubectl get deployment bluegreen-demo-green -o jsonpath='{.spec.template.spec.containers[0].image}'
```

## Quick Reference: Key Files

```
k8s/
├── deployment-blue.yaml    # Blue deployment (v1.0)
├── deployment-green.yaml   # Green deployment (v2.0)
├── service.yaml            # Service with selector
└── namespace.yaml          # Optional namespace

scripts/
├── deploy-blue.sh         # Deploy blue
├── deploy-green.sh        # Deploy green
├── switch-to-blue.sh      # Switch traffic to blue
├── switch-to-green.sh     # Switch traffic to green
├── status.sh              # Show status
└── cleanup.sh             # Clean up all resources
```

## Key Concepts

- **Blue**: Current production version
- **Green**: New version being deployed
- **Service Selector**: Routes traffic based on labels
- **Zero Downtime**: Both versions run, instant switch
- **Rollback**: Change selector back to previous version

## Remember

1. Always test green before switching
2. Monitor after switching
3. Keep blue running until green is proven stable
4. Document your rollback procedure
5. Automate what you can, but understand manual steps
