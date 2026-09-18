import argparse
from http.server import HTTPServer, BaseHTTPRequestHandler
import requests

def run_server(port):
    class RequestHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            client_ip = self.client_address[0]
            if self.path == '/api/ack':
                print(f"Received ACK request from {client_ip} - 200")
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"ACK")
                
                # Send back to the local-webserver (which is the source IP)
                try:
                    print(f"Attempting to send ACK back to source IP: {client_ip}")
                    requests.get(f"http://{client_ip}:8080/api/ack", timeout=30)
                    print(f"Successfully sent ACK to {client_ip}")
                except Exception as e:
                    print(f"Could not send ACK back to {client_ip}: {e}")

            else:
                print(f"Received request from {client_ip} for {self.path} - 404")
                self.send_response(404)
                self.end_headers()

    server = HTTPServer(('0.0.0.0', port), RequestHandler)
    print(f"K8s server running on port {port}...")
    server.serve_forever()

if __name__ == '__main__':
    run_server(80)
