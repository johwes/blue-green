# ConfigMap Updates and Blue-Green Deployments

## The Original Problem

When a ConfigMap update breaks an application in production, teams often ask: "What should I do? How long should I wait for the changes to propagate? What's the right threshold before manually restarting pods?"

**The answer: Don't wait. Don't set thresholds. Use blue-green deployments with immutable ConfigMaps.**

This approach eliminates the waiting game entirely. Instead of hoping Kubernetes will eventually restart all pods with the correct configuration, you deploy a completely new set of pods with the new config, test them, and only switch traffic when you're confident everything works.

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
oc get pods -l version=blue
# All blue pods use configmap-blue

# Deploy green with new config
oc apply -f configmap-green.yaml
oc apply -f deployment-green.yaml
# All green pods use configmap-green

# Test green before switching traffic
oc port-forward deployment/bluegreen-demo-green 8081:3000
curl http://localhost:8081/config

# Switch traffic ONLY when green is verified
oc patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"green"}}}'
```

**2. Instant Rollback**
```bash
# If green config breaks something
oc patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"blue"}}}'
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
oc get configmap -l version=blue
oc get configmap -l version=green

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
immutable: true  # Prevents accidental edits to live config
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
immutable: true  # Prevents accidental edits to live config
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

> **💡 Why `envFrom` instead of Volume Mounts?**
>
> There are two ways to consume ConfigMaps in Kubernetes:
>
> - **`envFrom` (used here):** ConfigMap values become environment variables. Pods **must restart** to see changes.
> - **Volume mounts:** ConfigMap becomes a file in the pod. Changes hot-reload **without restart** (after ~60 seconds).
>
> **Why envFrom is better for blue-green:**
> - **Explicit restarts:** New pods = new config. No surprises, no gradual updates.
> - **No partial reads:** With volume hot-reloads, your app might crash mid-read if config changes while it's being parsed.
> - **Health checks protect you:** With blue-green, new pods must pass readiness probes before receiving traffic. If bad config causes crashes, the service never switches to green.
>
> Blue-green deployments make `envFrom` safe by ensuring all pods start fresh with tested configuration.

### Step 3: Deployment Workflow

```bash
# 1. Current state: Blue is active with blue config
oc get svc myapp -o jsonpath='{.spec.selector.version}'
# Output: blue

# 2. Create new ConfigMap for green
oc apply -f configmap-green.yaml

# 3. Deploy green with new config
oc apply -f deployment-green.yaml

# 4. Wait for green to be ready
oc rollout status deployment/myapp-green

# ✓ CHECKPOINT: Both blue and green are running simultaneously
ocget deployments
# NAME          READY   UP-TO-DATE   AVAILABLE
# myapp-blue    3/3     3            3
# myapp-green   3/3     3            3

ocget pods -l app=myapp
# Shows pods from BOTH blue and green deployments
# This is normal! Blue handles traffic, green is ready for testing

# Visual representation of your cluster state:
#
#   User Traffic
#        |
#        v
#   ┌─────────┐
#   │ Service │  selector: version=blue
#   └────┬────┘
#        │
#        ├──────────┐
#        │          │
#   ┌────▼─────┐   │    ┌──────────────┐
#   │  Blue    │   │    │   Green      │
#   │  Pods    │   │    │   Pods       │
#   │ (active) │   │    │ (standby)    │
#   │          │◄──┘    │              │
#   │ v1.0     │        │ v2.0         │
#   │ config   │        │ config       │
#   │ -blue    │        │ -green       │
#   └──────────┘        └──────────────┘
#
# Blue = Receives ALL traffic (production)
# Green = Running but receives NO traffic (ready for testing)

# 5. Test green configuration
oc port-forward deployment/myapp-green 8081:3000
curl http://localhost:8081/config
# Verify config values are correct

# 6. Run integration tests against green
./run-tests.sh http://localhost:8081

# 7. Switch traffic to green (if tests pass)
oc patch svc myapp -p '{"spec":{"selector":{"version":"green"}}}'

# 8. Monitor for issues
oc logs -f -l version=green

# 9. Rollback if needed (instant)
oc patch svc myapp -p '{"spec":{"selector":{"version":"blue"}}}'

# 10. Clean up blue after green is stable (24-48 hours)
oc delete deployment myapp-blue
oc delete configmap app-config-blue
```

## Common Scenarios

### Scenario 1: Feature Flag Change

**Problem with mutable ConfigMap:**
```bash
# Change feature flag
oc patch configmap app-config -p '{"data":{"FEATURE_NEW_UI":"true"}}'
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
oc patch configmap app-config -p '{"data":{"DB_MAX_CONNECTIONS":"50"}}'
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
oc patch configmap app-config -p '{"data":{"API_TIMEOUT":"100"}}'
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
oc edit configmap app-config  # ❌

# Do this:
# Edit configmap-green.yaml in git
# Commit and push
# Deploy new version with new ConfigMap
oc apply -f configmap-green.yaml  # ✓
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
oc get deployment -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}{"\n"}{end}'
```

## Troubleshooting

### Issue: Green pods not starting

```bash
# Check ConfigMap exists
oc get configmap app-config-green

# Check ConfigMap is referenced correctly
oc get deployment myapp-green -o yaml | grep -A 3 envFrom

# Describe pod to see errors
oc describe pod -l version=green
```

### Issue: Config not being read

```bash
# Verify environment variables in pod
oc exec -it deployment/myapp-green -- env | grep -E "FEATURE|API|DB"

# Check /config endpoint
oc port-forward deployment/myapp-green 8081:3000
curl http://localhost:8081/config
```

### Issue: Accidentally switched with bad config

```bash
# Immediate rollback
oc patch svc myapp -p '{"spec":{"selector":{"version":"blue"}}}'

# Verify
curl http://myapp/config
# Should show blue configuration

# Fix green ConfigMap
oc apply -f configmap-green-fixed.yaml

# Update green deployment to pick up new ConfigMap
oc rollout restart deployment/myapp-green

# Test again before switching
```

## Advanced: Automated Config Hashing

Manually naming ConfigMaps as `-blue` and `-green` works well for learning and small deployments. In production environments with frequent configuration changes, many teams automate this pattern using **ConfigMap hashing**.

### The Concept

Instead of manually versioning ConfigMaps, tools like **Kustomize** and **Helm** automatically generate ConfigMap names based on the content:

```bash
# Kustomize automatically generates:
app-config-blue    → app-config-8f2d1a4b
app-config-green   → app-config-9c3e5f7a

# If you change even one character in the config:
app-config-green   → app-config-1a2b3c4d  # New hash, new name
```

### The Benefits

1. **Automatic immutability:** Every config change creates a new ConfigMap name
2. **No manual renaming:** The hash is computed from the content
3. **Automatic rollouts:** Changing the ConfigMap name triggers a Deployment update
4. **GitOps-friendly:** Config changes in git automatically create new resources

### Example with Kustomize

**kustomization.yaml**
```yaml
configMapGenerator:
- name: app-config
  literals:
  - MAX_REQUESTS_PER_MINUTE=200
  - FEATURE_NEW_UI=true
  - API_TIMEOUT=3000
```

When you run `oc apply -k .`, Kustomize generates:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-9c3e5f7a  # Hash automatically appended
data:
  MAX_REQUESTS_PER_MINUTE: "200"
  FEATURE_NEW_UI: "true"
  API_TIMEOUT: "3000"
```

And your Deployment automatically references the hashed name:
```yaml
spec:
  template:
    spec:
      containers:
      - envFrom:
        - configMapRef:
            name: app-config-9c3e5f7a  # Updated by Kustomize
```

### When to Use Hashing vs. Blue-Green

- **Manual Blue-Green (this guide):** Best for learning, infrequent config changes, explicit control
- **Automated Hashing:** Best for CI/CD pipelines, frequent changes, GitOps workflows

Both approaches achieve the same goal: **immutable, versioned configuration**. Blue-green gives you explicit control over testing and traffic switching. Hashing automates the versioning but requires more tooling.

**Learn more:**
- [Kustomize ConfigMap Generator](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/#configmapgenerator)
- [Helm ConfigMap Hashing](https://helm.sh/docs/howto/charts_tips_and_tricks/#automatically-roll-deployments)

## Summary

| Approach | ConfigMap Updates | Blue-Green with ConfigMaps |
|----------|------------------|---------------------------|
| Update Speed | Gradual (minutes) | Instant (< 1 second) |
| Consistency | Mixed versions across pods | All pods use same config |
| Rollback Time | 5-15 minutes | < 1 second |
| Testing | Limited | Full production testing |
| Audit Trail | Edit history only | Git history + versions |
| Risk Level | High | Low |

### Answering the Original Question

**"What should I do when a ConfigMap update breaks the application? How long should I wait? What's the right threshold?"**

With blue-green deployments and immutable ConfigMaps, these questions become irrelevant:

- **Don't wait:** The new configuration is deployed to green pods immediately. You don't wait for propagation—you test before switching.
- **No thresholds needed:** The "threshold" becomes: "Does the green deployment pass its readiness probes?" If green pods fail health checks due to bad config, the service never switches to them.
- **Instant recovery:** If you somehow switch to bad config, rollback is < 1 second via `oc patch svc`. No waiting for pod restarts or config propagation.

The problem shifts from a **technical timeout issue** (waiting for Kubernetes to restart things) to a **process-driven safety net** (test before switch, rollback if needed).

**Key Takeaway:** ConfigMap changes are deployments. Treat them with the same care and process as code deployments. Blue-green deployments make configuration changes safe, testable, and instantly reversible.
