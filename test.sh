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
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" http://localhost:8080/api/start 2>/tmp/curl_err)

if [[ $? -ne 0 ]]; then
    echo "Error: curl command failed to execute."
    cat /tmp/curl_err
    kill $SERVER_PID
    exit 1
fi

# Separate body and status code
HTTP_BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')
HTTP_CODE=$(echo "$RESPONSE" | grep 'HTTP_CODE:' | cut -d':' -f2)

echo "-----------------------------"
echo "HTTP Status: $HTTP_CODE"
if [[ "$HTTP_CODE" == "200" ]]; then
    echo "Result: SUCCESS"
    echo "$HTTP_BODY" | python3 -m json.tool
else
    echo "Result: FAILED"
    echo "Response Body: $HTTP_BODY"
    echo "-----------------------------"
    echo "Troubleshooting:"
    if [[ "$HTTP_CODE" == "500" ]]; then
        echo "- Local server could not reach $IP. Check K8s LoadBalancer IP and firewall rules."
    elif [[ "$HTTP_CODE" == "404" ]]; then
        echo "- Endpoint /api/start not found on local server."
    else
        echo "- Unexpected error occurred. Check server logs."
    fi
fi

if [ "$DETACH" = true ]; then
    echo "Detached mode: Local server will continue running in background (PID: $SERVER_PID)."
else
    kill $SERVER_PID
fi
echo "-----------------------------"
