#!/bin/bash
set -e

# Defaults
IMAGE=""
NAMESPACE=""
PATH_VAL="/api/ack"
INGRESS_CLASS="nginx"
USE_TRAEFIK=false

usage() {
    echo "Usage: $0 --image <image-name> --namespace <namespace> [--traefik] [--path <path>] [--ingressclass <class>]"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --image) IMAGE="$2"; shift ;;
        --namespace) NAMESPACE="$2"; shift ;;
        --traefik) USE_TRAEFIK=true ;;
        --path) PATH_VAL="$2"; shift ;;
        --ingressclass) INGRESS_CLASS="$2"; shift ;;
        *) usage ;;
    esac
    shift
done

if [[ -z "$IMAGE" || -z "$NAMESPACE" ]]; then
    usage
fi

echo "--- Initializing K8s Webserver ---"

echo "Installing local Python dependencies..."
pip install requests || echo "Warning: failed to install requests locally."

# 1. Build and Push Image
echo "Cleaning old local image $IMAGE..."
podman rmi "$IMAGE" 2>/dev/null || echo "Image not found locally, skipping delete."

echo "Building image $IMAGE (amd64)..."
if ! podman build --platform linux/amd64 -t "$IMAGE" -f Dockerfile . 2>/tmp/podman_err; then
    echo "Error: Failed to build image with podman."
    echo "Check if podman is installed and you have a valid Dockerfile."
    cat /tmp/podman_err
    exit 1
fi

echo "Pushing image $IMAGE..."
if ! podman push "$IMAGE" --tls-verify=false 2>/tmp/push_err; then
    echo "Error: Failed to push image to registry."
    echo "Ensure your registry is reachable and allows unverified TLS."
    cat /tmp/push_err
    exit 1
fi

# 2. Kubernetes Deployment
echo "Creating namespace $NAMESPACE..."
kubectl create namespace "$NAMESPACE" || echo "Namespace already exists, skipping..."

if [ "$USE_TRAEFIK" = true ]; then
    echo "Using Traefik template..."
    TEMPLATE="deployment.traefik.template.yaml"
    sed "s|{{IMAGE}}|$IMAGE|g; s|{{PATH}}|$PATH_VAL|g; s|{{INGRESS_CLASS}}|$INGRESS_CLASS|g" "$TEMPLATE" > deployment.yaml
else
    echo "Using standard template..."
    TEMPLATE="deployment.template.yaml"
    sed "s|{{IMAGE}}|$IMAGE|g" "$TEMPLATE" > deployment.yaml
fi

echo "Deploying to K8s..."
if ! kubectl apply -f deployment.yaml -n "$NAMESPACE" 2>/tmp/k8s_err; then
    echo "Error: Failed to deploy to Kubernetes."
    echo "Check your kubeconfig context and permissions for namespace $NAMESPACE."
    cat /tmp/k8s_err
    exit 1
fi

echo "Deployment successful. Please wait for the LoadBalancer IP to be assigned."
