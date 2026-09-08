#!/usr/bin/env python3
"""SSH/SFTP helper for sboxpos.com. Password from SBOXPOS_DEPLOY_PASSWORD."""
from __future__ import annotations

import os
import sys
import time

import paramiko

HOST = os.environ.get("SBOXPOS_HOST", "103.133.225.67")
USER = os.environ.get("SBOXPOS_USER", "root")
PASSWORD = os.environ.get("SBOXPOS_DEPLOY_PASSWORD") or os.environ.get("SBOXPOS_PW")


def connect() -> paramiko.SSHClient:
    if not PASSWORD:
        raise SystemExit("Set SBOXPOS_DEPLOY_PASSWORD")
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        HOST,
        username=USER,
        password=PASSWORD,
        timeout=30,
        allow_agent=False,
        look_for_keys=False,
        banner_timeout=30,
        auth_timeout=30,
    )
    return client


def run(cmd: str, timeout: int = 1800) -> int:
    print(f"\n>>> {cmd[:180]}")
    client = connect()
    try:
        stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout)
        while True:
            line = stdout.readline()
            if not line:
                break
            sys.stdout.buffer.write(line.encode("utf-8", errors="replace") if isinstance(line, str) else line)
            sys.stdout.buffer.flush()
        err = stderr.read().decode(errors="replace")
        if err.strip():
            sys.stderr.buffer.write(err.encode("utf-8", errors="replace"))
        code = stdout.channel.recv_exit_status()
        print(f"<<< exit {code}")
        return code
    finally:
        client.close()


def upload(local: str, remote: str) -> None:
    size = os.path.getsize(local)
    print(f"\n>>> upload {local} -> {remote} ({size / 1024 / 1024:.1f} MB)")
    client = connect()
    try:
        sftp = client.open_sftp()
        sent = {"n": 0, "t": time.time()}

        def cb(transferred: int, total: int) -> None:
            now = time.time()
            if now - sent["t"] >= 2 or transferred == total:
                pct = (transferred / total * 100) if total else 0
                print(f"    {transferred / 1024 / 1024:.1f}/{total / 1024 / 1024:.1f} MB ({pct:.0f}%)")
                sent["t"] = now

        sftp.put(local, remote, callback=cb)
        sftp.close()
    finally:
        client.close()
    print("<<< uploaded")


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: sboxpos_ssh.py run <cmd> | upload <local> <remote>")
        return 2
    action = sys.argv[1]
    if action == "run":
        return run(" ".join(sys.argv[2:]))
    if action == "upload":
        upload(sys.argv[2], sys.argv[3])
        return 0
    raise SystemExit(f"unknown action {action}")


if __name__ == "__main__":
    raise SystemExit(main())
