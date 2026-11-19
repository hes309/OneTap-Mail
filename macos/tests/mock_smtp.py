#!/usr/bin/env python3
"""A tiny local SMTP sink used only for automated testing.

It accepts plain SMTP, AUTH PLAIN, one message, and writes the raw
message to the path given as argv[1]. No TLS, no external network.
"""

from __future__ import annotations

import base64
import socket
import sys
from pathlib import Path

HOST = "127.0.0.1"
PORT = 2525


def send(conn: socket.socket, line: str) -> None:
    conn.sendall((line + "\r\n").encode())


def main() -> None:
    out_path = Path(sys.argv[1])
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(1)
    server.settimeout(20)
    print(f"READY {HOST}:{PORT}", flush=True)

    conn, _ = server.accept()
    conn.settimeout(20)
    reader = conn.makefile("rb")
    send(conn, "220 localhost ESMTP test")

    data_mode = False
    auth_plain_pending = False
    message_lines: list[bytes] = []

    while True:
        raw = reader.readline()
        if not raw:
            break
        if data_mode:
            if raw in (b".\r\n", b".\n"):
                data_mode = False
                out_path.write_bytes(b"".join(message_lines))
                send(conn, "250 2.0.0 queued")
                continue
            if raw.startswith(b".."):
                raw = raw[1:]
            message_lines.append(raw)
            continue

        line = raw.decode("utf-8", "replace").strip()
        upper = line.upper()

        if auth_plain_pending:
            try:
                decoded = base64.b64decode(line).decode("utf-8", "replace")
                fields = decoded.split("\x00")
                if len(fields) >= 2:
                    print(f"AUTH user={fields[-2]}", flush=True)
            except Exception:
                pass
            auth_plain_pending = False
            send(conn, "235 2.7.0 authentication successful")
            continue

        print("C:", line.split(" ")[0], flush=True)

        if upper.startswith("EHLO") or upper.startswith("HELO"):
            conn.sendall(
                b"250-localhost\r\n"
                b"250-AUTH PLAIN\r\n"
                b"250-8BITMIME\r\n"
                b"250 SIZE 26214400\r\n"
            )
        elif upper.startswith("AUTH PLAIN"):
            parts = line.split(" ", 2)
            if len(parts) == 3:
                try:
                    decoded = base64.b64decode(parts[2]).decode("utf-8", "replace")
                    fields = decoded.split("\x00")
                    if len(fields) >= 2:
                        print(f"AUTH user={fields[-2]}", flush=True)
                except Exception:
                    pass
                send(conn, "235 2.7.0 authentication successful")
            else:
                auth_plain_pending = True
                send(conn, "334 ")
        elif upper.startswith("MAIL FROM"):
            send(conn, "250 2.1.0 ok")
        elif upper.startswith("RCPT TO"):
            send(conn, "250 2.1.5 ok")
        elif upper == "DATA":
            data_mode = True
            send(conn, "354 end data with <CR><LF>.<CR><LF>")
        elif upper == "QUIT":
            send(conn, "221 2.0.0 bye")
            break
        elif upper == "RSET":
            send(conn, "250 ok")
        else:
            send(conn, "250 ok")

    conn.close()
    server.close()
    print(f"WROTE {out_path} {out_path.stat().st_size if out_path.exists() else 0}", flush=True)


if __name__ == "__main__":
    main()
