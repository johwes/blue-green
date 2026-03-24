# Blue-Green Deployment Architecture

Visual architecture diagrams and explanations for the blue-green deployment strategy.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         INTERNET                             │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            │
                    ┌───────▼────────┐
                    │ Load Balancer  │
                    │  (Cloud/LB)    │
                    └───────┬────────┘
                            │
                            │
        ┌───────────────────┼───────────────────┐
        │     Kubernetes Cluster                │
        │                   │                   │
        │          ┌────────▼────────┐          │
        │          │   Service       │          │
        │          │ (bluegreen-demo)│          │
        │          │                 │          │
        │          │  Selector:      │          │
        │          │  version: blue  │ ◄────────┼─── Traffic routing key
        │          └────────┬────────┘          │
        │                   │                   │
        │      ┌────────────┴────────────┐      │
        │      │                         │      │
        │      │                         │      │
        │  ┌───▼────────┐        ┌──────▼───┐  │
        │  │Blue Deploy │        │Green Dep │  │
        │  │  v1.0      │        │  v2.0    │  │
        │  │            │        │          │  │
        │  │replicas: 3 │        │replicas:3│  │
        │  └───┬────────┘        └──────┬───┘  │
        │      │                        │      │
        │  ┌───┴──┬────┬───┐    ┌──┬───┴──┬─┐ │
        │  │Pod   │Pod │Pod│    │P │Pod   │P│ │
        │  │v1.0  │v1.0│v1 │    │v2│v2.0  │v2│ │
        │  └──────┴────┴───┘    └──┴──────┴─┘ │
        │                                      │
        └──────────────────────────────────────┘
```

## Traffic Flow - Initial State (Blue Active)

```
Users
  │
  │  HTTP Request
  │
  ▼
┌─────────────────┐
│ LoadBalancer    │
│ External IP     │
└────────┬────────┘
         │
         │ Port 80
         │
         ▼
┌─────────────────────────┐
│ Service                 │
│ Name: bluegreen-demo    │
│                         │
│ Selector:               │
│   app: bluegreen-demo   │
│   version: blue  ◄──────┼── Routes to BLUE only
│                         │
│ Port: 80 → 3000         │
└────────┬────────────────┘
         │
         │ Matches labels
         │
    ┌────▼─────┐
    │          │
    │   BLUE   │
    │  ACTIVE  │
    │          │
    └──────────┘

┌──────────────────────┐
│ Blue Deployment      │
│ Labels:              │
│   app: bluegreen-demo│
│   version: blue      │ ◄── MATCHES service selector
└──────────────────────┘

┌──────────────────────┐
│ Green Deployment     │
│ Labels:              │
│   app: bluegreen-demo│
│   version: green     │ ◄── Does NOT match
└──────────────────────┘
    │
    │
    │   GREEN
    │  STANDBY
    │ (No Traffic)
    │
    └──────────┘
```

## Traffic Switch Process

### Step 1: Before Switch (Blue Active, Green Deployed)

```
┌─────────┐
│ Service │
│         │
│ version:│
│  blue   │ ──────────┐
└─────────┘           │
                      │
         ┌────────────▼───────┐      ┌──────────────────┐
         │ Blue Deployment    │      │ Green Deployment │
         │ ✓ Active           │      │ ○ Standby        │
         │ ✓ Receiving Traffic│      │ ✓ Deployed       │
         │ ✓ Version v1.0     │      │ ✓ Healthy        │
         └────────────────────┘      │ ○ No Traffic     │
                                     │ ✓ Version v2.0   │
                                     └──────────────────┘
```

### Step 2: Execute Switch

```
kubectl patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"green"}}}'
                                        │
                                        │ Change selector
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────┐
│ Service Configuration Update                            │
│                                                          │
│ OLD:  selector: {app: bluegreen-demo, version: blue}   │
│                                                          │
│ NEW:  selector: {app: bluegreen-demo, version: green}  │
└─────────────────────────────────────────────────────────┘
                    │
                    │ Kubernetes reconciles endpoints
                    │ Takes < 1 second
                    ▼
```

### Step 3: After Switch (Green Active)

```
┌─────────┐
│ Service │
│         │
│ version:│
│  green  │ ──────────────────┐
└─────────┘                   │
                              │
         ┌──────────────────┐ │   ┌────────────▼──────┐
         │ Blue Deployment  │ │   │ Green Deployment  │
         │ ○ Standby        │ │   │ ✓ Active          │
         │ ○ No Traffic     │ │   │ ✓ Receiving       │
         │ ✓ Still Running  │ │   │   Traffic         │
         │ ✓ Version v1.0   │ │   │ ✓ Version v2.0    │
         └──────────────────┘ │   └───────────────────┘
                              │
                    Ready for instant rollback
```

## Detailed Component Architecture

### Deployment Component (Blue)

```
┌────────────────────────────────────────────────────────────┐
│ Deployment: bluegreen-demo-blue                            │
├────────────────────────────────────────────────────────────┤
│ Metadata:                                                  │
│   name: bluegreen-demo-blue                                │
│   labels:                                                  │
│     app: bluegreen-demo                                    │
│     version: blue                                          │
├────────────────────────────────────────────────────────────┤
│ Spec:                                                      │
│   replicas: 3                                              │
│   selector:                                                │
│     matchLabels:                                           │
│       app: bluegreen-demo                                  │
│       version: blue                                        │
│   template:                                                │
│     metadata:                                              │
│       labels:                                              │
│         app: bluegreen-demo                                │
│         version: blue                                      │
│     spec:                                                  │
│       containers:                                          │
│       - name: app                                          │
│         image: bluegreen-demo:v1.0                         │
│         env:                                               │
│         - VERSION=v1.0                                     │
│         - COLOR=blue                                       │
│         ports:                                             │
│         - containerPort: 3000                              │
│         livenessProbe:                                     │
│           httpGet: /health                                 │
│         readinessProbe:                                    │
│           httpGet: /ready                                  │
└────────────────────────────────────────────────────────────┘
```

### Service Component

```
┌────────────────────────────────────────────────────────────┐
│ Service: bluegreen-demo                                    │
├────────────────────────────────────────────────────────────┤
│ Type: LoadBalancer                                         │
│                                                            │
│ Selector:  ◄────────────────────────────────────────────┐ │
│   app: bluegreen-demo                                   │ │
│   version: blue  ◄─── THIS FIELD CONTROLS TRAFFIC!     │ │
│                       Change to "green" to switch       │ │
│                       ────────────────────────────────────┘ │
│                                                            │
│ Ports:                                                     │
│   - port: 80                                               │
│     targetPort: 3000                                       │
│     protocol: TCP                                          │
│                                                            │
│ Endpoints: (auto-populated by Kubernetes)                 │
│   - 10.1.1.5:3000  ◄─── Blue Pod 1                       │
│   - 10.1.1.6:3000  ◄─── Blue Pod 2                       │
│   - 10.1.1.7:3000  ◄─── Blue Pod 3                       │
└────────────────────────────────────────────────────────────┘
```

## Pod Lifecycle

```
Blue Pod Lifecycle:
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│ Pending │───▶│ Running │───▶│ Ready   │───▶│ Active  │
└─────────┘    └─────────┘    └─────────┘    └─────────┘
     │              │              │              │
     │              │              │              │
  Created      Container      Readiness      Service
  by Deploy    Started        Probe          Sends
                              Passes         Traffic

Green Pod Lifecycle (before switch):
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│ Pending │───▶│ Running │───▶│ Ready   │───▶│ Standby │
└─────────┘    └─────────┘    └─────────┘    └─────────┘
                                                   │
                                                   │
                                              No Traffic
                                              (Not in service
                                               endpoints)

After Switch:
┌─────────┐                                   ┌─────────┐
│  Blue   │                                   │  Green  │
│ Active  │──── Traffic Switched ────────────▶│ Active  │
│ Standby │◀──── (Instant Rollback) ──────────│ Standby │
└─────────┘                                   └─────────┘
```

## Network Packet Flow

```
1. Initial Request (Blue Active)

Client ──┬──▶ LoadBalancer ──┬──▶ Service ──┬──▶ Blue Pod 1
         │                   │              │
         │                   │              ├──▶ Blue Pod 2
         │                   │              │
         │                   │              └──▶ Blue Pod 3
         │                   │
         │                   └──X──▶ Green Pods (not in endpoints)
         │

2. After Switch (Green Active)

Client ──┬──▶ LoadBalancer ──┬──▶ Service ──┬──X Blue Pods
         │                   │              │  (not in endpoints)
         │                   │              │
         │                   │              ├──▶ Green Pod 1
         │                   │              │
         │                   │              ├──▶ Green Pod 2
         │                   │              │
         │                   │              └──▶ Green Pod 3
```

## Label Matching Logic

```
Service Selector Logic:

selector:
  app: bluegreen-demo    ◄── AND
  version: blue          ◄── AND

Matches Pod if ALL labels present:

Blue Pod Labels:                Green Pod Labels:
  app: bluegreen-demo ✓           app: bluegreen-demo ✓
  version: blue       ✓           version: green      ✗

  Result: MATCH                   Result: NO MATCH
  ─────────────────               ─────────────────
  Pod added to                    Pod NOT in
  service endpoints               service endpoints


After changing selector to "green":

selector:
  app: bluegreen-demo    ◄── AND
  version: green         ◄── AND (changed!)

Blue Pod Labels:                Green Pod Labels:
  app: bluegreen-demo ✓           app: bluegreen-demo ✓
  version: blue       ✗           version: green      ✓

  Result: NO MATCH                Result: MATCH
  ────────────────                ─────────────
  Pod removed from                Pod added to
  service endpoints               service endpoints
```

## Rollback Flow

```
Issue Detected in Green
         │
         │
         ▼
┌──────────────────┐
│ Execute Rollback │
│ (Change selector │
│  back to blue)   │
└────────┬─────────┘
         │
         │ < 1 second
         │
         ▼
┌──────────────────┐
│ Traffic Returns  │
│ to Blue          │
│                  │
│ Green still runs │
│ for debugging    │
└──────────────────┘

Timeline:
─────────────────────────────────────────────────────▶
0s            10s            20s            30s
│              │              │              │
Deploy         Switch to      Issue          Rollback
Green          Green          Detected       to Blue
               │              │              │
               └──────────────┴──────────────┘
                      < 30 seconds total
```

## Resource Usage Over Time

```
During Deployment Cycle:

Resources
    │
    │   ┌─────────────────────┐
2x  │   │  Both Running       │
    │   │  Blue + Green       │
    │   │                     │
    ├───┼─────────────────────┼───────────────────┐
    │   │                     │                   │
1x  │───┘                     └───────────────────┤
    │   Blue Only                 Green Only      │
    │                                             │
    └─────┬──────────┬──────────┬────────────┬───┴─▶
          │          │          │            │     Time
          │          │          │            │
       Deploy     Switch     Monitor      Cleanup
       Green      Traffic    & Wait       Old Blue


Timeline Details:

Phase 1: Blue Only (Baseline)
├─ Resources: 1x (3 pods)
└─ Duration: Indefinite

Phase 2: Both Blue and Green
├─ Resources: 2x (6 pods total)
├─ Duration: Minutes to hours
├─ Activities:
│  ├─ Deploy green
│  ├─ Test green
│  ├─ Switch traffic
│  └─ Monitor green
└─ Cost: Temporary 2x resources

Phase 3: Green Only (New Baseline)
├─ Resources: 1x (3 pods)
├─ Duration: Indefinite
└─ Action: Delete or scale down blue
```

## Complete Deployment Sequence

```
┌──────────────────────────────────────────────────────────┐
│                  Deployment Sequence                     │
└──────────────────────────────────────────────────────────┘

1. Initial State
   ┌──────┐
   │ Blue │ ◀── Active, Receiving Traffic
   └──────┘


2. Deploy Green
   ┌──────┐    ┌───────┐
   │ Blue │    │ Green │ ◀── Deployed, No Traffic
   └──────┘    └───────┘
       ▲
       │
    Traffic


3. Test Green
   ┌──────┐    ┌───────┐
   │ Blue │    │ Green │ ◀── Direct Testing
   └──────┘    └───────┘
       ▲           ▲
       │           │
    Traffic    Port-forward
               for testing


4. Switch Traffic
   ┌──────┐    ┌───────┐
   │ Blue │    │ Green │
   └──────┘    └───────┘
                   ▲
                   │
                Traffic ◀── Switched!


5. Monitor
   ┌──────┐    ┌───────┐
   │ Blue │    │ Green │ ◀── Monitor metrics
   └──────┘    └───────┘      logs, errors
                   ▲
                   │
                Traffic


6. Cleanup (if stable)
                ┌───────┐
                │ Green │
                └───────┘
                    ▲
                    │
                 Traffic

   Blue deleted or scaled to 0
```

## Health Check Flow

```
Readiness Probe Flow:

┌─────────────┐
│   New Pod   │
│   Created   │
└──────┬──────┘
       │
       │ initialDelaySeconds: 5s
       │
       ▼
┌─────────────────┐
│ Readiness Probe │ ──HTTP GET /ready──▶ ┌──────────┐
│ Executes        │                       │   Pod    │
└────────┬────────┘ ◀─────200 OK─────────┘ port 3000│
         │                                 └──────────┘
         │
         │ Every 5 seconds (periodSeconds)
         │
         ▼
    ┌────────┐
    │Success?│
    └───┬────┘
        │
        ├─ YES ──▶ Mark Pod as Ready ──▶ Add to Service Endpoints
        │
        └─ NO ──▶ After 2 failures ──▶ Remove from Endpoints
                  (failureThreshold)


Liveness Probe Flow:

┌─────────────┐
│ Running Pod │
└──────┬──────┘
       │
       │ initialDelaySeconds: 10s
       │
       ▼
┌─────────────────┐
│ Liveness Probe  │ ──HTTP GET /health──▶ ┌──────────┐
│ Executes        │                        │   Pod    │
└────────┬────────┘ ◀─────200 OK──────────┘ port 3000│
         │                                  └──────────┘
         │
         │ Every 10 seconds
         │
         ▼
    ┌────────┐
    │Success?│
    └───┬────┘
        │
        ├─ YES ──▶ Pod continues running
        │
        └─ NO ──▶ After 3 failures ──▶ Restart Container
                  (failureThreshold)
```

## Summary

This architecture provides:

✓ **Zero Downtime**: Traffic switches instantly between environments
✓ **Easy Rollback**: Change selector back to previous version
✓ **Safety**: Test new version before exposing to users
✓ **Simplicity**: Uses standard Kubernetes resources
✓ **Flexibility**: Can scale, monitor, and manage independently

The key to blue-green deployment is the service selector - a simple label change that routes traffic from one deployment to another instantly.
