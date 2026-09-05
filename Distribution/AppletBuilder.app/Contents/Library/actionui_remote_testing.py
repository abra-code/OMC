"""actionui_remote_testing - a fake ActionUI remote host for test suites.

Serves ActionUI Remote Protocol version 1 on a Unix domain socket from an in-memory model, so a
script that uses actionui_remote (or the OMC `omc` module) can be exercised without an ActionUI
host. Every request is appended to a JSON Lines log, and the model can be dumped to a JSON file,
so a harness can assert what a script did and what the window would look like afterwards.

Command line:

    python3 -m actionui_remote_testing --socket PATH [--log PATH.jsonl] [--state PATH.json]
                                       [--window UUID ...] [--element WINDOW:ID:TYPE ...]

    The process serves until it receives SIGTERM or SIGINT, then writes the state file (if
    requested) and exits 0. `--window` pre-creates windows; `--element` pre-creates elements in
    them so unknown-view checks behave like the real host.

In-process:

    fake = FakeServer(socket_path, log_path=None)
    fake.add_window("W", {2: "TextField", 5: "Table"})
    fake.serve_in_thread()
    ...
    fake.stop()
    fake.requests      # list of decoded request dicts, in arrival order
    fake.model         # {window: {"elements": {id: type}, "values": {...}, ...}}

Behavior of the fake, by design:

- Every `actionui.*` method of PROTOCOL.md is implemented over the in-memory model with the
  same param validation and error codes as the real host (1001, 1002, -32602, -32601, 1003 for
  a state type change). Values are stored and returned as given.
- Any other namespaced method (`omc.*`, `app.*`) is accepted, logged, and answered `true`,
  unless a handler was registered for it with `fake.register(name, callable)`.
- Insert assigns the element's own `id` when it has one, otherwise the next free negative id.
- Not modeled, on purpose: rendering. `contentSizeLimits` is always null, `getValueString` is
  a plain stringification, `getColumnCount` counts stored rows only (the host also reads the
  `columns` property), and `removeElement` will remove a root the host refuses with 1003.
"""

import argparse
import json
import os
import signal
import socket
import socketserver
import sys
import threading

__all__ = ["FakeServer", "main"]

PROTOCOL_VERSION = 1

PARSE_ERROR = -32700
INVALID_REQUEST = -32600
METHOD_NOT_FOUND = -32601
INVALID_PARAMS = -32602
UNAUTHENTICATED = 1006
INTERNAL_ERROR = -32603
UNKNOWN_WINDOW = 1001
UNKNOWN_VIEW = 1002
ENGINE_FAILURE = 1003
HOST_REFUSED = 1004

MAX_BATCH_ENTRIES = 4096


class Failure(Exception):
    def __init__(self, code, message, data=None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.data = data


def _new_window():
    return {"elements": {}, "values": {}, "strings": {}, "properties": {}, "states": {},
            "rows": {}, "selection": {}, "modal": None, "dialog": None, "toast": None,
            "next_negative_id": -1}


class FakeServer:
    """See the module docstring."""

    def __init__(self, socket_path, log_path=None, host_name="FakeHost", host_version="0",
                 tokens=None):
        self.socket_path = socket_path
        self.log_path = log_path
        self.host_name = host_name
        self.host_version = host_version
        self.model = {}
        # Tokens this host accepts. Empty means it requires none, which is the default and what
        # every existing test expects.
        self.tokens = set(tokens or ())
        self.requests = []
        self._handlers = {}
        self._lock = threading.RLock()
        self._server = None
        self._thread = None
        self._log_file = None
        self._opened = False
        self._connections = set()

    # -- setup

    def add_window(self, uuid, elements=None):
        with self._lock:
            window = self.model.setdefault(uuid, _new_window())
            for view_id, element_type in (elements or {}).items():
                window["elements"][int(view_id)] = element_type
        return uuid

    def register(self, method, handler):
        """handler(params) -> result; raise Failure(code, message) to answer an error."""
        with self._lock:
            self._handlers[method] = handler

    # -- lifecycle

    def serve_in_thread(self):
        self._open()
        self._thread = threading.Thread(target=self._server.serve_forever, kwargs={"poll_interval": 0.1}, daemon=True)
        self._thread.start()
        return self

    def serve_forever(self):
        self._open()
        try:
            self._server.serve_forever(poll_interval=0.1)
        finally:
            self._close()

    def stop(self):
        server = self._server
        if server is not None:
            server.shutdown()
            if self._thread is not None:
                self._thread.join(timeout=5)
                self._thread = None
        # Close accepted connections too, or their daemon threads keep serving the old model
        # and a fake restarted on the same path is shadowed by this one.
        with self._lock:
            open_connections = list(self._connections)
            self._connections.clear()
        for connection in open_connections:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                connection.close()
            except OSError:
                pass
        self._close()

    def _open(self):
        try:
            os.unlink(self.socket_path)
        except FileNotFoundError:
            pass
        fake = self

        class Handler(socketserver.StreamRequestHandler):
            def setup(self):
                super().setup()
                with fake._lock:
                    fake._connections.add(self.connection)

            def finish(self):
                with fake._lock:
                    fake._connections.discard(self.connection)
                super().finish()

            def handle(self):
                while True:
                    line = self.rfile.readline()
                    if not line:
                        return
                    reply = fake.handle_line(line.rstrip(b"\r\n"))
                    if reply is not None:
                        self.wfile.write(reply + b"\n")
                        self.wfile.flush()

        class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
            daemon_threads = True
            allow_reuse_address = True

        self._server = Server(self.socket_path, Handler)
        self._opened = True
        os.chmod(self.socket_path, 0o600)
        if self.log_path:
            self._log_file = open(self.log_path, "a", encoding="utf-8")

    def _close(self):
        if self._server is not None:
            self._server.server_close()
            self._server = None
        if self._log_file is not None:
            self._log_file.close()
            self._log_file = None
        if self._opened:
            self._opened = False
            try:
                os.unlink(self.socket_path)
            except FileNotFoundError:
                pass

    def dump_state(self, path):
        with self._lock:
            snapshot = {uuid: {key: (_stringify_keys(value) if isinstance(value, dict) else value)
                               for key, value in window.items()}
                        for uuid, window in self.model.items()}
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(snapshot, handle, indent=2, sort_keys=True)

    # -- JSON-RPC

    def handle_line(self, line):
        """Decode one line and return the reply bytes, or None when nothing is to be sent."""
        try:
            value = json.loads(line.decode("utf-8"))
        except (UnicodeDecodeError, ValueError) as error:
            return _encode_error(None, PARSE_ERROR, "Parse error: %s" % error)
        if isinstance(value, dict):
            with self._lock:   # encode under the lock too: getters return live model objects
                reply = self._handle_object(value)
                return _encode(reply) if reply is not None else None
        if isinstance(value, list):
            if not value:
                return _encode_error(None, INVALID_REQUEST, "Invalid request: empty batch")
            if len(value) > MAX_BATCH_ENTRIES:
                return _encode_error(None, INVALID_REQUEST, "Invalid request: batch of %d entries exceeds the limit of %d" % (len(value), MAX_BATCH_ENTRIES))
            replies = []
            with self._lock:   # one "main-thread turn"
                for entry in value:
                    if not isinstance(entry, dict):
                        replies.append(_error_object(None, INVALID_REQUEST, "Invalid request: batch entry is not an object"))
                        continue
                    reply = self._handle_object(entry)
                    if reply is not None:
                        replies.append(reply)
                return _encode(replies) if replies else None
        return _encode_error(None, INVALID_REQUEST, "Invalid request: expected an object or an array")

    def _handle_object(self, request):
        request_id = request.get("id")
        if request_id is None:
            is_notification = True
        else:
            is_notification = False
            if isinstance(request_id, bool) or not isinstance(request_id, (int, float, str)):
                return _error_object(None, INVALID_REQUEST, 'Invalid request: "id" must be a string or a number')
        if request.get("jsonrpc") != "2.0":
            return _error_object(request_id, INVALID_REQUEST, 'Invalid request: "jsonrpc" must be "2.0"')
        method = request.get("method")
        if not isinstance(method, str) or not method:
            return _error_object(request_id, INVALID_REQUEST, 'Invalid request: "method" must be a non-empty string')
        params = request.get("params")
        if params is None:
            params = {}
        elif not isinstance(params, dict):
            if is_notification:
                return None
            return _error_object(request_id, INVALID_PARAMS, 'Invalid params: "params" must be an object with named keys')

        with self._lock:
            # Redact before recording, both in memory and on disk. A token is a credential; a
            # test log is read, copied into bug reports and kept in a scratch directory, and
            # nothing downstream needs its value - bridge_called filters on the other params.
            logged = params
            if isinstance(params, dict) and "token" in params:
                logged = dict(params)
                logged["token"] = "<redacted>"
            self.requests.append({"method": method, "params": logged, "id": request_id})
            if self._log_file is not None:
                self._log_file.write(json.dumps({"method": method, "params": logged, "id": request_id}, sort_keys=True) + "\n")
                self._log_file.flush()
            if self.tokens and params.get("token") not in self.tokens:
                if is_notification:
                    return None
                return _error_object(request_id, UNAUTHENTICATED,
                                     "This host requires a token. Pass it as the \"token\" "
                                     "parameter; processes the host spawned receive it in "
                                     "ACTIONUI_REMOTE_TOKEN, or on the descriptor named by "
                                     "ACTIONUI_REMOTE_TOKEN_FD.")
            try:
                result = self._dispatch(method, params)
            except Failure as failure:
                if is_notification:
                    return None
                return _error_object(request_id, failure.code, failure.message, failure.data)
            except Exception as error:   # a registered handler misbehaved
                if is_notification:
                    return None
                return _error_object(request_id, HOST_REFUSED, str(error))
        if is_notification:
            return None
        return {"jsonrpc": "2.0", "id": request_id, "result": result}

    # -- dispatch

    def _dispatch(self, method, params):
        handler = self._handlers.get(method)
        if handler is not None:
            return handler(params)
        builtin = getattr(self, "_m_" + method.replace(".", "_"), None) if method.startswith("actionui.") else None
        if builtin is not None:
            return builtin(Params(self, params))
        if "." in method and not method.startswith("actionui."):
            return True   # a host extension method the fake does not model
        raise Failure(METHOD_NOT_FOUND, "Method not found: %s" % method)

    # -- actionui.* methods

    def _methods(self):
        names = [name[3:].replace("_", ".", 1) for name in dir(self) if name.startswith("_m_actionui_")]
        return sorted(set(names + list(self._handlers)))

    def _m_actionui_hello(self, p):
        return {"protocolVersion": PROTOCOL_VERSION, "host": {"name": self.host_name, "version": self.host_version},
                "methods": self._methods(), "windows": sorted(self.model)}

    def _m_actionui_listWindows(self, p):
        return sorted(self.model)

    def _m_actionui_getElementInfo(self, p):
        window = p.window()
        return {str(i): t for i, t in window["elements"].items() if i > 0}

    def _m_actionui_getValue(self, p):
        window, view_id = p.window_and_view()
        value = window["values"].get(view_id)
        part = p.optional_int("viewPartID") or 0
        if part and isinstance(value, list):
            return value[part - 1] if 0 < part <= len(value) else None
        return value

    def _m_actionui_setValue(self, p):
        window, view_id = p.window_and_view()
        window["values"][view_id] = p.required("value")
        return True

    def _m_actionui_getValueString(self, p):
        window, view_id = p.window_and_view()
        if view_id in window["strings"]:
            return window["strings"][view_id]
        value = self._m_actionui_getValue(p)
        if value is None:
            return None
        if isinstance(value, bool):
            return "true" if value else "false"
        if isinstance(value, (int, float, str)):
            return str(value)
        return json.dumps(value)

    def _m_actionui_setValueString(self, p):
        window, view_id = p.window_and_view()
        text = p.string("value")
        window["strings"][view_id] = text
        window["values"][view_id] = text
        return True

    def _m_actionui_getProperty(self, p):
        window, view_id = p.window_and_view()
        return window["properties"].get(view_id, {}).get(p.string("name"))

    def _m_actionui_setProperty(self, p):
        window, view_id = p.window_and_view()
        window["properties"].setdefault(view_id, {})[p.string("name")] = p.required("value")
        return True

    def _m_actionui_getState(self, p):
        window, view_id = p.window_and_view()
        return window["states"].get(view_id, {}).get(p.string("key"))

    def _m_actionui_getStateString(self, p):
        value = self._m_actionui_getState(p)
        if value is None:
            return None
        if isinstance(value, bool):
            return "true" if value else "false"
        return str(value) if isinstance(value, (int, float, str)) else json.dumps(value)

    def _m_actionui_setState(self, p):
        window, view_id = p.window_and_view()
        key = p.string("key")
        value = p.required("value")
        states = window["states"].setdefault(view_id, {})
        if key in states:
            # Coerce toward the stored type as the real host does: a whole number into a Double
            # state, an integral float into an Int state. Bools stay bools.
            existing = states[key]
            if isinstance(existing, float) and isinstance(value, int) and not isinstance(value, bool):
                value = float(value)
            elif isinstance(existing, int) and not isinstance(existing, bool) and isinstance(value, float) and value.is_integer():
                value = int(value)
        if key in states and _state_kind(states[key]) != _state_kind(value):
            raise Failure(ENGINE_FAILURE, "Type mismatch for state key '%s' on viewID: %d; expected %s, got %s"
                          % (key, view_id, _state_kind(states[key]), _state_kind(value)))
        states[key] = value
        return True

    def _m_actionui_setStateString(self, p):
        window, view_id = p.window_and_view()
        key = p.string("key")
        text = p.string("value")
        states = window["states"].setdefault(view_id, {})
        existing = states.get(key)
        if isinstance(existing, bool):
            states[key] = text.lower() in ("true", "1", "yes")
        elif isinstance(existing, int):
            try:
                states[key] = int(text)
            except ValueError:
                pass
        elif isinstance(existing, float):
            try:
                states[key] = float(text)
            except ValueError:
                pass
        else:
            states[key] = text
        return True

    def _m_actionui_getColumnCount(self, p):
        window, view_id = p.window_and_view()
        rows = window["rows"].get(view_id)
        return max((len(r) for r in rows), default=0) if rows else 0

    def _m_actionui_getRows(self, p):
        window, view_id = p.window_and_view()
        rows = window["rows"].get(view_id)
        return None if rows is None else [list(row) for row in rows]

    def _m_actionui_setRows(self, p):
        window, view_id = p.window_and_view()
        window["rows"][view_id] = p.rows("rows")
        window["selection"].pop(view_id, None)
        return True

    def _m_actionui_appendRows(self, p):
        window, view_id = p.window_and_view()
        window["rows"].setdefault(view_id, []).extend(p.rows("rows"))
        return True

    def _m_actionui_clearRows(self, p):
        window, view_id = p.window_and_view()
        window["rows"][view_id] = []
        window["selection"].pop(view_id, None)
        window["values"].pop(view_id, None)
        return True

    def _m_actionui_selectRow(self, p):
        window, view_id = p.window_and_view()
        index = p.int("index")
        rows = window["rows"].get(view_id) or []
        if 0 <= index < len(rows):
            window["selection"][view_id] = index
            window["values"][view_id] = rows[index]
            return rows[index]
        window["selection"].pop(view_id, None)
        window["values"].pop(view_id, None)
        return None

    def _m_actionui_selectRowWithContent(self, p):
        window, view_id = p.window_and_view()
        text = p.string("text")
        column = p.optional_int("column")
        rows = window["rows"].get(view_id) or []
        for index, row in enumerate(rows):
            cells = row if column is None else (row[column:column + 1] if 0 <= column < len(row) else [])
            if text in cells:
                window["selection"][view_id] = index
                window["values"][view_id] = row
                return index
        return -1

    def _m_actionui_clearSelection(self, p):
        window, view_id = p.window_and_view()
        window["selection"].pop(view_id, None)
        window["values"].pop(view_id, None)
        return True

    def _m_actionui_insertElement(self, p):
        window = p.window()
        parent_id = p.int("parentID")
        element = p.object("element")
        p.position()
        if parent_id not in window["elements"]:
            raise Failure(ENGINE_FAILURE, "parentNotFound(parentID: %d)" % parent_id)
        return self._insert(window, element)

    def _m_actionui_insertRow(self, p):
        window = p.window()
        parent_id = p.int("parentID")
        cells = p.objects("cells")
        p.position()
        if parent_id not in window["elements"]:
            raise Failure(ENGINE_FAILURE, "parentNotFound(parentID: %d)" % parent_id)
        return [self._insert(window, cell) for cell in cells]

    def _insert(self, window, element):
        view_id = element.get("id")
        if not isinstance(view_id, int) or isinstance(view_id, bool):
            view_id = window["next_negative_id"]
            window["next_negative_id"] -= 1
        window["elements"][view_id] = element.get("type", "Unknown")
        return view_id

    def _m_actionui_removeElement(self, p):
        window, view_id = p.window_and_view()
        for bucket in ("elements", "values", "strings", "properties", "states", "rows", "selection"):
            window[bucket].pop(view_id, None)
        return True

    def _m_actionui_presentModal(self, p):
        window = p.window()
        element = p.raw.get("element")
        if element is not None and not isinstance(element, dict):
            raise Failure(INVALID_PARAMS, '"element" must be a JSON object describing the modal\'s root element')
        p.optional_string("json")
        p.optional_string("path")
        p.optional_string("format")
        if element is None and p.raw.get("json") is None and p.raw.get("path") is None:
            raise Failure(INVALID_PARAMS, 'presentModal needs one of "element" (object), "json" (string), or "path" (string)')
        style = p.optional_string("style")
        if style not in (None, "sheet", "fullScreenCover"):
            raise Failure(INVALID_PARAMS, 'Unknown modal style "%s" (expected sheet or fullScreenCover)' % style)
        window["modal"] = {"style": style or "sheet", "onDismissActionID": p.optional_string("onDismissActionID"),
                           "source": {k: p.raw[k] for k in ("element", "json", "path") if p.raw.get(k) is not None}}
        return True

    def _m_actionui_dismissModal(self, p):
        p.window()["modal"] = None
        return True

    def _m_actionui_presentAlert(self, p):
        window = p.window()
        window["dialog"] = {"style": "alert", "title": p.string("title"), "message": p.optional_string("message"),
                            "buttons": p.buttons("buttons") or [{"title": "OK", "role": "cancel"}]}
        return True

    def _m_actionui_presentConfirmationDialog(self, p):
        window = p.window()
        buttons = p.buttons("buttons")
        if not buttons:
            raise Failure(INVALID_PARAMS, '"buttons" is required: a non-empty array of {title, role?, actionID?}')
        window["dialog"] = {"style": "confirmationDialog", "title": p.string("title"),
                            "message": p.optional_string("message"), "buttons": buttons}
        return True

    def _m_actionui_dismissDialog(self, p):
        p.window()["dialog"] = None
        return True

    def _m_actionui_presentToast(self, p):
        window = p.window()
        window["toast"] = {"message": p.string("message"), "duration": p.optional_number("duration") or 4.0,
                           "actionTitle": p.optional_string("actionTitle"), "actionID": p.optional_string("actionID")}
        return True

    def _m_actionui_dismissToast(self, p):
        p.window()["toast"] = None
        return True

    def _m_actionui_contentSizeLimits(self, p):
        p.window()
        return None


def _state_kind(value):
    if isinstance(value, bool):
        return "Bool"
    if isinstance(value, int):
        return "Int"
    if isinstance(value, float):
        return "Double"
    if isinstance(value, str):
        return "String"
    return type(value).__name__


class Params:
    """The fake's mirror of the host's typed param access, with the same error codes."""

    def __init__(self, fake, raw):
        self.fake = fake
        self.raw = raw

    def window(self):
        uuid = self.string("window")
        window = self.fake.model.get(uuid)
        if window is None:
            raise Failure(UNKNOWN_WINDOW, "Unknown window: %s" % uuid)
        return window

    def window_and_view(self):
        window = self.window()
        view_id = self.int("viewID")
        if view_id not in window["elements"]:
            raise Failure(UNKNOWN_VIEW, "Unknown view %d in window %s" % (view_id, self.raw.get("window")))
        return window, view_id

    def required(self, key):
        value = self.raw.get(key)
        if value is None:
            raise Failure(INVALID_PARAMS, 'Missing required param "%s"' % key)
        return value

    def optional_string(self, key):
        value = self.raw.get(key)
        if value is None:
            return None
        if not isinstance(value, str):
            raise Failure(INVALID_PARAMS, 'Param "%s" must be a string' % key)
        return value

    def string(self, key):
        value = self.optional_string(key)
        if value is None:
            raise Failure(INVALID_PARAMS, 'Missing required string param "%s"' % key)
        return value

    def optional_int(self, key):
        value = self.raw.get(key)
        if value is None:
            return None
        if isinstance(value, bool) or not isinstance(value, (int, float)) or int(value) != value:
            raise Failure(INVALID_PARAMS, 'Param "%s" must be an integer' % key)
        return int(value)

    def int(self, key):
        value = self.optional_int(key)
        if value is None:
            raise Failure(INVALID_PARAMS, 'Missing required integer param "%s"' % key)
        return value

    def optional_number(self, key):
        value = self.raw.get(key)
        if value is None:
            return None
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise Failure(INVALID_PARAMS, 'Param "%s" must be a number' % key)
        return value

    def object(self, key):
        value = self.raw.get(key)
        if not isinstance(value, dict):
            raise Failure(INVALID_PARAMS, 'Param "%s" must be an object' % key)
        return value

    def objects(self, key):
        value = self.raw.get(key)
        if not isinstance(value, list) or not all(isinstance(item, dict) for item in value):
            raise Failure(INVALID_PARAMS, 'Param "%s" must be an array of objects' % key)
        return value

    def rows(self, key):
        value = self.raw.get(key)
        if not isinstance(value, list) or not all(isinstance(row, list) for row in value):
            raise Failure(INVALID_PARAMS, 'Param "%s" must be an array of rows (arrays of strings)' % key)
        for row in value:
            if not all(isinstance(cell, str) for cell in row):
                raise Failure(INVALID_PARAMS, 'Param "%s": every cell must be a string' % key)
        return [list(row) for row in value]

    def position(self):
        value = self.raw.get("position")
        if value is None or value in ("append", "prepend"):
            return value
        if not isinstance(value, dict) or value.get("kind") not in ("append", "prepend", "at", "before", "after"):
            raise Failure(INVALID_PARAMS, "Insert position must be an object with a valid \"kind\" or a string")
        kind = value["kind"]
        needs = {"at": "index", "before": "siblingID", "after": "siblingID"}.get(kind)
        if needs is not None:
            n = value.get(needs)
            if isinstance(n, bool) or not isinstance(n, (int, float)) or int(n) != n:
                raise Failure(INVALID_PARAMS, 'Insert position "%s" requires an integer "%s"' % (kind, needs))
        return value

    def buttons(self, key):
        value = self.raw.get(key)
        if value is None:
            return None
        if isinstance(value, list):
            # As the host's ActionUIJSON.dialogButtons: entries without a string title are skipped.
            usable = [b for b in value if isinstance(b, dict) and isinstance(b.get("title"), str)]
        else:
            usable = []
        if not usable:
            raise Failure(INVALID_PARAMS, 'Param "%s" must be a non-empty array of {title, role?, actionID?}' % key)
        return usable


def _stringify_keys(mapping):
    return {str(key): value for key, value in mapping.items()}


def _error_object(request_id, code, message, data=None):
    error = {"code": code, "message": message}
    if data is not None:
        error["data"] = data
    return {"jsonrpc": "2.0", "id": request_id, "error": error}


def _encode(value):
    return json.dumps(value, separators=(",", ":")).encode("utf-8")


def _encode_error(request_id, code, message):
    return _encode(_error_object(request_id, code, message))


def main(argv=None):
    parser = argparse.ArgumentParser(description="Fake ActionUI remote host for tests.")
    parser.add_argument("--socket", required=True, help="Unix socket path to serve on")
    parser.add_argument("--log", help="append every request as one JSON line here")
    parser.add_argument("--state", help="write the model here on exit")
    parser.add_argument("--window", action="append", default=[], help="pre-create a window (repeatable)")
    parser.add_argument("--element", action="append", default=[], help="WINDOW:ID:TYPE, pre-create an element (repeatable)")
    parser.add_argument("--host-name", default="FakeHost")
    parser.add_argument("--host-version", default="0")
    parser.add_argument("--token", action="append", default=[],
                        help="require this token (repeatable); omit to require none")
    args = parser.parse_args(argv)

    fake = FakeServer(args.socket, log_path=args.log, host_name=args.host_name,
                      host_version=args.host_version, tokens=args.token)
    for uuid in args.window:
        fake.add_window(uuid)
    for spec in args.element:
        parts = spec.split(":", 2)
        if len(parts) != 3 or not parts[1].lstrip("-").isdigit():
            parser.error("--element expects WINDOW:ID:TYPE with an integer ID, got %r" % spec)
        fake.add_window(parts[0], {int(parts[1]): parts[2]})

    def on_signal(signum, frame):
        fake.stop()

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)
    fake.serve_in_thread()
    try:
        while fake._thread is not None and fake._thread.is_alive():
            fake._thread.join(timeout=0.5)
    finally:
        if args.state:
            fake.dump_state(args.state)
    return 0


if __name__ == "__main__":
    sys.exit(main())
