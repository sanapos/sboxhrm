"""Mô phỏng nginx cho kiểm thử giao diện local: phục vụ flutter_client/build/web (SPA fallback)
và chuyển /api, /hubs… sang API local.

    python tools/local-test/web_proxy.py [cổng_web=8190] [api=http://localhost:7199]
"""
import http.server
import os
import socketserver
import sys
import urllib.error
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "flutter_client", "build", "web"))
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8190
API = sys.argv[2] if len(sys.argv) > 2 else "http://localhost:7199"
PROXY = ("/api/", "/hubs/", "/stores/", "/o/", "/uploads/", "/health")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=ROOT, **k)

    def _proxy(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        req = urllib.request.Request(API + self.path, data=body, method=self.command)
        for k, v in self.headers.items():
            if k.lower() not in ("host", "content-length", "connection"):
                req.add_header(k, v)
        try:
            resp = urllib.request.urlopen(req, timeout=120)
            status, headers, data = resp.status, resp.headers, resp.read()
        except urllib.error.HTTPError as e:
            status, headers, data = e.code, e.headers, e.read()
        except Exception as e:  # API chưa chạy
            status, headers, data = 502, {}, str(e).encode()
        self.send_response(status)
        for k, v in (headers.items() if hasattr(headers, "items") else []):
            if k.lower() not in ("transfer-encoding", "connection", "content-length"):
                self.send_header(k, v)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _route(self):
        if self.path.startswith(PROXY) or "/uploads/" in self.path:
            return self._proxy()
        path = self.path.split("?")[0]
        if path == "/" or not os.path.exists(os.path.join(ROOT, path.lstrip("/"))):
            self.path = "/index.html"
        return super().do_GET() if self.command == "GET" else super().do_HEAD()

    def do_GET(self):
        self._route()

    def do_HEAD(self):
        self._route()

    def do_POST(self):
        self._proxy()

    def do_PUT(self):
        self._proxy()

    def do_DELETE(self):
        self._proxy()

    def do_PATCH(self):
        self._proxy()

    def log_message(self, *a):
        pass


if not os.path.exists(os.path.join(ROOT, "index.html")):
    sys.exit(f"Missing web build at {ROOT} - run tools/local-test/build-web.sh first.")
socketserver.ThreadingTCPServer.allow_reuse_address = True
print(f"Web http://localhost:{PORT} -> API {API}", flush=True)
with socketserver.ThreadingTCPServer(("", PORT), Handler) as s:
    s.serve_forever()
