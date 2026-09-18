import argparse
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import socket
import requests

# Global store for egress results
results = {
    "ingress_k8s_ip": None,
    "outside_cluster_initiated_egress_ip": None,
    "inside_cluster_initiated_egress_ip": None
}

def run_server(port, endpoint):
    class RequestHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            global results
            if self.path == '/api/start':
                results["ingress_k8s_ip"] = endpoint
                print(f"DEBUG: Triggering K8s server at {endpoint}...")

                try:
                    # We use a socket directly to reliably capture the responding IP
                    with socket.create_connection((endpoint, 80), timeout=5) as s:
                        s.sendall(b"GET /api/ack HTTP/1.1\r\nHost: " + endpoint.encode() + b"\r\n\r\n")
                        # The peername here is the IP that responded to our SYN
                        responding_ip = s.getpeername()[0]
                        print(f"DEBUG: Response received from IP: {responding_ip}")
                        results["outside_cluster_initiated_egress_ip"] = responding_ip
                except Exception as e:
                    print(f"DEBUG: Initial trigger error: {e}")
                
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"status": "Trigger sent, waiting for callbacks..."}).encode())
                print(f"Replied to {self.client_address[0]} with 200")
            
            elif self.path == '/api/ack':
                src_ip = self.client_address[0]
                print(f"DEBUG: RECEIVED ACK from K8s server! Source IP: {src_ip}")
                # We don't update outside_cluster_initiated_egress_ip here 
                # because that's for the response to our initial request.
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"ACK")
                print(f"DEBUG: Sent ACK response to {src_ip} - 200")
            
            elif self.path == '/api/callback':
                src_ip = self.client_address[0]
                print(f"DEBUG: RECEIVED SECONDARY CALLBACK from K8s server! Source IP: {src_ip}")
                results["inside_cluster_initiated_egress_ip"] = src_ip
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"CALLBACK_OK")
                print(f"DEBUG: Sent callback response to {src_ip} - 200")

            elif self.path == '/api/results':
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps(results, indent=4).encode())
                print(f"DEBUG: Returned results to {self.client_address[0]}")

            else:
                print(f"Received request from {self.client_address[0]} for {self.path} - 404")
                self.send_response(404)
                self.end_headers()

    server = HTTPServer(('0.0.0.0', port), RequestHandler)
    print(f"Local server running on port {port}, targeting endpoint {endpoint}...")
    server.serve_forever()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--endpoint', required=True, help='The IP address of the k8s-webserver')
    parser.add_argument('--port', type=int, default=8080, help='Port to run on')
    args = parser.parse_args()
    run_server(args.port, args.endpoint)
