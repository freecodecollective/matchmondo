import os
import json
import base64
import threading
import urllib.request
import urllib.error
from http.server import HTTPServer, BaseHTTPRequestHandler

GITHUB_PAT = os.environ.get("GITHUB_PAT", "")
REPO = "freecodecollective/matchmondo"
IOS_REPO = "freecodecollective/matchmondo-ios"
FILE_PATH = "data/trivia.json"
GH_API = f"https://api.github.com/repos/{REPO}/contents/{FILE_PATH}"
WORKFLOW_API = f"https://api.github.com/repos/{IOS_REPO}/actions/workflows/process-trivia.yml/dispatches"
ALLOWED_ORIGINS = [
    "https://freecodecollective.github.io",
    "http://localhost:8011",
    "http://127.0.0.1:8011",
]


def has_pending_tasks(put_body):
    try:
        content_b64 = json.loads(put_body).get("content", "")
        trivia = json.loads(base64.b64decode(content_b64))
        if any(t.get("status") == "pending" for t in trivia.get("pendingTasks", [])):
            return True
        if any(q.get("claudeTask") for q in trivia.get("questions", [])):
            return True
    except Exception:
        pass
    return False


def trigger_workflow():
    try:
        req = urllib.request.Request(WORKFLOW_API, method="POST", headers={
            "Accept": "application/vnd.github.v3+json",
            "Authorization": f"token {GITHUB_PAT}",
            "Content-Type": "application/json",
            "User-Agent": "trivia-proxy",
        }, data=json.dumps({"ref": "main"}).encode())
        urllib.request.urlopen(req, timeout=10)
        print("Triggered trivia processor workflow")
    except Exception as e:
        print(f"Failed to trigger workflow: {e}")


class Handler(BaseHTTPRequestHandler):
    def _cors(self):
        origin = self.headers.get("Origin", "")
        if origin in ALLOWED_ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
        self.send_header("Access-Control-Allow-Methods", "GET, PUT, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Max-Age", "86400")

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self):
        if self.path != "/api/trivia":
            self.send_response(404)
            self.end_headers()
            return
        try:
            req = urllib.request.Request(GH_API, headers={
                "Accept": "application/vnd.github.v3+json",
                "Authorization": f"token {GITHUB_PAT}",
                "User-Agent": "trivia-proxy",
            })
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = resp.read()
            self.send_response(200)
            self._cors()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(data)
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self._cors()
            self.end_headers()
            self.wfile.write(e.read())

    def do_PUT(self):
        if self.path != "/api/trivia":
            self.send_response(404)
            self.end_headers()
            return
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        pending = has_pending_tasks(body)
        try:
            req = urllib.request.Request(GH_API, data=body, method="PUT", headers={
                "Accept": "application/vnd.github.v3+json",
                "Authorization": f"token {GITHUB_PAT}",
                "Content-Type": "application/json",
                "User-Agent": "trivia-proxy",
            })
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = resp.read()
            self.send_response(200)
            self._cors()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(data)
            if pending:
                threading.Thread(target=trigger_workflow, daemon=True).start()
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self._cors()
            self.end_headers()
            self.wfile.write(e.read())

    def log_message(self, fmt, *args):
        print(f"{self.client_address[0]} - {fmt % args}")


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"Proxy listening on :{port}")
    server.serve_forever()
