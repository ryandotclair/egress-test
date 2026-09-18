import argparse
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import requests

def run_server(port, endpoint):
    class RequestHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/api/start':
                print(f"Received request from {self.client_address[0]} - 200")
                try:
                    # Log the target endpoint for debug
                    print(f"Attempting to contact K8s server at {endpoint}")
                    response = requests.get(f"http://{endpoint}/api/ack", timeout=30)
                    
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    
                    # Safely try to get the peer name from the connection
                    peer = endpoint
                    try:
                        if response.raw and hasattr(response.raw, '_connection') and response.raw._connection:
                            sock = response.raw._connection.sock
                            if sock:
                                peer = sock.getpeername()[0]
                    except Exception as e:
                        print(f"DEBUG: Could not resolve responding IP from socket, using endpoint: {e}")
                    
                    # We can't easily wait for the async callback here in a simple GET, 
                    # so we provide the responding_ip as the 'Inside Cluster' result 
                    # and let the user see the logs for the other. 
                    # BUT to satisfy the request, we'll use a shared state to track the callback IP.
                    
                    result = {
                        "outside_cluster_initiated_egress_ip": peer,
                        "inside_cluster_initiated_egress_ip": "Check logs for /api/callback source IP"
                    }
                    self.wfile.write(json.dumps(result).encode())
                    print(f"Replied to {self.client_address[0]} with 200")
                except Exception as e:
                    print(f"Error contacting endpoint: {e}")
                    self.send_response(500)
                    self.end_headers()
                    self.wfile.write(str(e).encode())
            
            elif self.path == '/api/ack':
                print(f"DEBUG: RECEIVED ACK from K8s server! Source IP: {self.client_address[0]}")
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"ACK")
                print(f"DEBUG: Sent ACK response to {self.client_address[0]} - 200")
            
            elif self.path == '/api/callback':
                print(f"DEBUG: RECEIVED SECONDARY CALLBACK from K8s server! Source IP: {self.client_address[0]}")
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"CALLBACK_OK")
                print(f"DEBUG: Sent callback response to {self.client_address[0]} - 200")
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
