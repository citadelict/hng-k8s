#!/bin/bash


# Variables
NAMESPACE="test"
SERVICE_NAME="test"
DOMAIN="${SERVICE_NAME}.endpoint.demo-domain.online"
NODE_IP="node ip"  

# Step 1: Create the test namespace if it doesn't exist
echo "Creating namespace '$NAMESPACE' if it doesn't exist..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Step 2: Deploy a VM-like pod using citatech/pod-base-image:latest
echo "Deploying VM-like pod in '$NAMESPACE' namespace..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vm-pod
  namespace: $NAMESPACE
  labels:
    app: vm-pod
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vm-pod
  strategy:
    type: Recreate  # Ensures no disruption during updates
  template:
    metadata:
      labels:
        app: vm-pod
    spec:
      containers:
      - name: vm
        image: citatech/pod-base-image:latest
        imagePullPolicy: Always
        command: ["/bin/bash", "-c", "while true; do sleep 3600; done"]  # Keep container running indefinitely
        ports:
        - containerPort: 80
        - containerPort: 22  # For SSH access if needed
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        volumeMounts:
        - name: vm-data
          mountPath: /data
      volumes:
      - name: vm-data
        emptyDir: {}  # Persists as long as the pod exists
EOF

# Step 3: Create a Service for the VM pod
echo "Creating service '$SERVICE_NAME' in '$NAMESPACE' namespace..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $SERVICE_NAME
  namespace: $NAMESPACE
spec:
  selector:
    app: vm-pod
  ports:
  - name: http
    port: 80
    targetPort: 80
  - name: ssh
    port: 22
    targetPort: 22
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
sleep 10

# Step 6: Get the NodePort and construct the full domain with port
echo "Checking service details in '$NAMESPACE' namespace..."
HTTP_NODE_PORT=$(kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
SSH_NODE_PORT=$(kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="ssh")].nodePort}')

if [ -z "$HTTP_NODE_PORT" ]; then
  echo "Error: Could not retrieve HTTP NodePort for service '$SERVICE_NAME'. Check service status:"
  kubectl describe svc "$SERVICE_NAME" -n "$NAMESPACE"
  exit 1
fi

# Output the full domain name with the mapped port
FULL_DOMAIN="http://${DOMAIN}:${HTTP_NODE_PORT}"
echo "Service '$SERVICE_NAME' deployed successfully!"
echo "Full domain with port: $FULL_DOMAIN"
echo "SSH access available on: ${NODE_IP}:${SSH_NODE_PORT}"

# Get the pod name for easy access
POD_NAME=$(kubectl get pods -n $NAMESPACE -l app=vm-pod -o jsonpath='{.items[0].metadata.name}')
echo "Pod name: $POD_NAME"
echo ""
echo "Access your VM-like pod with: kubectl exec -it -n $NAMESPACE $POD_NAME -- bash"

# Optional: Test the endpoint if web server is running in the image
echo "Note: HTTP access will only work if a web server is running in the base image"