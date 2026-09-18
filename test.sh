#!/bin/bash

IP=""
DEBUG=false
DETACH=false

usage() {
    echo "Usage: $0 --ip <k8s-webserver-ip> [--debug] [--detach]"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --ip) IP="$2"; shift ;;
        --debug) DEBUG=true ;;
        --detach) DETACH=true ;;
        *) usage ;;
    esac
    shift
done

if [[ -z "$IP" ]]; then
    usage
fi

if [ "$DEBUG" = true ]; then
    echo "DEBUG MODE ENABLED"
    set -x
fi

if [ "$DETACH" = true ]; then
    echo "-----------------------------"
    echo "DETACHED MODE"
    echo "1. Start the trigger:"
    echo "   curl http://localhost:8080/api/start"
    echo ""
    echo "2. Wait a few seconds, then check results:"
    echo "   curl http://localhost:8080/api/results"
    echo "-----------------------------"
    read -n 1 -s -r -p "Press any key to launch local-webserver... "
    echo ""
    python3 -u local-webserver.py --endpoint "$IP"
    exit 0
fi

echo "--- Testing Egress IP ---"

# Start local server in background
echo "Starting local-webserver on port 8080 targeting $IP..."
python3 -u local-webserver.py --endpoint "$IP" &
SERVER_PID=$!

# Give server a moment to start
sleep 2

echo "Sending request to /api/start..."
curl -s http://localhost:8080/api/start
echo -e "\nWaiting for callbacks to complete..."
sleep 5

echo "--- Final Results ---"
RESULT=$(curl -s http://localhost:8080/api/results)
echo "$RESULT" | python3 -m json.tool

# Parse JSON using python for reliability
OUTSIDE=$(echo "$RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('outside_cluster_initiated_egress_ip', 'null'))")
INSIDE=$(echo "$RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('inside_cluster_initiated_egress_ip', 'null'))")
INGRESS=$(echo "$RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('ingress_k8s_ip', 'null'))")

echo "-----------------------------"
if [[ "$OUTSIDE" == "null" && "$INSIDE" == "null" ]]; then
    echo "Result: FAILED - No egress IPs captured. Check connectivity and firewall."
elif [[ "$OUTSIDE" == "$INSIDE" ]]; then
    echo "Result: SUCCESS - Egress IPs match: $OUTSIDE"
else
    echo "Result: SUCCESS - Different egress IPs detected!"
    echo "Ingress K8s IP: $INGRESS"
    echo "Outside Initiated: $OUTSIDE"
    echo "Inside Initiated: $INSIDE"
fi
echo "-----------------------------"

kill $SERVER_PID

