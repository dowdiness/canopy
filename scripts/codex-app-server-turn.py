#!/usr/bin/env python3
"""Drive one Codex app-server turn over the daemon's WebSocket control socket.

The Codex `app-server` exposes two transports with *different* framings:

  * stdio (`codex app-server`)            -> newline-delimited JSON-RPC
  * unix / daemon control socket          -> WebSocket (RFC6455), one
    JSON-RPC object per text frame

`codex app-server proxy` is a dumb byte relay (tokio::io::copy), NOT a
protocol adapter, so to talk to the control socket you must speak WebSocket
yourself. This script does that with a hand-rolled minimal client (no deps):
HTTP/1.1 upgrade + masked client frames.

Prerequisites (one-time, see memory reference_codex_app_server_driving):
  * A managed standalone install must exist at
    ~/.codex/packages/standalone/current/codex. The npm `@openai/codex`
    distribution does not create it; symlink the bundled native binary:
        mkdir -p ~/.codex/packages/standalone/current
        ln -sf <node_modules .../codex-linux-x64/.../codex/codex> \
               ~/.codex/packages/standalone/current/codex
  * Start the daemon:
        codex app-server daemon bootstrap
        codex app-server daemon start
    Verify: `codex app-server daemon version` -> {"status":"running",...}

Protocol per connection:
  initialize -> initialized (notification, REQUIRED) -> thread/start ->
  turn/start -> stream events until turn/completed.

Usage:
    python3 scripts/codex-app-server-turn.py "your prompt here"
    python3 scripts/codex-app-server-turn.py --sock /path/to/sock "prompt"

For routine Codex use prefer the `mcp__codex__codex` MCP wrapper; this script
exists for exercising / debugging the app-server control protocol itself.
"""

import argparse
import base64
import json
import os
import socket
import struct
import sys
import time

DEFAULT_SOCK = os.path.expanduser("~/.codex/app-server-control/app-server-control.sock")


def ws_handshake(s):
    key = base64.b64encode(os.urandom(16)).decode()
    req = (
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n"
    )
    s.sendall(req.encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        d = s.recv(1)
        if not d:
            raise RuntimeError("EOF during WS handshake; got: %r" % buf)
        buf += d
    status = buf.decode(errors="replace").split("\r\n", 1)[0]
    if "101" not in status:
        raise RuntimeError("WS handshake failed: " + status)
    return status


def send_text(s, obj):
    payload = json.dumps(obj).encode()
    mask = os.urandom(4)
    n = len(payload)
    fin_op = 0x81  # FIN + text frame
    if n < 126:
        header = struct.pack("!BB", fin_op, 0x80 | n)
    elif n < 65536:
        header = struct.pack("!BBH", fin_op, 0x80 | 126, n)
    else:
        header = struct.pack("!BBQ", fin_op, 0x80 | 127, n)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    s.sendall(header + mask + masked)


def _recv_exact(s, n):
    buf = b""
    while len(buf) < n:
        d = s.recv(n - len(buf))
        if not d:
            raise RuntimeError("EOF mid-frame")
        buf += d
    return buf


def recv_msg(s):
    """Return (kind, payload): ('text', str) | ('close', bytes). Handles
    fragmentation; answers pings; skips other control frames."""
    data = b""
    while True:
        b0, b1 = struct.unpack("!BB", _recv_exact(s, 2))
        fin = b0 & 0x80
        opcode = b0 & 0x0F
        masked = b1 & 0x80
        ln = b1 & 0x7F
        if ln == 126:
            ln = struct.unpack("!H", _recv_exact(s, 2))[0]
        elif ln == 127:
            ln = struct.unpack("!Q", _recv_exact(s, 8))[0]
        mask = _recv_exact(s, 4) if masked else None
        payload = _recv_exact(s, ln) if ln else b""
        if mask:
            payload = bytes(c ^ mask[i % 4] for i, c in enumerate(payload))
        if opcode == 0x8:  # close
            return ("close", payload)
        if opcode == 0x9:  # ping -> ignore (server tolerates no pong here)
            continue
        if opcode in (0x1, 0x0):  # text / continuation
            data += payload
            if fin:
                return ("text", data.decode(errors="replace"))


def main():
    ap = argparse.ArgumentParser(description="Drive one Codex app-server turn over the WS control socket.")
    ap.add_argument("prompt", help="user prompt text")
    ap.add_argument("--sock", default=DEFAULT_SOCK, help="control socket path")
    ap.add_argument("--timeout", type=float, default=120.0, help="overall turn timeout (s)")
    args = ap.parse_args()

    if not os.path.exists(args.sock):
        sys.exit(
            f"control socket not found: {args.sock}\n"
            "Is the daemon running? `codex app-server daemon version`"
        )

    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(args.sock)
    print("WS:", ws_handshake(s), file=sys.stderr)
    s.settimeout(args.timeout)

    next_id = [0]

    def rid():
        next_id[0] += 1
        return next_id[0]

    def wait_for_response(want_id):
        while True:
            kind, msg = recv_msg(s)
            if kind == "close":
                sys.exit("server closed connection: " + msg.decode(errors="replace"))
            obj = json.loads(msg)
            if obj.get("id") == want_id and ("result" in obj or "error" in obj):
                return obj

    # 1. initialize
    i_id = rid()
    send_text(s, {"jsonrpc": "2.0", "id": i_id, "method": "initialize",
                  "params": {"clientInfo": {"name": "canopy-codex-turn", "version": "0.1.0"}}})
    wait_for_response(i_id)

    # 2. initialized (REQUIRED notification, no id/params)
    send_text(s, {"jsonrpc": "2.0", "method": "initialized"})

    # 3. thread/start
    t_id = rid()
    send_text(s, {"jsonrpc": "2.0", "id": t_id, "method": "thread/start", "params": {}})
    r = wait_for_response(t_id)
    if "error" in r:
        sys.exit("thread/start error: " + json.dumps(r["error"]))
    thread = r["result"]["thread"]["id"]
    print("thread:", thread, file=sys.stderr)

    # 4. turn/start
    turn_id = rid()
    send_text(s, {"jsonrpc": "2.0", "id": turn_id, "method": "turn/start",
                  "params": {"threadId": thread, "input": [{"type": "text", "text": args.prompt}]}})
    r = wait_for_response(turn_id)
    if "error" in r:
        sys.exit("turn/start error: " + json.dumps(r["error"]))

    # 5. stream events until turn/completed
    deltas = []
    final_text = None
    start = time.time()
    while True:
        kind, msg = recv_msg(s)
        if kind == "close":
            print("server closed during stream", file=sys.stderr)
            break
        obj = json.loads(msg)
        m = obj.get("method")
        if m is None:
            continue
        # server->client approval requests (have id): deny by default
        if "id" in obj and ("requestApproval" in m or "approval" in m.lower()):
            print("approval request:", m, "-> denying", file=sys.stderr)
            send_text(s, {"jsonrpc": "2.0", "id": obj["id"], "result": {"decision": "denied"}})
            continue
        if m == "item/agentMessage/delta":
            deltas.append(obj["params"].get("delta", ""))
        elif m == "item/completed":
            item = obj.get("params", {}).get("item", {})
            if item.get("type") == "agentMessage":
                final_text = item.get("text")
        elif m == "turn/completed":
            status = obj["params"].get("turn", {}).get("status")
            print("turn/completed status=", status, file=sys.stderr)
            break
        if time.time() - start > args.timeout:
            print("timeout waiting for turn/completed", file=sys.stderr)
            break

    print(((final_text if final_text is not None else "".join(deltas)) or "").strip())
    s.close()


if __name__ == "__main__":
    main()
