# Blue-Green Deployment Tutorial

## OpenShift Tutorial

This demo is designed for **Red Hat OpenShift**. For a comprehensive step-by-step tutorial, please see:

**[OPENSHIFT-SANDBOX.md](OPENSHIFT-SANDBOX.md)**

The OpenShift tutorial includes:

- ✅ Free Red Hat Developer Sandbox setup (no credit card needed)
- ✅ Complete deployment walkthrough
- ✅ OpenShift builds (no local Docker required)
- ✅ Traffic switching and rollback demonstrations
- ✅ ConfigMap management best practices
- ✅ Troubleshooting guide
- ✅ OpenShift vs Kubernetes comparison

## Quick Links

- **Get Free OpenShift Cluster**: [sandbox.redhat.com](https://sandbox.redhat.com/)
- **Full Tutorial**: [OPENSHIFT-SANDBOX.md](OPENSHIFT-SANDBOX.md)
- **ConfigMap Use Case**: [CONFIGMAP-USECASE.md](CONFIGMAP-USECASE.md)
- **Repository**: [github.com/johwes/blue-green](https://github.com/johwes/blue-green)

## Why OpenShift?

This demo focuses on Red Hat OpenShift because:

1. **Free to Try**: Red Hat Developer Sandbox provides a free OpenShift cluster for 30 days
2. **No Local Setup**: Everything runs in the cloud - no Docker Desktop or local cluster needed
3. **Production-Ready**: Real enterprise platform used by Red Hat customers
4. **Built-in Builds**: OpenShift builds your container images - no local Docker required
5. **Simple Routing**: OpenShift Routes provide instant external access
6. **Enterprise Features**: Security Context Constraints, built-in registry, and more

## Getting Started

The fastest way to get started:

```bash
# 1. Get free OpenShift cluster at https://sandbox.redhat.com/
# 2. Login to your cluster
oc login --token=sha256~xxxxx --server=https://api.sandbox...

# 3. Clone the repo
git clone https://github.com/johwes/blue-green.git
cd blue-green

# 4. Use the Makefile
make build        # Build in OpenShift
make deploy-all   # Deploy blue + service
make deploy-green # Deploy green
make switch-green # Switch to green
make status       # Check status
```

For detailed instructions, see [OPENSHIFT-SANDBOX.md](OPENSHIFT-SANDBOX.md).
