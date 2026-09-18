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
- **Registry**: You must have access to a container registry that allows `podman push` (with `--tls-verify=false` supported if using a self-signed registry).

## How it Works
1. **Local Server**: Runs a server that listens for callbacks and initiates the test.
2. **K8s Server**: A pod that receives the initial request and attempts to call back to the source IP.
3. **Egress Verification**: By checking the logs of the local server, you can see the exact IP the K8s pod used to exit the cluster.

## Quick Start

### 1. Initialize the Cluster Server
Build and deploy the server to your Kubernetes cluster.
```bash
./init.sh --image my-registry.com/egress-test:v1 --namespace egress-test-ns
```

### 2. Run the Egress Test
Find the LoadBalancer IP of your K8s service and run the test.
```bash
# In one terminal, run the test (foreground mode)
./test.sh --ip 1.2.3.4

# OR run in detached mode to manually trigger with curl
./test.sh --ip 1.2.3.4 --detach
curl http://localhost:8080/api/start
```

## Troubleshooting
- **Timeout Errors**: Ensure your local firewall (macOS Firewall/pfctl) allows inbound traffic on port `8080`.
- **No Logs**: If the K8s pod isn't logging, check `kubectl logs` to ensure the pod is running and not in `CrashLoopBackOff`.
