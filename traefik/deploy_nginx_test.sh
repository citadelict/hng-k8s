#!/bin/bash

# Script to deploy an Nginx pod, service, and Traefik IngressRoute in the 'test' namespace

# Variables
NAMESPACE="test"
SERVICE_NAME="test"
DOMAIN="${SERVICE_NAME}.endpoint.demo-domain.online"
NODE_IP="nodeip"  

# Step 1: Create the test namespace if it doesn't exist
echo "Creating namespace '$NAMESPACE' if it doesn't exist..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Step 2: Deploy an Nginx pod
echo "Deploying Nginx pod in '$NAMESPACE' namespace..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
  namespace: $NAMESPACE
  labels:
    app: nginx
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
EOF

# Step 3: Create a Service for the Nginx pod
echo "Creating service '$SERVICE_NAME' in '$NAMESPACE' namespace..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $SERVICE_NAME
  namespace: $NAMESPACE
spec:
  selector:
    app: nginx
  ports:
  - name: http
    port: 80
    targetPort: 80
  type: NodePort
EOF

# Step 4: Create a Traefik IngressRoute
echo "Creating IngressRoute for '$DOMAIN' in '$NAMESPACE' namespace..."
cat <<EOF | kubectl apply -f -
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: ${SERVICE_NAME}-route
  namespace: $NAMESPACE
spec:
  entryPoints:
    - web
  routes:
  - match: Host(\`$DOMAIN\`)
    kind: Rule
    services:
    - name: $SERVICE_NAME
      port: 80
EOF

# Step 5: Wait briefly for the service to be assigned a NodePort
echo "Waiting for service to be ready..."
sleep 5

# Step 6: Get the NodePort and construct the full domain with port
echo "Checking service details in '$NAMESPACE' namespace..."
NODE_PORT=$(kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')

if [ -z "$NODE_PORT" ]; then
  echo "Error: Could not retrieve NodePort for service '$SERVICE_NAME'. Check service status:"
  kubectl describe svc "$SERVICE_NAME" -n "$NAMESPACE"
  exit 1
fi

# Output the full domain name with the mapped port
FULL_DOMAIN="http://${DOMAIN}:${NODE_PORT}"
echo "Service '$SERVICE_NAME' deployed successfully!"
echo "Full domain with port: $FULL_DOMAIN"

# Optional: Test the endpoint
echo "Testing the endpoint with curl..."
curl -v "$FULL_DOMAIN" || echo "Failed to connect to $FULL_DOMAIN"
