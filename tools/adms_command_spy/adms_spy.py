#!/usr/bin/env python3
"""
ADMS command spy / reverse proxy.

Point the device Cloud Server to this host:port, then forward all /iclock/*
traffic to the real ADMS (default: http://agap.top). Logs every wire command
line of the form C:<id>:<cmd> so you can capture Open Door dialect.

Usage:
  python3 adms_spy.py --listen 0.0.0.0:9088 --upstream http://agap.top
  # Device COMM > Cloud Server: IP=<this server>  Port=9088
"""

from __future__ import annotations

import argparse
import datetime as dt
import re
import socket
import sys
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Iterable
from urllib.parse import urlsplit

CMD_LINE_RE = re.compile(r"(?m)^C:[^\r\n]+")
HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "content-length",
    "host",
}


def ts() -> str:
    return dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


class SpyState:
    def __init__(self, upstream: str, log_path: Path) -> None:
        parts = urlsplit(upstream)
        if parts.scheme not in ("http", "https") or not parts.netloc:
            raise SystemExit(f"Invalid upstream URL: {upstream}")
        self.upstream = upstream.rstrip("/")
        self.upstream_host = parts.netloc
        self.log_path = log_path
        self.lock = threading.Lock()
        self.log_path.parent.mkdir(parents=True, exist_ok=True)

    def log(self, line: str) -> None:
        text = f"[{ts()}] {line}"
        print(text, flush=True)
        with self.lock:
            with self.log_path.open("a", encoding="utf-8") as f:
                f.write(text + "\n")

    def log_commands(self, sn: str, body: str, where: str) -> None:
        hits = CMD_LINE_RE.findall(body or "")
        if not hits:
            return
        self.log(f"*** ADMS COMMANDS from {where} SN={sn or '?'} ***")
        for hit in hits:
            self.log(f"  CMD> {hit.strip()}")


STATE: SpyState | None = None


def filter_request_headers(headers) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    for key, value in headers.items():
        if key.lower() in HOP_BY_HOP:
            continue
        out.append((key, value))
    return out


class AdmsSpyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt: str, *args) -> None:  # quieter access log
        if STATE:
            STATE.log(f"ACCESS {self.address_string()} {fmt % args}")

    def _sn(self) -> str:
        q = urlsplit(self.path).query
        for part in q.split("&"):
            if part.upper().startswith("SN="):
                return part.split("=", 1)[1]
        return ""

    def _proxy(self) -> None:
        assert STATE is not None
        sn = self._sn()
        length = int(self.headers.get("Content-Length", "0") or "0")
        body = self.rfile.read(length) if length > 0 else b""

        target = f"{STATE.upstream}{self.path}"
        req_headers = filter_request_headers(self.headers)
        req_headers.append(("Host", STATE.upstream_host.split("@")[-1]))
        # Prefer identity encoding so we can log plaintext body.
        req_headers = [(k, v) for k, v in req_headers if k.lower() != "accept-encoding"]
        req_headers.append(("Accept-Encoding", "identity"))

        STATE.log(
            f"{self.command} {self.path} SN={sn or '-'} bytes={len(body)} -> {STATE.upstream}"
        )
        if body and len(body) <= 4096:
            try:
                preview = body.decode("utf-8", errors="replace").replace("\r", "\\r").replace("\n", "\\n")
                STATE.log(f"  REQ body: {preview[:800]}")
            except Exception:
                pass

        request = urllib.request.Request(
            target,
            data=body if self.command in ("POST", "PUT", "PATCH") else None,
            method=self.command,
            headers=dict(req_headers),
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as resp:
                resp_body = resp.read()
                status = resp.status
                reason = resp.reason
                resp_headers = list(resp.headers.items())
        except urllib.error.HTTPError as e:
            resp_body = e.read() or b""
            status = e.code
            reason = e.reason
            resp_headers = list(e.headers.items()) if e.headers else []
        except Exception as e:
            STATE.log(f"UPSTREAM ERROR {e}")
            msg = f"OK\n".encode("utf-8")  # keep device calm
            self.send_response(200, "OK")
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)
            return

        text = ""
        try:
            text = resp_body.decode("utf-8", errors="replace")
        except Exception:
            text = ""

        STATE.log_commands(sn, text, f"{self.command} {urlsplit(self.path).path}")
        if text and "C:" not in text and len(text) <= 600:
            STATE.log(f"  RESP {status}: {text.replace(chr(10), ' | ')[:500]}")
        elif text and "C:" not in text:
            STATE.log(f"  RESP {status}: {len(resp_body)} bytes")

        self.send_response(status, reason)
        for key, value in resp_headers:
            if key.lower() in HOP_BY_HOP:
                continue
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(resp_body)))
        self.end_headers()
        self.wfile.write(resp_body)

    def do_GET(self) -> None:
        self._proxy()

    def do_POST(self) -> None:
        self._proxy()

    def do_PUT(self) -> None:
        self._proxy()

    def do_OPTIONS(self) -> None:
        self._proxy()


def parse_listen(value: str) -> tuple[str, int]:
    if ":" in value:
        host, port_s = value.rsplit(":", 1)
        return host or "0.0.0.0", int(port_s)
    return "0.0.0.0", int(value)


def main(argv: Iterable[str] | None = None) -> int:
    global STATE
    parser = argparse.ArgumentParser(description="ADMS reverse-proxy command spy")
    parser.add_argument("--listen", default="0.0.0.0:9088", help="bind host:port")
    parser.add_argument("--upstream", default="http://agap.top", help="real ADMS base URL")
    parser.add_argument(
        "--log",
        default=str(Path(__file__).resolve().parent / "adms_spy.log"),
        help="log file path",
    )
    args = parser.parse_args(list(argv) if argv is not None else None)

    host, port = parse_listen(args.listen)
    STATE = SpyState(args.upstream, Path(args.log))
    STATE.log(f"Starting ADMS spy on {host}:{port} -> {STATE.upstream}")
    STATE.log("Point device Cloud Server Address to this host, Port to listen port.")

    httpd = ThreadingHTTPServer((host, port), AdmsSpyHandler)
    # Avoid slow POST stalls on some firmwares
    httpd.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        STATE.log("Stopped.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
