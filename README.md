# Blue-Green Deployment Demo for OpenShift/Kubernetes

A comprehensive hands-on learning path for understanding and implementing blue-green deployment strategies on **Red Hat OpenShift** and Kubernetes. **Includes real-world ConfigMap management use case.**

🎯 **Try it FREE on Red Hat Developer Sandbox** - No installation required! Get a free OpenShift cluster for 30 days at [sandbox.redhat.com](https://sandbox.redhat.com/)

## What is Blue-Green Deployment?

Blue-green deployment is a release management strategy that reduces downtime and risk by running two identical production environments (blue and green). At any time, only one environment serves production traffic while the other remains idle or serves as a staging environment.

### Key Benefits

- **Zero-downtime deployments**: Switch traffic instantly between environments
- **Easy rollback**: Revert to the previous version by switching traffic back
- **Testing in production**: Test new versions in a production-like environment
- **Reduced risk**: New version is fully deployed and tested before receiving traffic
- **Safe ConfigMap updates**: Avoid the common pitfall of mutable ConfigMaps breaking applications ([see detailed use case](CONFIGMAP-USECASE.md))

## Architecture Overview

```
User Traffic
     |
     v
Service (selector: version: blue OR green)
     |
     +---> Blue Deployment (v1.0)
     |
     +---> Green Deployment (v2.0)
```

The service uses label selectors to route traffic to either the blue or green deployment. Traffic switching is accomplished by updating the service's selector.

## Real-World Use Case: Safe ConfigMap Updates

**Problem:** A common issue in Kubernetes is updating ConfigMaps in-place, which can break applications:
- Changes propagate gradually to pods (not atomic)
- No easy way to test config before it goes live
- Difficult to rollback when bad configuration breaks the app
- Pods may run with mixed configurations during rollout

**Solution:** Blue-green deployments with immutable ConfigMaps:
- Each environment (blue/green) has its own ConfigMap
- Test new configuration in green before switching traffic
- Instant atomic switch when config is verified
- Instant rollback if configuration causes issues
- Configuration versioned with code in git

See [CONFIGMAP-USECASE.md](CONFIGMAP-USECASE.md) for detailed explanation, examples, and best practices.

## Repository Structure

```
.
├── README.md                          # This file
├── OPENSHIFT-SANDBOX.md               # Red Hat Developer Sandbox guide
├── TUTORIAL.md                        # Step-by-step tutorial
├── CONFIGMAP-USECASE.md               # ConfigMap update use case
├── app/                               # Sample application (Red Hat UBI base)
│   ├── Dockerfile
│   ├── package.json
│   └── server.js
├── k8s/                               # Kubernetes/OpenShift manifests
│   ├── configmap-blue.yaml            # Blue configuration
│   ├── configmap-green.yaml           # Green configuration
│   ├── deployment-blue.yaml
│   ├── deployment-green.yaml
│   └── service.yaml
└── scripts/                           # Deployment automation
    ├── deploy-blue.sh
    ├── deploy-green.sh
    ├── switch-to-blue.sh
    └── switch-to-green.sh
```

## Quick Start

### Option 1: Red Hat Developer Sandbox (Recommended - FREE!)

**Get started in minutes with a free OpenShift cluster!**

#### Prerequisites
- Red Hat account (free to create)
- Web browser
- `oc` CLI tool ([download here](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/))

#### Setup Steps

1. **Get your free OpenShift cluster**
   - Visit [sandbox.redhat.com](https://sandbox.redhat.com/)
   - Click "Start your sandbox for free"
   - Login or create a Red Hat account
   - Wait for your sandbox to provision (~2 minutes)

2. **Get your login command**
   - Click on your username (top right)
   - Select "Copy login command"
   - Click "Display Token"
   - Copy the `oc login` command

3. **Login to your cluster**
   ```bash
   # Paste your login command (example):
   oc login --token=sha256~xxxxx --server=https://api.sandbox.openshiftapps.com:6443

   # Switch to your dev project (namespace is auto-created)
   oc project $(oc whoami)-dev
   ```

4. **Deploy the demo**
   ```bash
   # Clone the repository
   git clone https://github.com/johwes/blue-green.git
   cd blue-green

   # Deploy ConfigMaps
   oc apply -f k8s/configmap-blue.yaml
   oc apply -f k8s/configmap-green.yaml

   # Build the application image (OpenShift builds it for you!)
   oc new-build --name=bluegreen-demo --binary --strategy=docker
   oc start-build bluegreen-demo --from-dir=./app --follow

   # Tag the image for blue and green
   oc tag bluegreen-demo:latest bluegreen-demo:v1.0
   oc tag bluegreen-demo:latest bluegreen-demo:v2.0

   # Deploy blue
   oc apply -f k8s/deployment-blue.yaml
   oc set image deployment/bluegreen-demo-blue \
     app=image-registry.openshift-image-registry.svc:5000/$(oc project -q)/bluegreen-demo:v1.0

   # Create service (ClusterIP for sandbox)
   cat <<EOF | oc apply -f -
   apiVersion: v1
   kind: Service
   metadata:
     name: bluegreen-demo
   spec:
     type: ClusterIP
     selector:
       app: bluegreen-demo
       version: blue
     ports:
     - port: 80
       targetPort: 3000
   EOF

   # Expose with OpenShift route
   oc expose service bluegreen-demo

   # Get your route URL
   echo "Your app is available at: http://$(oc get route bluegreen-demo -o jsonpath='{.spec.host}')"
   ```

5. **Deploy green and test switching**
   ```bash
   # Deploy green
   oc apply -f k8s/deployment-green.yaml
   oc set image deployment/bluegreen-demo-green \
     app=image-registry.openshift-image-registry.svc:5000/$(oc project -q)/bluegreen-demo:v2.0

   # Wait for green to be ready
   oc rollout status deployment/bluegreen-demo-green

   # Test both configurations
   ROUTE=$(oc get route bluegreen-demo -o jsonpath='{.spec.host}')
   curl http://$ROUTE/config  # Shows blue config

   # Switch to green
   oc patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"green"}}}'
   curl http://$ROUTE/config  # Shows green config

   # Rollback to blue
   oc patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"blue"}}}'
   ```

**See [OPENSHIFT-SANDBOX.md](OPENSHIFT-SANDBOX.md) for detailed instructions with screenshots.**

---

### Option 2: Local Kubernetes (minikube/kind)

For local development without OpenShift:

#### Prerequisites
- Kubernetes cluster (minikube or kind)
- kubectl configured
- Docker for building images

#### Deploy Steps
```bash
# Build images locally
docker build -t bluegreen-demo:v1.0 ./app/
docker build -t bluegreen-demo:v2.0 ./app/

# Load to cluster
kind load docker-image bluegreen-demo:v1.0
kind load docker-image bluegreen-demo:v2.0

# Deploy
kubectl apply -f k8s/configmap-blue.yaml
kubectl apply -f k8s/deployment-blue.yaml
kubectl apply -f k8s/service.yaml

# Test
kubectl port-forward svc/bluegreen-demo 8080:80
curl http://localhost:8080/config
```

See [TUTORIAL.md](TUTORIAL.md) for complete local setup instructions.

## Learning Path

Follow the [TUTORIAL.md](TUTORIAL.md) for a comprehensive step-by-step guide that covers:

1. Understanding blue-green deployment concepts
2. Setting up your Kubernetes environment
3. Building and deploying the sample application
4. Implementing traffic switching
5. Testing rollback scenarios
6. Best practices and considerations

## Next Steps

After completing this demo, consider exploring:

- **Canary deployments**: Gradually shift traffic to new versions
- **GitOps with Argo CD**: Automate deployments with declarative GitOps
- **Service mesh**: Use Istio or Linkerd for advanced traffic management
- **Progressive delivery**: Combine blue-green with feature flags and observability

## Resources

### Red Hat OpenShift
- [Red Hat Developer Sandbox](https://sandbox.redhat.com/) - Free OpenShift cluster for 30 days
- [OpenShift Documentation](https://docs.openshift.com/)
- [OpenShift CLI (oc) Download](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/)
- [Red Hat Developer](https://developers.redhat.com/) - Tutorials and learning paths

### Kubernetes & Cloud Native
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [12-Factor App Methodology](https://12factor.net/)
- [CNCF Cloud Native Glossary](https://glossary.cncf.io/)
