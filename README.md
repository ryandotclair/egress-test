# K8s Egress IP Tester

A simple tool to verify the egress IP of a Kubernetes workload. It deploys a small Python web server to a K8s cluster and coordinates a "ping-pong" of requests between your local machine and the cluster to identify the actual source IP used for outbound traffic.

## Assumptions & Requirements

### Tooling
- **Python 3.9+**: Required for both local and K8s servers.
- **Podman**: Used for building and pushing the container image.
- **kubectl**: Configured and authenticated to a reachable K8s cluster.
- **curl**: Used for triggering the local test.

### Network
- **Inbound Access**: Your local machine must be reachable by the K8s cluster on port `8080` for the callback to work.
- **LoadBalancer**: The K8s cluster must support `type: LoadBalancer` services to provide an external IP.
- **Ingress (Traefik)**: If you use Traefik, ensure the ingress class is available and the controller is running.
- **Registry**: You must have access to a container registry that allows `podman push` (with `--tls-verify=false` supported if using a self-signed registry).

## Quick Start

### 1. Initialize the Cluster Server

**Option A: Standard LoadBalancer**
```
./init.sh --image my-registry.com/egress-test:v1 --namespace egress-test-ns
```

**Option B: Traefik Ingress** (example using the `kommander-traefik` class and a custom path)
```
./init.sh \
  --image my-registry.com/egress-test:v1 \
  --namespace egress-test-ns \
  --traefik \
  --path /api/ack \
  --ingressclass kommander-traefik
```

This will create a Deployment with two containers (the web server and a sidecar), a Service on port 80, and an Ingress resource that routes HTTP traffic at the specified path to the service.

### 2. Run the Egress Test
Find the external IP (LoadBalancer or Ingress IP) **or** a hostname that resolves to it and run the test.
```
# Foreground mode using an IP address
./test.sh --ip <EXTERNAL_IP>

# Foreground mode using a hostname (e.g., a DNS record pointing to the LB)
./test.sh --host <HOSTNAME>

# Detached mode (you manually trigger the start and later check results) using IP
./test.sh --ip <EXTERNAL_IP> --detach
# Or using hostname
./test.sh --host <HOSTNAME> --detach
# Then in another terminal:
curl http://localhost:8080/api/start
curl http://localhost:8080/api/results
```

The final output will include:
- `Ingress K8s IP`: The IP address of the LoadBalancer or Ingress that received your original request.
- `Outside Initiated`: The source IP seen when the pod replies to your request.
- `Inside Initiated`: The source IP used when the pod initiates a fresh connection back to you.

## How it Works
The tool uses a sidecar pattern:
- **Main Server** receives `/api/ack` from the client, writes a trigger file, and records the external IP used for the inbound request.
- **Sidecar** watches the trigger file, reads the client IP, and initiates a separate HTTP request back to the client at `/api/callback`. This isolates the *inside‑cluster* egress path.
- The **local server** records two IPs:
  1. `outside_cluster_initiated_egress_ip` – the source IP seen when the pod replies to your original request (the LoadBalancer VIP when using a LoadBalancer, or the Node IP when using an Ingress).
  2. `inside_cluster_initiated_egress_ip` – the source IP used when the pod initiates a fresh connection (the worker node IP).

## Troubleshooting
- **Timeout Errors**: Ensure your local firewall (macOS Firewall/pfctl, Ubuntu UFW, etc.) allows inbound traffic on port `8080`.
- **No Logs**: If the pod isn't logging, check `kubectl logs` to verify the containers are running and not in `CrashLoopBackOff`.
- **Ingress Not Routing**: Verify the Ingress controller is watching the specified `ingressClassName` and that the path you provided matches the request you send.
