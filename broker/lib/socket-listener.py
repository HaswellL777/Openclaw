#!/usr/bin/env python3
"""
socket-listener.py — Unix socket listener for openclaw-broker

Status: Phase 2 implementation slice 2 — repo-only, not deployed
This is NOT a deployed production service. Phase 2 live deployment has NOT started.

Provides:
  - Unix domain socket listener at BROKER_SOCKET_PATH
  - SO_PEERCRED peer authentication (uid=0 or uid=openclaw only)
  - Single-connection, single-request/response model
  - Delegates to broker --dispatch for actual request processing

Fail-closed: any error returns structured JSON error on socket, then closes.

Environment:
  BROKER_SOCKET_PATH    Socket path (default: /run/openclaw/broker.sock)
  BROKER_ALLOWED_UID    Override allowed service UID for testing (default: resolved from 'openclaw' user)
  BROKER_DISPATCH_CMD   Path to broker --dispatch command (default: sibling openclaw-broker)
  BROKER_DRY_RUN        Passed through to broker (default: true)
  BROKER_WRAPPER_DIR    Passed through to broker
  BROKER_LOG_FILE       Passed through to broker
"""

import grp
import json
import os
import pwd
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time

# --- Constants ---
MAX_REQUEST_SIZE = 1_048_576  # 1 MB
READ_TIMEOUT = 30  # seconds
LISTEN_BACKLOG = 1  # single connection

# --- Helpers ---

def log(msg):
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    print(f"[{ts}] [socket-listener] {msg}", file=sys.stderr, flush=True)


def error_json(message, status="error", error_code="", action="", request_id="", task_id=""):
    obj = {
        "ok": False,
        "action": action,
        "request_id": request_id,
        "task_id": task_id,
        "status": status,
        "message": message,
    }
    if error_code:
        obj["error_code"] = error_code
    return json.dumps(obj)


def resolve_allowed_uid():
    """Resolve the UID that is allowed to connect (besides root).

    Priority:
      1. BROKER_ALLOWED_UID env var (for testing)
      2. pwd lookup of 'openclaw' user
    Always returns an int. Exits on failure.
    """
    env_uid = os.environ.get("BROKER_ALLOWED_UID")
    if env_uid is not None:
        try:
            uid = int(env_uid)
            log(f"BROKER_ALLOWED_UID override: {uid}")
            return uid
        except ValueError:
            log(f"FATAL: BROKER_ALLOWED_UID is not a valid integer: {env_uid}")
            sys.exit(1)

    try:
        pw = pwd.getpwnam("openclaw")
        log(f"Resolved openclaw user UID: {pw.pw_uid}")
        return pw.pw_uid
    except KeyError:
        log("FATAL: 'openclaw' user not found and BROKER_ALLOWED_UID not set")
        sys.exit(1)


def get_peer_cred(conn):
    """Get peer credentials via SO_PEERCRED. Returns (pid, uid, gid)."""
    SO_PEERCRED = 17  # Linux-specific
    cred = conn.getsockopt(socket.SOL_SOCKET, SO_PEERCRED, struct.calcsize("III"))
    pid, uid, gid = struct.unpack("III", cred)
    return pid, uid, gid


def authenticate_peer(conn, allowed_uid):
    """Authenticate the connecting peer via SO_PEERCRED.

    Returns (pid, uid, gid) on success.
    Raises PermissionError on auth failure.
    """
    pid, uid, gid = get_peer_cred(conn)
    log(f"Peer credentials: pid={pid} uid={uid} gid={gid}")

    if uid == 0:
        log(f"AUTH OK: root (uid=0, pid={pid})")
        return pid, uid, gid
    elif uid == allowed_uid:
        log(f"AUTH OK: allowed uid={uid} (pid={pid})")
        return pid, uid, gid
    else:
        log(f"AUTH DENIED: uid={uid} pid={pid} (allowed: 0 or {allowed_uid})")
        raise PermissionError(f"Unauthorized peer uid={uid}. Allowed: root (0) or {allowed_uid}")


def read_request(conn):
    """Read a complete JSON request from the socket.

    Reads until the connection is half-closed (shutdown(WR) or close by client),
    up to MAX_REQUEST_SIZE bytes, with READ_TIMEOUT.
    Returns the raw bytes.
    """
    conn.settimeout(READ_TIMEOUT)
    chunks = []
    total = 0
    try:
        while True:
            chunk = conn.recv(65536)
            if not chunk:
                break
            total += len(chunk)
            if total > MAX_REQUEST_SIZE:
                raise ValueError(f"Request exceeds {MAX_REQUEST_SIZE} byte limit")
            chunks.append(chunk)
    except socket.timeout:
        raise TimeoutError(f"Read timeout after {READ_TIMEOUT}s")
    return b"".join(chunks)


def dispatch_request(request_bytes, broker_cmd):
    """Write request to temp file, call broker --dispatch, return result."""
    with tempfile.NamedTemporaryFile(
        mode="wb", prefix="broker-req-", suffix=".json", delete=False
    ) as f:
        f.write(request_bytes)
        tmp_path = f.name

    try:
        env = os.environ.copy()
        result = subprocess.run(
            [broker_cmd, "--dispatch", tmp_path],
            capture_output=True,
            timeout=60,
            env=env,
        )
        # Broker outputs result JSON on stdout (success or structured error)
        stdout = result.stdout.decode("utf-8", errors="replace").strip()
        stderr = result.stderr.decode("utf-8", errors="replace").strip()

        if stderr:
            for line in stderr.split("\n"):
                log(f"BROKER_STDERR: {line}")

        if stdout:
            # Validate it's JSON before returning
            try:
                json.loads(stdout)
                return stdout
            except json.JSONDecodeError:
                return error_json(
                    "Broker returned non-JSON output",
                    error_code="E_BROKER_INTERNAL",
                )
        else:
            return error_json(
                f"Broker exited {result.returncode} with no stdout",
                error_code="E_BROKER_INTERNAL",
            )
    except subprocess.TimeoutExpired:
        return error_json(
            "Broker dispatch timed out after 60s",
            error_code="E_BROKER_TIMEOUT",
        )
    except FileNotFoundError:
        return error_json(
            f"Broker command not found: {broker_cmd}",
            error_code="E_BROKER_NOT_FOUND",
        )
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def handle_connection(conn, addr, allowed_uid, broker_cmd):
    """Handle a single client connection. Always sends a response and closes."""
    try:
        # Step 1: Authenticate peer
        try:
            authenticate_peer(conn, allowed_uid)
        except PermissionError as e:
            resp = error_json(str(e), status="denied", error_code="E_AUTH_DENIED")
            conn.sendall(resp.encode("utf-8"))
            # Graceful shutdown: signal write-end closed, drain pending client data
            try:
                conn.shutdown(socket.SHUT_WR)
                while conn.recv(4096):
                    pass
            except Exception:
                pass
            return
        except OSError as e:
            resp = error_json(f"SO_PEERCRED failed: {e}", error_code="E_AUTH_FAILED")
            conn.sendall(resp.encode("utf-8"))
            try:
                conn.shutdown(socket.SHUT_WR)
                while conn.recv(4096):
                    pass
            except Exception:
                pass
            return

        # Step 2: Read request
        try:
            request_bytes = read_request(conn)
        except TimeoutError as e:
            resp = error_json(str(e), error_code="E_READ_TIMEOUT")
            conn.sendall(resp.encode("utf-8"))
            return
        except ValueError as e:
            resp = error_json(str(e), error_code="E_REQUEST_TOO_LARGE")
            conn.sendall(resp.encode("utf-8"))
            return

        if not request_bytes.strip():
            resp = error_json("Empty request", error_code="E_INVALID_JSON")
            conn.sendall(resp.encode("utf-8"))
            return

        # Step 3: Validate JSON parse (early check before dispatch)
        try:
            json.loads(request_bytes)
        except json.JSONDecodeError as e:
            resp = error_json(f"Invalid JSON: {e}", error_code="E_INVALID_JSON")
            conn.sendall(resp.encode("utf-8"))
            return

        # Step 4: Dispatch to broker
        log(f"Dispatching request ({len(request_bytes)} bytes)")
        result = dispatch_request(request_bytes, broker_cmd)

        # Step 5: Send response
        conn.sendall(result.encode("utf-8"))

    except BrokenPipeError:
        log("Client disconnected before response could be sent")
    except Exception as e:
        log(f"Unexpected error handling connection: {e}")
        try:
            resp = error_json(f"Internal error: {e}", error_code="E_INTERNAL")
            conn.sendall(resp.encode("utf-8"))
        except Exception:
            pass
    finally:
        try:
            conn.close()
        except Exception:
            pass


def run_listener(socket_path, allowed_uid, broker_cmd):
    """Main listener loop. Binds socket, accepts connections sequentially."""

    # Clean up stale socket file
    if os.path.exists(socket_path):
        try:
            os.unlink(socket_path)
        except OSError as e:
            log(f"FATAL: Cannot remove stale socket {socket_path}: {e}")
            sys.exit(1)

    # Ensure parent directory exists
    parent = os.path.dirname(socket_path)
    if parent and not os.path.isdir(parent):
        log(f"FATAL: Socket parent directory does not exist: {parent}")
        sys.exit(1)

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)

    # Handle SIGTERM gracefully
    shutdown_flag = [False]

    def handle_signal(signum, frame):
        log(f"Received signal {signum}, shutting down")
        shutdown_flag[0] = True
        try:
            sock.close()
        except Exception:
            pass

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    try:
        sock.bind(socket_path)
        # Set socket permissions: owner rw, group rw, other none (0660)
        os.chmod(socket_path, 0o660)
        # Set socket group to openclaw so the openclaw user can connect.
        # Mandatory when running as root (production); skipped in dev/test.
        if os.geteuid() == 0:
            try:
                openclaw_gid = grp.getgrnam("openclaw").gr_gid
            except KeyError:
                log("FATAL: 'openclaw' group not found — cannot chown broker socket")
                sys.exit(1)
            try:
                os.chown(socket_path, 0, openclaw_gid)
            except OSError as e:
                log(f"FATAL: Cannot chown socket to root:openclaw — {e}")
                sys.exit(1)
            log(f"Socket ownership set to root:openclaw (gid={openclaw_gid})")
        else:
            log(f"WARNING: Running as non-root (euid={os.geteuid()}), skipping socket chown — not suitable for production")
        sock.listen(LISTEN_BACKLOG)
        sock.settimeout(1.0)  # Allow periodic shutdown check
        log(f"Listening on {socket_path}")

        while not shutdown_flag[0]:
            try:
                conn, addr = sock.accept()
                log("Accepted connection")
                handle_connection(conn, addr, allowed_uid, broker_cmd)
            except socket.timeout:
                continue
            except OSError:
                if shutdown_flag[0]:
                    break
                raise

    except OSError as e:
        log(f"FATAL: Socket error: {e}")
        sys.exit(1)
    finally:
        try:
            sock.close()
        except Exception:
            pass
        try:
            os.unlink(socket_path)
        except OSError:
            pass
        log("Listener stopped")


def main():
    socket_path = os.environ.get("BROKER_SOCKET_PATH", "/run/openclaw/broker.sock")
    allowed_uid = resolve_allowed_uid()

    # Resolve broker command path
    script_dir = os.path.dirname(os.path.abspath(__file__))
    default_broker = os.path.join(script_dir, "..", "openclaw-broker")
    broker_cmd = os.environ.get("BROKER_DISPATCH_CMD", default_broker)

    if not os.path.isfile(broker_cmd):
        log(f"FATAL: Broker command not found: {broker_cmd}")
        sys.exit(1)

    log(f"Socket path: {socket_path}")
    log(f"Broker command: {broker_cmd}")
    log(f"Allowed UID: {allowed_uid} (+ root)")
    log(f"Dry-run: {os.environ.get('BROKER_DRY_RUN', 'true')}")

    run_listener(socket_path, allowed_uid, broker_cmd)


if __name__ == "__main__":
    main()
