#!/usr/bin/env python3
"""omcitest_rpc.py - the bridge client for `appletbuilder itest` (omcitest.sh).

One request per invocation, over the ActionUI remote bridge of an applet that omcitest.sh
launched for a test (OMC's OMCTestHost.h). The socket and the token come from the environment:

    OMCITEST_SOCKET      the bridge's socket path
    OMCITEST_TOKEN_FILE  a file holding the test's token (mode 0600, in the run's private folder)

Commands (results on stdout, problems on stderr):

    call <method> [params-json] [--raw]   any method; prints the result as JSON, or a string
                                          result as plain text with --raw
    run <commandID> [--text T] [--file PATH]... [--key-window]
                                          omc.test.runCommand; prints the run number
    value <window> <viewID> [--part N]    actionui.getValueString; prints the text
    set-value <window> <viewID> <text> [--part N]
                                          actionui.setValueString
    click <window> <viewID> [--part N] [--property P]
                                          actionui.performAction; prints the action id
    windows                               the window uuids, one per line
    run-record <run>                      that run's omc.test.log record, as JSON
    output <run>                          that run's output text
    wait-idle [--timeout S] [--settle S]  waits until omc.test.status is idle and its activity
                                          stays the same for the settle time (default 20, 0.2)
    wait-ready --pid PID [--timeout S]    waits for the bridge to answer actionui.hello, failing
                                          early when the applet process is gone (default 20)

Exit status: 0 done, 1 usage, 2 cannot connect, 3 the method answered an error (code and message
on stderr), 4 timed out, 5 the applet exited.
"""

import json
import os
import socket
import sys
import time

EXIT_USAGE = 1
EXIT_CONNECT = 2
EXIT_RPC_ERROR = 3
EXIT_TIMEOUT = 4
EXIT_GONE = 5


class RPCError(Exception):
    def __init__(self, code, message):
        super().__init__("%s: %s" % (code, message))
        self.code = code
        self.message = message


def read_token():
    path = os.environ.get("OMCITEST_TOKEN_FILE", "")
    if not path:
        raise SystemExit("omcitest_rpc: OMCITEST_TOKEN_FILE is not set")
    with open(path, "r", encoding="ascii") as handle:
        return handle.read().strip()


class Client:
    def __init__(self, path, token, timeout=30):
        self.token = token
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(timeout)
        self.sock.connect(path)
        self.stream = self.sock.makefile("rwb")
        self.next_id = 1

    def call(self, method, params=None):
        params = dict(params or {})
        params["token"] = self.token
        request = {"jsonrpc": "2.0", "id": self.next_id, "method": method, "params": params}
        self.next_id += 1
        self.stream.write((json.dumps(request) + "\n").encode("utf-8"))
        self.stream.flush()
        line = self.stream.readline()
        if not line:
            raise ConnectionError("the bridge closed the connection")
        try:
            reply = json.loads(line)
        except ValueError:
            raise ConnectionError("the bridge sent a reply that is not JSON: %r" % line[:200])
        if not isinstance(reply, dict):
            raise ConnectionError("the bridge sent a reply that is not a JSON object")
        if "error" in reply:
            error = reply["error"]
            raise RPCError(error.get("code"), error.get("message"))
        return reply.get("result")

    def close(self):
        try:
            self.stream.close()
            self.sock.close()
        except OSError:
            pass


def connect():
    path = os.environ.get("OMCITEST_SOCKET", "")
    if not path:
        raise SystemExit("omcitest_rpc: OMCITEST_SOCKET is not set")
    return Client(path, read_token())


def take_option(args, name, default=None, flag=False):
    """Remove `name` (and its value unless flag) from args; returns the value."""
    if name not in args:
        return default
    index = args.index(name)
    if flag:
        del args[index]
        return True
    if index + 1 >= len(args):
        raise SystemExit("omcitest_rpc: %s needs a value" % name)
    value = args[index + 1]
    del args[index:index + 2]
    return value


def take_all(args, name):
    values = []
    while name in args:
        values.append(take_option(args, name))
    return values


def as_int(text, what):
    try:
        return int(text)
    except ValueError:
        raise SystemExit("omcitest_rpc: %s must be an integer, not %r" % (what, text))


def wait_ready(args):
    pid = as_int(take_option(args, "--pid", "0"), "--pid")
    timeout = float(take_option(args, "--timeout", "20"))
    path = os.environ.get("OMCITEST_SOCKET", "")
    token = read_token()
    deadline = time.time() + timeout
    while time.time() < deadline:
        if pid > 0:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                print("omcitest_rpc: the applet exited before its bridge answered", file=sys.stderr)
                return EXIT_GONE
            except PermissionError:
                pass
        if os.path.exists(path):
            try:
                client = Client(path, token, timeout=5)
                client.call("actionui.hello")
                client.close()
                return 0
            except (OSError, ConnectionError, RPCError):
                pass
        time.sleep(0.05)
    print("omcitest_rpc: the bridge did not answer within %ss" % timeout, file=sys.stderr)
    return EXIT_TIMEOUT


def wait_idle(client, args):
    timeout = float(take_option(args, "--timeout", "20"))
    settle = float(take_option(args, "--settle", "0.2"))
    deadline = time.time() + timeout
    status = None
    while time.time() < deadline:
        first = client.call("omc.test.status")
        status = first
        if first.get("idle"):
            time.sleep(settle)
            second = client.call("omc.test.status")
            status = second
            if second.get("idle") and second.get("activity") == first.get("activity"):
                return 0
        else:
            time.sleep(0.05)
    print("omcitest_rpc: not idle within %ss: %s" % (timeout, json.dumps(status)), file=sys.stderr)
    return EXIT_TIMEOUT


def print_text(value):
    if value is None:
        value = ""
    if not isinstance(value, str):
        value = json.dumps(value)
    sys.stdout.write(value)
    sys.stdout.write("\n")


def run_record(client, run):
    runs = client.call("omc.test.log", {"run": run}).get("runs", [])
    if not runs:
        raise RPCError(-32602, "no such run: %s" % run)
    return runs[0]


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return EXIT_USAGE
    command, args = argv[0], list(argv[1:])

    if command == "wait-ready":
        return wait_ready(args)

    try:
        client = connect()
    except OSError as error:
        print("omcitest_rpc: cannot connect to the bridge: %s" % error, file=sys.stderr)
        return EXIT_CONNECT

    try:
        if command == "call":
            raw = take_option(args, "--raw", flag=True)
            if not args:
                raise SystemExit("omcitest_rpc: call needs a method")
            try:
                params = json.loads(args[1]) if len(args) > 1 and args[1] else {}
            except ValueError as error:
                raise SystemExit("omcitest_rpc: params are not JSON: %s" % error)
            if not isinstance(params, dict):
                raise SystemExit("omcitest_rpc: params must be a JSON object")
            result = client.call(args[0], params)
            if raw:
                print_text(result)
            else:
                print(json.dumps(result, sort_keys=True))
        elif command == "run":
            text = take_option(args, "--text")
            files = take_all(args, "--file")
            key_window = take_option(args, "--key-window", flag=True)
            if len(args) != 1:
                raise SystemExit("omcitest_rpc: run needs one command id")
            params = {"commandID": args[0]}
            if text is not None:
                params["text"] = text
            if files:
                params["files"] = files
            if key_window:
                params["keyWindow"] = True
            print(client.call("omc.test.runCommand", params)["run"])
        elif command == "value":
            part = take_option(args, "--part")
            if len(args) != 2:
                raise SystemExit("omcitest_rpc: value needs a window and a view id")
            params = {"window": args[0], "viewID": as_int(args[1], "viewID")}
            if part is not None:
                params["viewPartID"] = as_int(part, "--part")
            print_text(client.call("actionui.getValueString", params))
        elif command == "set-value":
            part = take_option(args, "--part")
            if len(args) != 3:
                raise SystemExit("omcitest_rpc: set-value needs a window, a view id and a value")
            params = {"window": args[0], "viewID": as_int(args[1], "viewID"), "value": args[2]}
            if part is not None:
                params["viewPartID"] = as_int(part, "--part")
            client.call("actionui.setValueString", params)
        elif command == "click":
            part = take_option(args, "--part")
            prop = take_option(args, "--property")
            if len(args) != 2:
                raise SystemExit("omcitest_rpc: click needs a window and a view id")
            params = {"window": args[0], "viewID": as_int(args[1], "viewID")}
            if part is not None:
                params["viewPartID"] = as_int(part, "--part")
            if prop is not None:
                params["property"] = prop
            print_text(client.call("actionui.performAction", params))
        elif command == "windows":
            for window in client.call("actionui.listWindows") or []:
                print(window)
        elif command == "run-record":
            if len(args) != 1:
                raise SystemExit("omcitest_rpc: run-record needs a run number")
            print(json.dumps(run_record(client, as_int(args[0], "run")), sort_keys=True))
        elif command == "output":
            if len(args) != 1:
                raise SystemExit("omcitest_rpc: output needs a run number")
            sys.stdout.write(run_record(client, as_int(args[0], "run")).get("output", ""))
        elif command == "wait-idle":
            return wait_idle(client, args)
        else:
            print("omcitest_rpc: unknown command %r" % command, file=sys.stderr)
            return EXIT_USAGE
    except RPCError as error:
        print("omcitest_rpc: %s failed with %s: %s" % (command, error.code, error.message), file=sys.stderr)
        return EXIT_RPC_ERROR
    except (OSError, ConnectionError) as error:
        print("omcitest_rpc: the bridge connection failed: %s" % error, file=sys.stderr)
        return EXIT_CONNECT
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
