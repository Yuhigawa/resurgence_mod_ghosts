#!/usr/bin/env python3
"""Send a console command to the iw6-mod dedicated server over rcon.

The binary ships component@rcon with a (netadr_s&, std::string) handler and
the dvar rcon_password, so the standard Quake3-style out-of-band packet works:

    \\xff\\xff\\xff\\xff rcon <password> <command>

Usage:
    RCON_PASSWORD=... tools/rcon.py "spawn_bot 3"
    RCON_PASSWORD=... tools/rcon.py --host 127.0.0.1 --port 28960 "status"

The password is never stored in this repo. Pass it in the environment, and
launch the server with +set rcon_password <same value>.
"""
import argparse
import os
import socket
import sys

PREFIX = b"\xff\xff\xff\xff"


def send(host: str, port: int, password: str, command: str, timeout: float) -> str:
    payload = PREFIX + b"rcon " + password.encode() + b" " + command.encode()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(timeout)
        sock.sendto(payload, (host, port))
        chunks = []
        while True:
            try:
                data, _ = sock.recvfrom(65535)
            except socket.timeout:
                break
            if data.startswith(PREFIX):
                data = data[len(PREFIX):]
            chunks.append(data.decode("utf-8", "replace"))
    return "".join(chunks)


def main() -> int:
    ap = argparse.ArgumentParser(description="rcon a command to the Ghosts server")
    ap.add_argument("command", help="console command, e.g. 'spawn_bot 3'")
    ap.add_argument("--host", default=os.environ.get("RCON_HOST", "127.0.0.1"))
    ap.add_argument("--port", type=int, default=int(os.environ.get("RCON_PORT", "28960")))
    ap.add_argument("--timeout", type=float, default=5.0,
                    help="seconds to keep reading replies (default 5); a busy\n                         server needs several")
    ap.add_argument("--retries", type=int, default=4,
                    help="attempts before giving up (default 4); a busy "
                         "server drops replies")
    args = ap.parse_args()

    password = os.environ.get("RCON_PASSWORD")
    if not password:
        print("error: set RCON_PASSWORD (and launch the server with the same "
              "+set rcon_password value)", file=sys.stderr)
        return 2

    # A busy server (18 bots fighting) drops replies, so retry rather than
    # reporting a working server as down.
    reply = ""
    for attempt in range(args.retries):
        reply = send(args.host, args.port, password, args.command, args.timeout)
        if reply.strip():
            break
    if not reply.strip():
        print("(no reply — server down, wrong port, or rcon_password unset "
              "on the server)", file=sys.stderr)
        return 1
    print(reply.rstrip())
    return 0


if __name__ == "__main__":
    sys.exit(main())
