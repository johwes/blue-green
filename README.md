# Blue-Green Deployment Demo for Kubernetes

A comprehensive hands-on learning path for understanding and implementing blue-green deployment strategies using native Kubernetes resources.

## What is Blue-Green Deployment?

Blue-green deployment is a release management strategy that reduces downtime and risk by running two identical production environments (blue and green). At any time, only one environment serves production traffic while the other remains idle or serves as a staging environment.

### Key Benefits

- **Zero-downtime deployments**: Switch traffic instantly between environments
- **Easy rollback**: Revert to the previous version by switching traffic back
- **Testing in production**: Test new versions in a production-like environment
- **Reduced risk**: New version is fully deployed and tested before receiving traffic

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

## Repository Structure

```
.
├── README.md                          # This file
├── TUTORIAL.md                        # Step-by-step tutorial
├── app/                               # Sample application
│   ├── Dockerfile
│   ├── package.json
│   └── server.js
├── k8s/                               # Kubernetes manifests
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

### Prerequisites

- Kubernetes cluster (minikube, kind, or cloud provider)
- kubectl configured
- Docker (for building images)

### Deploy the Demo

```bash
# 1. Deploy blue version (v1.0)
kubectl apply -f k8s/deployment-blue.yaml
kubectl apply -f k8s/service.yaml

# 2. Verify blue is running
kubectl get pods -l app=bluegreen-demo
kubectl get svc bluegreen-demo

# 3. Deploy green version (v2.0)
kubectl apply -f k8s/deployment-green.yaml

# 4. Switch traffic to green
./scripts/switch-to-green.sh

# 5. Rollback to blue if needed
./scripts/switch-to-blue.sh
```

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

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [12-Factor App Methodology](https://12factor.net/)
- [CNCF Cloud Native Glossary](https://glossary.cncf.io/)
