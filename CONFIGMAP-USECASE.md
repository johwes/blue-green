# ConfigMap Updates and Blue-Green Deployments

## The Problem: Mutable ConfigMaps Breaking Applications

A common Kubernetes anti-pattern is updating ConfigMaps in-place and expecting running applications to pick up the changes. This approach has several critical issues:

### What Goes Wrong

1. **Gradual, Non-Atomic Updates**
   - ConfigMap changes propagate gradually to pods (can take minutes)
   - Some pods get new config while others still use old config
   - Application behavior becomes inconsistent across replicas

2. **No Easy Rollback**
   - If bad configuration breaks the app, you must:
     - Edit the ConfigMap again with correct values
     - Wait for changes to propagate to all pods
     - Or force pod restarts and wait for rollout
   - This can take 5-15 minutes during an outage

3. **No Testing Before Deployment**
   - Configuration goes live immediately as pods restart
   - No way to validate config in production before exposing to users
   - First indication of problems is often user-facing errors

4. **Unclear Which Version is Running**
   - Hard to know which pods have picked up new config
   - Difficult to correlate issues with config changes
   - No immutable audit trail

### Real-World Example

```bash
# Developer updates ConfigMap with typo
oc edit configmap app-config
# Changed: MAX_REQUESTS_PER_MINUTE: "100"
# To:      MAX_REQUESTS_PER_MINUTE: "10"  (typo - meant 1000)

# Pods gradually restart and pick up the config
# Application starts rate-limiting aggressively
# Users see "Too Many Requests" errors
# Team scrambles to figure out what changed
# Takes 10 minutes to identify, fix, and rollout correction
```

## The Solution: Blue-Green Deployments with Immutable ConfigMaps

### Key Principle: Configuration is Versioned with Code

Instead of one mutable ConfigMap, create separate ConfigMaps for each version:
- `app-config-blue` for blue deployment
- `app-config-green` for green deployment

### How It Works

```
Traditional (Mutable):                   Blue-Green (Immutable):

┌────────────────┐                     ┌──────────────────┐
│   ConfigMap    │                     │ ConfigMap-Blue   │
│   (updated)    │                     │  (immutable)     │
└───────┬────────┘                     └────────┬─────────┘
        │                                       │
        │ Gradual propagation                   │
        │                              ┌────────▼─────────┐
    ┌───▼─────┐                        │ Blue Deployment  │
    │  Pods   │                        │   (v1.0)         │
    │ (mixed) │                        └──────────────────┘
    └─────────┘
                                       ┌──────────────────┐
                                       │ ConfigMap-Green  │
                                       │  (immutable)     │
                                       └────────┬─────────┘
                                                │
                                       ┌────────▼─────────┐
                                       │ Green Deployment │
                                       │   (v2.0)         │
                                       └──────────────────┘
```

### Benefits

**1. Atomic Configuration Changes**
```bash
# Blue runs with old config (stable)
ocget pods -l version=blue
# All blue pods use configmap-blue

# Deploy green with new config
ocapply -f configmap-green.yaml
ocapply -f deployment-green.yaml
# All green pods use configmap-green

# Test green before switching traffic
ocport-forward deployment/bluegreen-demo-green 8081:3000
curl http://localhost:8081/config

# Switch traffic ONLY when green is verified
ocpatch svc bluegreen-demo -p '{"spec":{"selector":{"version":"green"}}}'
```

**2. Instant Rollback**
```bash
# If green config breaks something
ocpatch svc bluegreen-demo -p '{"spec":{"selector":{"version":"blue"}}}'
# Traffic back to blue in < 1 second
# Green still running for debugging
```

**3. Safe Testing in Production**
```bash
# Green is deployed with new config
# But receives NO user traffic
# Test thoroughly before switching

# Run smoke tests
./test-green-config.sh

# Verify feature flags work
curl http://green-pod-ip:3000/config

# Only switch when confident
```

**4. Clear Version Tracking**
```bash
# Know exactly which config each deployment uses
ocget configmap -l version=blue
ocget configmap -l version=green

# Audit trail through git
git log openshift/configmap-green.yaml
```

## Implementation Example

### Step 1: Create Versioned ConfigMaps

**configmap-blue.yaml** (Current production config)
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-blue
  labels:
    app: myapp
    version: blue
data:
  MAX_REQUESTS_PER_MINUTE: "100"
  FEATURE_NEW_UI: "false"
  API_TIMEOUT: "5000"
```

**configmap-green.yaml** (New config to test)
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-green
  labels:
    app: myapp
    version: green
data:
  MAX_REQUESTS_PER_MINUTE: "200"  # Increased
  FEATURE_NEW_UI: "true"          # New feature enabled
  API_TIMEOUT: "3000"             # Reduced timeout
```

### Step 2: Reference in Deployments

**deployment-blue.yaml**
```yaml
spec:
  template:
    spec:
      containers:
      - name: app
        envFrom:
        - configMapRef:
            name: app-config-blue  # Immutable reference
```

**deployment-green.yaml**
```yaml
spec:
  template:
    spec:
      containers:
      - name: app
        envFrom:
        - configMapRef:
            name: app-config-green  # Different ConfigMap
```

### Step 3: Deployment Workflow

```bash
# 1. Current state: Blue is active with blue config
ocget svc myapp -o jsonpath='{.spec.selector.version}'
# Output: blue

# 2. Create new ConfigMap for green
ocapply -f configmap-green.yaml

# 3. Deploy green with new config
ocapply -f deployment-green.yaml

# 4. Wait for green to be ready
ocrollout status deployment/myapp-green

# 5. Test green configuration
ocport-forward deployment/myapp-green 8081:3000
curl http://localhost:8081/config
# Verify config values are correct

# 6. Run integration tests against green
./run-tests.sh http://localhost:8081

# 7. Switch traffic to green (if tests pass)
ocpatch svc myapp -p '{"spec":{"selector":{"version":"green"}}}'

# 8. Monitor for issues
oclogs -f -l version=green

# 9. Rollback if needed (instant)
ocpatch svc myapp -p '{"spec":{"selector":{"version":"blue"}}}'

# 10. Clean up blue after green is stable (24-48 hours)
ocdelete deployment myapp-blue
ocdelete configmap app-config-blue
```

## Common Scenarios

### Scenario 1: Feature Flag Change

**Problem with mutable ConfigMap:**
```bash
# Change feature flag
ocpatch configmap app-config -p '{"data":{"FEATURE_NEW_UI":"true"}}'
# Some pods get it, some don't
# Users see inconsistent UI
# Can't easily turn it off for all users
```

**Solution with blue-green:**
```bash
# Create green with new feature flag
# Test thoroughly
# Switch traffic atomically
# All users see consistent behavior
# Can rollback instantly if needed
```

### Scenario 2: Database Connection Pool Size

**Problem with mutable ConfigMap:**
```bash
# Increase DB connections
ocpatch configmap app-config -p '{"data":{"DB_MAX_CONNECTIONS":"50"}}'
# Pods restart gradually
# Some pods overwhelm DB with 50 connections
# Other pods still use 10 connections
# DB performance is unpredictable
```

**Solution with blue-green:**
```bash
# Deploy green with DB_MAX_CONNECTIONS=50
# All green pods use new value consistently
# Monitor DB performance before switching traffic
# Switch only if DB handles the load well
```

### Scenario 3: API Timeout Configuration

**Problem with mutable ConfigMap:**
```bash
# Someone reduces timeout too much
ocpatch configmap app-config -p '{"data":{"API_TIMEOUT":"100"}}'
# Pods start timing out legitimate requests
# Errors spike
# Need to find the change, fix it, and wait for propagation
```

**Solution with blue-green:**
```bash
# Create green with API_TIMEOUT=100
# Test against green: curl http://green:3000/api/slow-endpoint
# Tests timeout! Don't switch traffic!
# Fix green ConfigMap, redeploy green
# Test again until satisfied
# Switch traffic only when working
```

## Best Practices

### 1. Treat ConfigMaps as Immutable

```bash
# Don't do this:
ocedit configmap app-config  # ❌

# Do this:
# Edit configmap-green.yaml in git
# Commit and push
# Deploy new version with new ConfigMap
ocapply -f configmap-green.yaml  # ✓
```

### 2. Version ConfigMaps with Deployments

```
git/
├── openshift/
│   ├── deployment-blue.yaml
│   ├── configmap-blue.yaml    # Versioned together
│   ├── deployment-green.yaml
│   └── configmap-green.yaml   # Versioned together
```

### 3. Include Config in Testing

```bash
# Test script
test_config() {
  # Test that config is read correctly
  curl http://$ENDPOINT/config | jq .

  # Test feature flags work
  if [ "$FEATURE_NEW_UI" = "true" ]; then
    curl http://$ENDPOINT/ui | grep "new-ui-class"
  fi

  # Test rate limiting
  for i in {1..150}; do
    curl http://$ENDPOINT/api
  done
  # Should see rate limit at configured threshold
}
```

### 4. Document Configuration Changes

```yaml
# configmap-green.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-green
  annotations:
    description: "v2.0 configuration with new UI feature enabled"
    change-request: "JIRA-1234"
    author: "john@example.com"
    date: "2024-01-15"
data:
  FEATURE_NEW_UI: "true"  # Enabled for v2.0 release
  API_TIMEOUT: "3000"     # Reduced from 5000ms per performance testing
```

### 5. Monitor Configuration Drift

```bash
# Compare configs between environments
diff <(ocget cm app-config-blue -o yaml) \
     <(ocget cm app-config-green -o yaml)

# Ensure blue and green use different ConfigMaps
ocget deployment -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}{"\n"}{end}'
```

## Troubleshooting

### Issue: Green pods not starting

```bash
# Check ConfigMap exists
ocget configmap app-config-green

# Check ConfigMap is referenced correctly
ocget deployment myapp-green -o yaml | grep -A 3 envFrom

# Describe pod to see errors
ocdescribe pod -l version=green
```

### Issue: Config not being read

```bash
# Verify environment variables in pod
ocexec -it deployment/myapp-green -- env | grep -E "FEATURE|API|DB"

# Check /config endpoint
ocport-forward deployment/myapp-green 8081:3000
curl http://localhost:8081/config
```

### Issue: Accidentally switched with bad config

```bash
# Immediate rollback
ocpatch svc myapp -p '{"spec":{"selector":{"version":"blue"}}}'

# Verify
curl http://myapp/config
# Should show blue configuration

# Fix green ConfigMap
ocapply -f configmap-green-fixed.yaml

# Update green deployment to pick up new ConfigMap
ocrollout restart deployment/myapp-green

# Test again before switching
```

## Summary

| Approach | ConfigMap Updates | Blue-Green with ConfigMaps |
|----------|------------------|---------------------------|
| Update Speed | Gradual (minutes) | Instant (< 1 second) |
| Consistency | Mixed versions across pods | All pods use same config |
| Rollback Time | 5-15 minutes | < 1 second |
| Testing | Limited | Full production testing |
| Audit Trail | Edit history only | Git history + versions |
| Risk Level | High | Low |

**Key Takeaway:** ConfigMap changes are deployments. Treat them with the same care and process as code deployments. Blue-green deployments make configuration changes safe, testable, and instantly reversible.
