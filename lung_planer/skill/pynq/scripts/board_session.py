"""One trusted SSH/SFTP session; hidden authentication and JSON-line operations.

Run with --host HOST --user USER [--known-hosts FILE] [--key FILE].
After authentication, send {"op":"run","command":"...","timeout":120},
{"op":"put","local":"...","remote":"..."}, {"op":"get",...},
{"op":"ping"}, or {"op":"close"}. Remote stdin is the optional "stdin" field.
Never put credentials in an operation. Paths must already have parent directories.
"""
import argparse
import getpass
import json
import sys
import time
import math
import threading
from pathlib import Path

import paramiko


def run_command(client, request):
    timeout = float(request.get("timeout", 120))
    if not math.isfinite(timeout) or timeout <= 0:
        raise ValueError("timeout must be positive")
    deadline = time.monotonic() + timeout
    channel = client.get_transport().open_session(timeout=min(15, timeout))
    output, error = bytearray(), bytearray()
    def check_deadline():
        if time.monotonic() >= deadline:
            raise TimeoutError("Remote command deadline exceeded; remote process may still exist")
    try:
        channel.settimeout(timeout)
        # Channel.settimeout does not bound the SSH exec-request acknowledgement.
        # Close the channel on deadline so the request waiter wakes too.
        acknowledged = threading.Event()
        failure = []
        def execute():
            try:
                channel.exec_command(request["command"])
            except Exception as exc:
                failure.append(exc)
            finally:
                acknowledged.set()
        threading.Thread(target=execute, daemon=True).start()
        if not acknowledged.wait(max(0, deadline - time.monotonic())):
            raise TimeoutError("SSH execution request deadline exceeded")
        if failure:
            raise failure[0]
        check_deadline()
        payload = request.get("stdin", "").encode("utf-8")
        if payload:
            channel.settimeout(max(0.01, deadline - time.monotonic()))
            channel.sendall(payload)
            check_deadline()
        channel.shutdown_write()
        while True:
            check_deadline()
            while channel.recv_ready():
                output.extend(channel.recv(65536))
                check_deadline()
            while channel.recv_stderr_ready():
                error.extend(channel.recv_stderr(65536))
                check_deadline()
            if channel.exit_status_ready() and not channel.recv_ready() and not channel.recv_stderr_ready():
                return {"exit_code": channel.recv_exit_status(),
                        "stdout": output.decode("utf-8", "replace"),
                        "stderr": error.decode("utf-8", "replace")}
            time.sleep(0.03)
    except TimeoutError as exc:
        return {"timed_out": True, "error": str(exc),
                "stdout": output.decode("utf-8", "replace"),
                "stderr": error.decode("utf-8", "replace")}
    finally:
        channel.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--port", type=int, default=22)
    parser.add_argument("--known-hosts", type=Path)
    parser.add_argument("--key", type=Path)
    parser.add_argument("--password", action="store_true", help="Use a hidden password prompt immediately")
    args = parser.parse_args()
    client = paramiko.SSHClient()
    client.load_system_host_keys()
    if args.known_hosts:
        client.load_host_keys(str(args.known_hosts))
    client.set_missing_host_key_policy(paramiko.RejectPolicy())
    connection = dict(hostname=args.host, port=args.port, username=args.user,
                      timeout=10, auth_timeout=15, banner_timeout=15)
    try:
        if not args.password:
            try:
                client.connect(**connection, key_filename=str(args.key) if args.key else None,
                               allow_agent=True, look_for_keys=True)
            except paramiko.AuthenticationException:
                args.password = True
            except paramiko.SSHException as exc:
                if str(exc) != "No authentication methods available":
                    raise
                args.password = True
        if args.password:
            password = getpass.getpass("Board SSH password: ")
            try:
                client.connect(**connection, password=password, allow_agent=False, look_for_keys=False)
            finally:
                password = None
    except BaseException:
        client.close()
        raise
    try:
        client.get_transport().set_keepalive(30)
        print(json.dumps({"ready": True, "host": args.host}), flush=True)
        with client.open_sftp() as sftp:
            for line in sys.stdin:
                request = None
                try:
                    request = json.loads(line)
                    operation = request["op"]
                    if operation == "close":
                        print(json.dumps({"closed": True}), flush=True)
                        break
                    if operation == "run":
                        result = run_command(client, request)
                    elif operation == "put":
                        sftp.put(request["local"], request["remote"])
                        result = {"uploaded": request["remote"], "bytes": sftp.stat(request["remote"]).st_size}
                    elif operation == "get":
                        sftp.get(request["remote"], request["local"])
                        result = {"downloaded": request["local"], "bytes": Path(request["local"]).stat().st_size}
                    elif operation == "ping":
                        result = {"connected": client.get_transport().is_active()}
                    else:
                        raise ValueError("Unknown operation")
                    print(json.dumps(result, ensure_ascii=False), flush=True)
                except Exception as exc:
                    # Do not echo request fields (remote stdin could be sensitive).
                    print(json.dumps({"error_type": type(exc).__name__, "error": str(exc)}, ensure_ascii=False), flush=True)
                finally:
                    request = None
    finally:
        client.close()


if __name__ == "__main__":
    main()
