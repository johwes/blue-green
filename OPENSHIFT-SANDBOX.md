# Red Hat Developer Sandbox Quick Start Guide

Complete guide for deploying the blue-green demo on Red Hat Developer Sandbox - **a free OpenShift cluster for 30 days**.

## Why Use OpenShift Sandbox?

✅ **FREE** - No credit card required
✅ **No Installation** - Fully managed OpenShift cluster in the cloud
✅ **Production-Ready** - Real Red Hat OpenShift 4.x environment
✅ **30 Days** - Plenty of time to learn and experiment
✅ **Easy Setup** - Ready in minutes
✅ **Perfect for Learning** - Ideal for demos, POCs, and training

## Step 1: Get Your Free OpenShift Cluster

### 1.1 Visit Red Hat Developer Sandbox

Navigate to: **https://sandbox.redhat.com/**

### 1.2 Start Your Sandbox

Click the **"Start your sandbox for free"** button

### 1.3 Login or Create Account

- If you have a Red Hat account, login
- If not, click **"Register for a Red Hat account"**
  - Provide email, username, password
  - Verify your email
  - Complete registration

### 1.4 Wait for Provisioning

Your sandbox will provision automatically (takes ~2 minutes)

You'll see a screen saying "Your OpenShift cluster is ready!"

## Step 2: Install OpenShift CLI (oc)

### Download for Your Platform

**Linux:**
```bash
curl -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz -o oc.tar.gz
tar -xzf oc.tar.gz
sudo mv oc /usr/local/bin/
sudo mv kubectl /usr/local/bin/
oc version --client
```

**macOS:**
```bash
curl -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-mac.tar.gz -o oc.tar.gz
tar -xzf oc.tar.gz
sudo mv oc /usr/local/bin/
sudo mv kubectl /usr/local/bin/
oc version --client
```

**Windows:**
1. Download from: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-windows.zip
2. Extract the ZIP file
3. Add `oc.exe` to your PATH
4. Run `oc version --client` to verify

## Step 3: Login to Your Cluster

### 3.1 Get Your Login Command

1. In the OpenShift web console, click your **username** (top right corner)
2. Select **"Copy login command"**
3. You'll be redirected to a new page
4. Click **"Display Token"**
5. Copy the entire `oc login` command

It will look like:
```bash
oc login --token=sha256~xxxxxxxxxxxxx --server=https://api.sandbox-m2.ll9k.p1.openshiftapps.com:6443
```

### 3.2 Login from Terminal

Paste and run the login command:

```bash
oc login --token=sha256~xxxxxxxxxxxxx --server=https://api.sandbox-m2.ll9k.p1.openshiftapps.com:6443
```

You should see:
```
Logged into "https://api.sandbox-m2.ll9k.p1.openshiftapps.com:6443" as "your-username" using the token provided.

You have access to the following projects and can switch between them with 'oc project <projectname>':

    your-username-dev

Using project "your-username-dev".
```

### 3.3 Verify Your Project

```bash
# Check current project
oc project

# List all projects you have access to
oc projects

# Switch to your dev project (if not already)
oc project $(oc whoami)-dev
```

**Important:** In Developer Sandbox, you cannot create new projects/namespaces. Use your pre-created `<username>-dev` project.

## Step 4: Deploy Blue-Green Demo

### 4.1 Clone the Repository

```bash
git clone https://github.com/johwes/blue-green.git
cd blue-green
```

### 4.2 Deploy ConfigMaps

ConfigMaps are the same in OpenShift and Kubernetes:

```bash
oc apply -f k8s/configmap-blue.yaml
oc apply -f k8s/configmap-green.yaml
```

Verify:
```bash
oc get configmaps
```

You should see:
```
NAME                          DATA   AGE
bluegreen-demo-config-blue    8      5s
bluegreen-demo-config-green   8      5s
```

### 4.3 Build the Application Image

OpenShift can build container images for you using BuildConfig:

```bash
# Create a BuildConfig for binary builds
oc new-build --name=bluegreen-demo --binary --strategy=docker

# Start the build from the app directory
oc start-build bluegreen-demo --from-dir=./app --follow
```

This will:
1. Upload your app code to OpenShift
2. Build the container using your Dockerfile
3. Push to OpenShift's internal registry
4. Take ~1-2 minutes

You should see:
```
Uploading directory "app" as binary input for the build ...
...
Pushing image image-registry.openshift-image-registry.svc:5000/youruser-dev/bluegreen-demo:latest ...
Push successful
```

### 4.4 Tag Images for Blue and Green

```bash
# Tag as v1.0 for blue
oc tag bluegreen-demo:latest bluegreen-demo:v1.0

# Tag as v2.0 for green
oc tag bluegreen-demo:latest bluegreen-demo:v2.0
```

Verify:
```bash
oc get imagestream bluegreen-demo
```

### 4.5 Deploy Blue Environment

```bash
# Apply the blue deployment
oc apply -f k8s/deployment-blue.yaml

# Update to use the internal registry image
oc set image deployment/bluegreen-demo-blue \
  app=image-registry.openshift-image-registry.svc:5000/$(oc project -q)/bluegreen-demo:v1.0

# Wait for rollout
oc rollout status deployment/bluegreen-demo-blue
```

Verify blue is running:
```bash
oc get pods -l version=blue
```

You should see 3 pods running:
```
NAME                                   READY   STATUS    RESTARTS   AGE
bluegreen-demo-blue-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
bluegreen-demo-blue-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
bluegreen-demo-blue-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
```

### 4.6 Create Service

The service needs to be ClusterIP (not LoadBalancer) in Developer Sandbox:

```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: bluegreen-demo
  labels:
    app: bluegreen-demo
spec:
  type: ClusterIP
  selector:
    app: bluegreen-demo
    version: blue
  ports:
  - name: http
    port: 80
    targetPort: 3000
    protocol: TCP
EOF
```

### 4.7 Expose with OpenShift Route

OpenShift Routes provide external access (like Ingress in Kubernetes):

```bash
oc expose service bluegreen-demo
```

Get your route URL:
```bash
oc get route bluegreen-demo -o jsonpath='{.spec.host}'
```

Or get the full URL:
```bash
echo "http://$(oc get route bluegreen-demo -o jsonpath='{.spec.host}')"
```

### 4.8 Test Blue Environment

```bash
# Save route URL
ROUTE=$(oc get route bluegreen-demo -o jsonpath='{.spec.host}')

# Test root endpoint
curl http://$ROUTE/

# Test version endpoint
curl http://$ROUTE/version

# Test configuration endpoint (shows blue config)
curl http://$ROUTE/config | jq .
```

You should see blue configuration:
```json
{
  "version": "v1.0",
  "color": "blue",
  "configuration": {
    "maxRequestsPerMinute": 100,
    "featureFlags": {
      "enableNewUI": false,
      "enableCache": true,
      "enableMetrics": true
    },
    "apiTimeout": 5000,
    "logLevel": "info",
    "database": {
      "host": "postgres.database.svc.cluster.local",
      "maxConnections": 10
    }
  }
}
```

## Step 5: Deploy Green Environment

### 5.1 Deploy Green

```bash
# Apply green deployment
oc apply -f k8s/deployment-green.yaml

# Update to use v2.0 image
oc set image deployment/bluegreen-demo-green \
  app=image-registry.openshift-image-registry.svc:5000/$(oc project -q)/bluegreen-demo:v2.0

# Wait for rollout
oc rollout status deployment/bluegreen-demo-green
```

### 5.2 Verify Both Environments Running

```bash
oc get pods -l app=bluegreen-demo
```

You should see 6 pods total (3 blue + 3 green):
```
NAME                                    READY   STATUS    RESTARTS   AGE
bluegreen-demo-blue-xxxxxxxxxx-xxxxx    1/1     Running   0          3m
bluegreen-demo-blue-xxxxxxxxxx-xxxxx    1/1     Running   0          3m
bluegreen-demo-blue-xxxxxxxxxx-xxxxx    1/1     Running   0          3m
bluegreen-demo-green-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
bluegreen-demo-green-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
bluegreen-demo-green-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
```

### 5.3 Check Current Service Routing

```bash
# See which version is active
oc get svc bluegreen-demo -o jsonpath='{.spec.selector}'
```

Should show: `{"app":"bluegreen-demo","version":"blue"}`

## Step 6: Switch Traffic (Blue → Green)

### 6.1 Switch to Green

```bash
# Patch service to route to green
oc patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"green"}}}'
```

### 6.2 Verify Traffic Switched

```bash
# Check configuration (should now show green)
curl http://$ROUTE/config | jq '.configuration'
```

You should now see green configuration:
```json
{
  "maxRequestsPerMinute": 200,
  "featureFlags": {
    "enableNewUI": true,
    "enableCache": true,
    "enableMetrics": true
  },
  "apiTimeout": 3000,
  "logLevel": "debug",
  "database": {
    "host": "postgres.database.svc.cluster.local",
    "maxConnections": 20
  }
}
```

**Notice the differences:**
- maxRequestsPerMinute: 100 → 200 (doubled)
- enableNewUI: false → true (new feature enabled)
- apiTimeout: 5000 → 3000 (reduced)
- logLevel: info → debug (more verbose)
- DB connections: 10 → 20 (doubled)

## Step 7: Rollback (Green → Blue)

### 7.1 Instant Rollback

If you discover issues with green:

```bash
# Switch back to blue
oc patch svc bluegreen-demo -p '{"spec":{"selector":{"version":"blue"}}}'
```

### 7.2 Verify Rollback

```bash
curl http://$ROUTE/config | jq '.configuration'
```

Should show blue configuration again.

**Rollback time: < 2 seconds!**

## Step 8: Monitoring and Logs

### View Pods

```bash
# All blue-green pods
oc get pods -l app=bluegreen-demo

# Just blue
oc get pods -l version=blue

# Just green
oc get pods -l version=green
```

### View Logs

```bash
# Blue logs
oc logs -l version=blue --tail=50

# Green logs
oc logs -l version=green --tail=50

# Follow logs
oc logs -l version=green -f
```

### Check Service

```bash
# Service details
oc describe svc bluegreen-demo

# Current selector
oc get svc bluegreen-demo -o jsonpath='{.spec.selector}' | jq .

# Endpoints (pod IPs)
oc get endpoints bluegreen-demo
```

### Check Deployments

```bash
# All deployments
oc get deployments -l app=bluegreen-demo

# Deployment details
oc describe deployment bluegreen-demo-blue
oc describe deployment bluegreen-demo-green
```

## Step 9: Cleanup

When you're done with the demo:

```bash
# Delete everything
oc delete deployment bluegreen-demo-blue
oc delete deployment bluegreen-demo-green
oc delete svc bluegreen-demo
oc delete route bluegreen-demo
oc delete configmap bluegreen-demo-config-blue
oc delete configmap bluegreen-demo-config-green
oc delete buildconfig bluegreen-demo
oc delete imagestream bluegreen-demo
```

Or delete by label:
```bash
oc delete all,configmap -l app=bluegreen-demo
oc delete buildconfig,imagestream bluegreen-demo
```

## Troubleshooting

### Issue: Build Fails

**Check build logs:**
```bash
oc logs -f bc/bluegreen-demo
```

**Common causes:**
- Dockerfile syntax errors
- Missing files in app directory
- Network issues pulling base image

**Solution:** Fix the issue and rebuild:
```bash
oc start-build bluegreen-demo --from-dir=./app --follow
```

### Issue: Pods Not Starting

**Check pod status:**
```bash
oc get pods -l app=bluegreen-demo
oc describe pod <pod-name>
```

**Common causes:**
- Image pull errors
- Wrong image reference
- Resource quota exceeded

**Solution for image reference:**
```bash
# Verify image exists
oc get imagestream bluegreen-demo

# Update deployment with correct image
oc set image deployment/bluegreen-demo-blue \
  app=image-registry.openshift-image-registry.svc:5000/$(oc project -q)/bluegreen-demo:v1.0
```

### Issue: Route Not Accessible

**Check route:**
```bash
oc get route bluegreen-demo
oc describe route bluegreen-demo
```

**Test from within cluster:**
```bash
oc run test --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s http://bluegreen-demo/version
```

**Check if pods are ready:**
```bash
oc get pods -l app=bluegreen-demo
```

Make sure pods show `1/1 Running` status.

### Issue: Service Not Switching

**Verify selector was updated:**
```bash
oc get svc bluegreen-demo -o yaml | grep -A 3 selector
```

**Check endpoints:**
```bash
oc get endpoints bluegreen-demo
```

The IP addresses should match the pods for the selected version.

### Issue: ConfigMap Not Loading

**Verify ConfigMap exists:**
```bash
oc get configmap bluegreen-demo-config-blue -o yaml
```

**Check deployment references it:**
```bash
oc get deployment bluegreen-demo-blue -o yaml | grep -A 5 envFrom
```

**Restart pods to pick up ConfigMap:**
```bash
oc rollout restart deployment/bluegreen-demo-blue
```

## OpenShift Sandbox Limitations

Be aware of these sandbox limitations:

1. **No Namespace Creation** - Use your pre-created `<username>-dev` project
2. **No LoadBalancer** - Use Routes instead (we did this above)
3. **Resource Quotas** - Limited CPU/memory/storage
4. **30-Day Limit** - Sandbox expires after 30 days (can re-create)
5. **Sleep Mode** - Resources may sleep after inactivity (wake on access)
6. **No Persistent Volume Claims** - Limited PVC support

For production use, consider Red Hat OpenShift Service on AWS (ROSA), Azure Red Hat OpenShift (ARO), or OpenShift Dedicated.

## Next Steps

Now that you have the demo running:

1. **Experiment with switching**
   - Switch between blue and green multiple times
   - Observe instant traffic changes
   - Test rollback scenarios

2. **Modify ConfigMaps**
   - Edit `k8s/configmap-green.yaml`
   - Apply changes: `oc apply -f k8s/configmap-green.yaml`
   - Restart green: `oc rollout restart deployment/bluegreen-demo-green`
   - Test before switching traffic

3. **Update the application**
   - Modify `app/server.js`
   - Rebuild: `oc start-build bluegreen-demo --from-dir=./app --follow`
   - Tag: `oc tag bluegreen-demo:latest bluegreen-demo:v3.0`
   - Update deployment: `oc set image deployment/bluegreen-demo-green app=....:v3.0`

4. **Learn more**
   - Read [CONFIGMAP-USECASE.md](CONFIGMAP-USECASE.md) for ConfigMap best practices
   - Read [TUTORIAL.md](TUTORIAL.md) for deeper understanding
   - Explore [Red Hat Developer](https://developers.redhat.com/) for more tutorials

## OpenShift vs Kubernetes Differences

For those familiar with Kubernetes, here are key OpenShift differences:

| Feature | Kubernetes | OpenShift |
|---------|-----------|-----------|
| CLI | `kubectl` | `oc` (superset of kubectl) |
| Build System | External (Docker/CI) | Built-in (BuildConfig) |
| External Access | Ingress | Routes (simpler) |
| Registry | External | Built-in registry |
| Image Builds | CI/CD pipeline | `oc new-build`, `oc start-build` |
| Security | Manual | Security Context Constraints (automatic) |
| User Management | Basic RBAC | Advanced RBAC + Projects |

OpenShift includes everything in Kubernetes plus enterprise features like built-in CI/CD, developer console, operators, and more.

## Resources

- **Red Hat Developer Sandbox**: https://sandbox.redhat.com/
- **OpenShift Documentation**: https://docs.openshift.com/
- **OpenShift CLI Reference**: https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html
- **Red Hat Developer**: https://developers.redhat.com/
- **This Demo Repository**: https://github.com/johwes/blue-green

## Support

For sandbox issues:
- Check status: https://status.redhat.com/
- Community forums: https://developers.redhat.com/community
- Documentation: https://developers.redhat.com/developer-sandbox

For demo issues:
- Open an issue: https://github.com/johwes/blue-green/issues
- Read the docs: See README.md and TUTORIAL.md

---

**Congratulations!** 🎉 You've successfully deployed a blue-green application on Red Hat OpenShift using the Developer Sandbox. You now understand how to safely deploy configuration changes with zero downtime and instant rollback capabilities.
