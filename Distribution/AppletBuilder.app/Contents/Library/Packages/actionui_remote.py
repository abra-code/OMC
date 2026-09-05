"""actionui_remote - out-of-process client for ActionUI windows.

Speaks ActionUI Remote Protocol version 1 (see PROTOCOL.md next to this file): newline-delimited
JSON-RPC 2.0 over a Unix domain socket to a host that embeds ActionUI and runs
ActionUIRemoteServer. Pure standard library, Python 3.9 or newer, no threads.

The Window API mirrors the in-process `actionui.Window` naming and argument order, so code
written against the in-process bridge ports here by changing the import and the constructor.
The differences, all deliberate:

- `select_row` returns the selected row (or None when out of range) instead of a bool.
- `present_modal(source, ...)` also accepts the keyword forms `element=` (a dict), `json_text=`
  and `path=` (a resource name or path the host resolves).
- `InsertPosition` is a small class with factory methods (`InsertPosition.at(2)`) instead of an
  enum plus a separate position parameter.
- `batch()`, `call()`, `set_enabled()` and `set_hidden()` exist only here.

Example:

    import actionui_remote as aui
    win = aui.Window.from_environment()      # ACTIONUI_REMOTE_ENDPOINT + ACTIONUI_WINDOW_UUID
    win.set_string(4, "Working...")
    rows = win.get_rows(5)
    with win.batch() as b:                   # one JSON-RPC batch, one main-thread turn
        b.set_rows(5, rows + [["new", "row"]])
        b.set_enabled(2, False)

Errors from the host arrive as RemoteError (with the protocol's error code); socket-level
failures as ConnectionError subclasses (EndpointError, ProtocolError).

There is also a command line, so a shell handler gets a read path instead of only the
environment snapshot taken when it was spawned:

    python3 -m actionui_remote hello
    python3 -m actionui_remote --window UUID get-value 5
    python3 -m actionui_remote get-rows 5           # window from $ACTIONUI_WINDOW_UUID
    python3 -m actionui_remote call actionui.getRows '{"window":"UUID","viewID":5}'

--endpoint, --window and --timeout come before the command, as argparse requires.
"""

import atexit
import errno
import json
import os
import select
import socket
import sys
import weakref

if sys.version_info < (3, 9):
    raise ImportError("actionui_remote requires Python 3.9 or newer; this is %s" % sys.version.split()[0])

__all__ = [
    "PROTOCOL_VERSION", "ENDPOINT_ENV", "WINDOW_ENV", "TOKEN_ENV", "TOKEN_FD_ENV",
    "RemoteError", "EndpointError", "ProtocolError",
    "InsertPosition", "DialogButton", "ButtonRole", "ModalStyle",
    "Connection", "Window", "Batch", "hello", "connect", "main",
    "EXIT_OK", "EXIT_REMOTE_ERROR", "EXIT_USAGE", "EXIT_NO_HOST",
]

PROTOCOL_VERSION = 1
ENDPOINT_ENV = "ACTIONUI_REMOTE_ENDPOINT"
WINDOW_ENV = "ACTIONUI_WINDOW_UUID"
# A host may require a token; the ones it spawned inherit it here. Read automatically, so a
# script that never heard of it keeps working against a host that turns the requirement on.
TOKEN_ENV = "ACTIONUI_REMOTE_TOKEN"
# Or the host hands it over on an inherited pipe and names the descriptor here, so that the token
# is never in this process's environment - where `ps` would show it to any process of the same
# user. The number is no secret; the pipe is. See _read_token_descriptor.
TOKEN_FD_ENV = "ACTIONUI_REMOTE_TOKEN_FD"

DEFAULT_TIMEOUT = 15.0      # seconds; covers the host's 10 s main-thread wait
MAX_LINE_LENGTH = 64 * 1024 * 1024
SUN_PATH_LIMIT = 103        # macOS sun_path, PROTOCOL.md section 1


# --- Errors ---------------------------------------------------------------------------------

class RemoteError(Exception):
    """An error reply from the host. `code` is the protocol error code (PROTOCOL.md section 4)."""

    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603
    UNKNOWN_WINDOW = 1001
    UNKNOWN_VIEW = 1002
    ENGINE_FAILURE = 1003
    HOST_REFUSED = 1004
    MAIN_THREAD_UNAVAILABLE = 1005

    def __init__(self, code, message, data=None, request_id=None, results=None):
        super().__init__("[%s] %s" % (code, message))
        self.code = code
        self.message = message
        self.data = data
        self.request_id = request_id
        # For a batch: the full per-call results list (RemoteError instances in failed slots).
        self.results = results


class EndpointError(ConnectionError):
    """The socket could not be reached: no endpoint configured, path too long, nothing listening."""


class ProtocolError(ConnectionError):
    """The host sent something this client cannot interpret, or closed the connection mid-reply."""


# --- Value types ----------------------------------------------------------------------------

class ButtonRole:
    CANCEL = "cancel"
    DESTRUCTIVE = "destructive"


class ModalStyle:
    SHEET = "sheet"
    FULL_SCREEN_COVER = "fullScreenCover"


class DialogButton:
    """A button for present_alert / present_confirmation_dialog."""

    __slots__ = ("title", "role", "action_id")

    def __init__(self, title, role=None, action_id=None):
        self.title = title
        self.role = role
        self.action_id = action_id

    def to_json(self):
        button = {"title": self.title}
        if self.role is not None:
            button["role"] = self.role
        if self.action_id is not None:
            button["actionID"] = self.action_id
        return button

    @staticmethod
    def coerce(value):
        if isinstance(value, DialogButton):
            return value.to_json()
        if isinstance(value, dict):
            return value
        if isinstance(value, str):
            return {"title": value}
        raise TypeError("a button must be a DialogButton, a dict, or a title string")


class InsertPosition:
    """Where insert_element / insert_row put the new element (PROTOCOL.md section 6)."""

    __slots__ = ("_json",)

    def __init__(self, json_value):
        self._json = json_value

    def to_json(self):
        return self._json

    @classmethod
    def append(cls):
        return cls({"kind": "append"})

    @classmethod
    def prepend(cls):
        return cls({"kind": "prepend"})

    @classmethod
    def at(cls, index):
        return cls({"kind": "at", "index": int(index)})

    @classmethod
    def before(cls, sibling_id):
        return cls({"kind": "before", "siblingID": int(sibling_id)})

    @classmethod
    def after(cls, sibling_id):
        return cls({"kind": "after", "siblingID": int(sibling_id)})

    @staticmethod
    def coerce(value):
        if value is None:
            return None
        if isinstance(value, InsertPosition):
            return value.to_json()
        if isinstance(value, (dict, str)):
            return value
        raise TypeError("position must be an InsertPosition, a dict, or 'append'/'prepend'")


# --- The token on a descriptor --------------------------------------------------------------

# Read once and held for the life of the process: the pipe is drained by its first reader, so
# there is nothing to read a second time. None means "not read yet", not "no token".
_token_from_descriptor = None
# And the failure, if it failed, so that every later attempt reports the same thing.
_token_descriptor_error = None

# A token is 64 characters. The cap is not about tokens, it is about a descriptor that is not the
# pipe the contract describes - a tty, or a socket nobody closed - which would otherwise be read
# until it blocked forever or exhausted memory.
MAX_TOKEN_LENGTH = 4096
# How long to wait for bytes that should already be there. The creator writes the token and
# closes its write end before the child can run, so a correct handoff never waits at all; this
# only bounds a misconfigured descriptor whose write end someone holds open and never writes -
# which the size cap above cannot catch, there being nothing to count. Unbounded would mean
# hanging at import, since that is when the descriptor is read.
TOKEN_DESCRIPTOR_TIMEOUT = 10.0
# os.read raises OverflowError, not OSError, for a number too large for a C int, and that is not
# the failure shape this contract promises.
_MAX_DESCRIPTOR = 2 ** 31 - 1


def _token_descriptor_failure(message, fd=None):
    """Record the failure, close the descriptor, and raise.

    Recorded because the answer must not change between calls. Closed because the reader's half
    of the contract is to leave nothing for its children to inherit, and that is no less true of
    a descriptor that turned out to be unusable - a child inheriting an open one would read from
    whatever it is. The variable is deliberately NOT removed: it is the only remaining trace of
    how this process was configured, and the recorded message, not a re-read, is what later
    attempts report.
    """
    global _token_descriptor_error
    _token_descriptor_error = message
    if fd is not None:
        try:
            os.close(fd)
        except OSError:
            pass
    raise EndpointError(message)


def _read_token_descriptor():
    """The token from $ACTIONUI_REMOTE_TOKEN_FD, or None when no descriptor is configured.

    The lifecycle has two owners (PROTOCOL.md section 10). The process that creates the pipe
    writes the token and a newline and closes its write end at once. This side reads once, then
    closes the descriptor and removes the variable, so that nothing this script spawns inherits
    an open descriptor to a drained pipe, or a variable naming one. A child that needs the bridge
    must be handed its own token.

    A descriptor that is configured but cannot be read is a failure, never a fallback to the
    environment: falling back would silently undo the point of the descriptor, which is that the
    token is not in the environment at all. The failure is recorded, so every later attempt
    reports the same thing rather than a different one.

    Descriptors 0, 1 and 2 are accepted. The number is the creator's to choose, and a creator
    that can only hand over stdin - Foundation's Process, for one - is still a valid creator.
    """
    global _token_from_descriptor
    if _token_from_descriptor is not None:
        return _token_from_descriptor
    if _token_descriptor_error is not None:
        raise EndpointError(_token_descriptor_error)

    raw = os.environ.get(TOKEN_FD_ENV)
    if not raw:
        return None
    # isdigit() alone accepts superscripts and other unicode digits that int() then rejects.
    if not (raw.isascii() and raw.isdigit()):
        _token_descriptor_failure("%s must be a descriptor number, not %r" % (TOKEN_FD_ENV, raw))
    fd = int(raw)
    if fd > _MAX_DESCRIPTOR:
        _token_descriptor_failure("%s is not a descriptor number: %r" % (TOKEN_FD_ENV, raw))

    chunks = []
    total = 0
    try:
        # poll, not select: select raises ValueError - not OSError, so neither handler below
        # would catch it, and the import would die - for any descriptor at or above FD_SETSIZE,
        # which is 1024 on Darwin. poll has no such ceiling, and the C side accepts any number
        # above stderr.
        waiter = select.poll()
        waiter.register(fd, select.POLLIN)
        while True:
            if not waiter.poll(TOKEN_DESCRIPTOR_TIMEOUT * 1000.0):
                _token_descriptor_failure(
                    "descriptor %d (%s) produced nothing in %g seconds; the token should already "
                    "be there" % (fd, TOKEN_FD_ENV, TOKEN_DESCRIPTOR_TIMEOUT), fd)
            chunk = os.read(fd, 4096)
            if not chunk:                       # EOF: the creator closed its write end
                break
            total += len(chunk)                 # everything read, so the cap means what it says
            if total > MAX_TOKEN_LENGTH:
                _token_descriptor_failure(
                    "descriptor %d (%s) gave more than %d bytes with no newline; it is not the "
                    "token pipe" % (fd, TOKEN_FD_ENV, MAX_TOKEN_LENGTH), fd)
            newline = chunk.find(b"\n")
            if newline >= 0:
                chunks.append(chunk[:newline])
                break
            chunks.append(chunk)
    except EndpointError:
        raise                                   # already recorded; not an I/O failure to re-wrap
    except OSError as error:
        # EndpointError subclasses the builtin ConnectionError, and so is an OSError - hence the
        # re-raise above, without which the failures recorded in this loop would be caught here
        # and reported nested inside a "could not be read" message.
        #
        # poll.register rejects a descriptor that is not open at all, with the same shape as a
        # failed read, so both arrive here.
        _token_descriptor_failure("descriptor %d (%s) could not be read: %s"
                                  % (fd, TOKEN_FD_ENV, error), fd)

    token = b"".join(chunks).decode("utf-8", "replace").strip()
    if not token:
        _token_descriptor_failure("nothing could be read from descriptor %d (%s)"
                                  % (fd, TOKEN_FD_ENV), fd)

    try:
        os.close(fd)
    except OSError:
        pass                                    # the token is in hand; a failed close changes nothing
    os.environ.pop(TOKEN_FD_ENV, None)
    _token_from_descriptor = token
    return token


# Drained at import, not at first use. Until it is read, this process holds an open descriptor to
# a live token and exports the variable naming it, so everything it spawns inherits both - and a
# handler that runs a subprocess before its first bridge call would hand that child its token, or
# have the token read out from under it. PROTOCOL.md section 10 wants the descriptor closed out
# and the variable gone; the earliest this module can do that is now.
#
# A failure here is recorded, not raised: an import must not fail over a token nothing has asked
# for yet, and the caller sees the same error at the point it does ask.
try:
    _read_token_descriptor()
except EndpointError:
    pass


# --- Connection -----------------------------------------------------------------------------

_live_connections = weakref.WeakSet()


def _close_all_connections():
    for connection in list(_live_connections):
        connection.close()


atexit.register(_close_all_connections)


class Connection:
    """One socket to one host. Lazily connected, reconnects once on a dead socket, closed at
    interpreter exit. Not thread-safe: a thread that needs its own should construct one directly
    rather than use the process-wide one from connect()."""

    def __init__(self, endpoint, timeout=DEFAULT_TIMEOUT, token=None):
        if not endpoint:
            raise EndpointError("no ActionUI remote endpoint given")
        self.endpoint = endpoint
        self.timeout = timeout
        # An explicit token wins; otherwise the descriptor, then the environment, consulted per
        # request rather than captured here. connect() caches one Connection per endpoint, so
        # capturing would pin whatever the environment held the first time anything connected -
        # and a host that starts serving later, or a test that sets the variable afterwards,
        # would never be seen. The descriptor is the exception, and is cached module-wide: a pipe
        # can only be read once, so re-reading it per request would find nothing.
        self._explicit_token = token
        self._sock = None
        self._buffer = b""
        self._next_id = 1
        _live_connections.add(self)

    @property
    def token(self):
        """The token this connection sends: the explicit one, else the one on
        $ACTIONUI_REMOTE_TOKEN_FD, else $ACTIONUI_REMOTE_TOKEN now.

        Raises EndpointError when a descriptor is configured but unreadable - a host that went to
        the trouble of keeping the token out of the environment must not be answered with an
        environment token that a `ps` sweep could have supplied.
        """
        if self._explicit_token is not None:
            return self._explicit_token
        from_descriptor = _read_token_descriptor()
        if from_descriptor is not None:
            return from_descriptor
        return os.environ.get(TOKEN_ENV, "")

    # -- lifecycle

    def _connect(self):
        # Measured here rather than left to connect(): CPython refuses an over-long AF_UNIX path
        # itself, with an OSError that carries no errno, so the caller would get a message that
        # neither names the limit nor says which path was too long. In bytes, because sun_path
        # holds bytes and a path short in characters can encode long.
        if len(os.fsencode(self.endpoint)) > SUN_PATH_LIMIT:
            raise EndpointError("socket path is too long for sun_path (limit %d bytes): %s"
                                % (SUN_PATH_LIMIT, self.endpoint))
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)
        try:
            sock.connect(self.endpoint)
        except OSError as error:
            sock.close()
            if error.errno in (errno.ENOENT, errno.ECONNREFUSED):
                raise EndpointError("no ActionUI host is listening at %s (%s)" % (self.endpoint, error.strerror)) from None
            raise EndpointError("cannot connect to %s: %s" % (self.endpoint, error)) from None
        self._sock = sock
        self._buffer = b""

    def close(self):
        sock, self._sock = self._sock, None
        if sock is not None:
            try:
                sock.close()
            except OSError:
                pass
        self._buffer = b""

    @property
    def is_connected(self):
        return self._sock is not None

    # -- wire

    def _send_line(self, payload):
        if self._sock is None:
            self._connect()
        self._sock.sendall(payload + b"\n")

    def _read_line(self):
        while True:
            newline = self._buffer.find(b"\n")
            if newline >= 0:
                line = self._buffer[:newline]
                self._buffer = self._buffer[newline + 1:]
                return line
            if len(self._buffer) > MAX_LINE_LENGTH:
                self.close()
                raise ProtocolError("reply exceeds %d bytes" % MAX_LINE_LENGTH)
            try:
                chunk = self._sock.recv(65536)
            except socket.timeout:
                self.close()
                raise ProtocolError("no reply from %s within %.1f s" % (self.endpoint, self.timeout)) from None
            except OSError as error:
                self.close()
                raise ProtocolError("the connection to %s failed while waiting for a reply: %s" % (self.endpoint, error)) from None
            if not chunk:
                self.close()
                raise ProtocolError("the host closed the connection before replying")
            self._buffer += chunk

    def _round_trip(self, payload, expect_reply):
        """Send one line and read one reply line (or none).

        A failure on send reconnects once and resends: nothing reached the host, so a retry is
        safe (a host that closed an idle connection is detected here). A failure while waiting
        for the reply is not retried, by design: the request may already have been applied, and
        resending an appendRows would apply it twice. The caller gets a ProtocolError instead."""
        for attempt in (1, 2):
            try:
                self._send_line(payload)
                break
            except (BrokenPipeError, ConnectionResetError, OSError) as error:
                self.close()
                if attempt == 2 or isinstance(error, EndpointError):
                    raise
        if not expect_reply:
            return None
        return self._read_line()

    # -- JSON-RPC

    def _request(self, method, params, notification=False):
        envelope = {"jsonrpc": "2.0", "method": method}
        if not notification:
            envelope["id"] = self._next_id
            self._next_id += 1
        if self.token:
            # On every request, not once per connection. The host remembers a connection that
            # has authenticated, so this costs nothing after the first; sending it every time is
            # what lets the one-connection-per-request pattern (PROTOCOL.md section 1) keep
            # working without an extra round trip, and what makes a reconnect transparent.
            params = dict(params or {})
            params["token"] = self.token
        if params:
            envelope["params"] = params
        return envelope

    def _read_reply(self, accept):
        """Read lines until `accept(decoded)` is true, ignoring anything else (a reply to
        nothing we sent, or a server-initiated line from a later protocol version). Each
        skipped line still counts against the timeout; a malformed line resets the connection."""
        while True:
            line = self._read_line()
            try:
                decoded = json.loads(line.decode("utf-8"))
            except (UnicodeDecodeError, ValueError) as error:
                self.close()
                raise ProtocolError("unreadable reply from host: %s" % error) from None
            if accept(decoded):
                return decoded

    @staticmethod
    def _unpack(reply, expected_id):
        if not isinstance(reply, dict) or reply.get("jsonrpc") != "2.0":
            raise ProtocolError("malformed reply: %r" % (reply,))
        if reply.get("id") != expected_id:
            raise ProtocolError("reply id %r does not match request id %r" % (reply.get("id"), expected_id))
        if "error" in reply:
            error = reply["error"] or {}
            return RemoteError(error.get("code", RemoteError.INTERNAL_ERROR), error.get("message", ""),
                               error.get("data"), request_id=expected_id)
        return reply.get("result")

    def call(self, method, params=None):
        """Call one method and return its result. Raises RemoteError on an error reply."""
        envelope = self._request(method, params or {})
        self._round_trip(json.dumps(envelope, separators=(",", ":")).encode("utf-8"), False)
        expected = envelope["id"]
        reply = self._read_reply(lambda d: isinstance(d, dict) and d.get("id") == expected)
        outcome = self._unpack(reply, expected)
        if isinstance(outcome, RemoteError):
            raise outcome
        return outcome

    def notify(self, method, params=None):
        """Fire and forget: the host executes the method and sends no reply."""
        envelope = self._request(method, params or {}, notification=True)
        self._round_trip(json.dumps(envelope, separators=(",", ":")).encode("utf-8"), False)

    def call_batch(self, calls):
        """Send several calls as one JSON-RPC batch. `calls` is a list of (method, params) pairs.
        Returns a list with one entry per call: the result, or a RemoteError instance."""
        envelopes = [self._request(method, params or {}) for method, params in calls]
        if not envelopes:
            return []
        self._round_trip(json.dumps(envelopes, separators=(",", ":")).encode("utf-8"), False)
        ids = {e["id"] for e in envelopes}

        def is_ours(decoded):
            if isinstance(decoded, list):
                return any(isinstance(r, dict) and r.get("id") in ids for r in decoded)
            # A whole-batch rejection arrives as one object with a null id.
            return isinstance(decoded, dict) and decoded.get("id") is None and "error" in decoded

        replies = self._read_reply(is_ours)
        if isinstance(replies, dict):
            # A whole-batch rejection (parse error, oversized batch) comes back as one object.
            outcome = self._unpack(replies, replies.get("id"))
            if isinstance(outcome, RemoteError):
                return [outcome] * len(envelopes)
            raise ProtocolError("expected a batch reply, got a single result")
        if not isinstance(replies, list):
            raise ProtocolError("malformed batch reply: %r" % (replies,))
        by_id = {}
        for reply in replies:
            if isinstance(reply, dict):
                by_id[reply.get("id")] = reply
        results = []
        for envelope in envelopes:
            reply = by_id.get(envelope["id"])
            if reply is None:
                results.append(RemoteError(RemoteError.INTERNAL_ERROR, "no reply for batch member", request_id=envelope["id"]))
            else:
                results.append(self._unpack(reply, envelope["id"]))
        return results


_connections = {}


def connect(endpoint=None, timeout=DEFAULT_TIMEOUT, token=None):
    """The process-wide Connection for an endpoint (default: $ACTIONUI_REMOTE_ENDPOINT).

    One connection per endpoint is shared by every Window in the process; it is not
    thread-safe. A later call with a different timeout applies it to the shared connection."""
    endpoint = endpoint or os.environ.get(ENDPOINT_ENV)
    if not endpoint:
        raise EndpointError("%s is not set; this host did not start the ActionUI remote server" % ENDPOINT_ENV)
    connection = _connections.get(endpoint)
    if connection is None:
        connection = Connection(endpoint, timeout=timeout, token=token)
        _connections[endpoint] = connection
    elif connection.timeout != timeout:
        connection.timeout = timeout
        if connection._sock is not None:
            connection._sock.settimeout(timeout)
    return connection


def hello(endpoint=None):
    """The host's actionui.hello: protocol version, host name and version, methods, windows."""
    return connect(endpoint).call("actionui.hello")


# --- Window ---------------------------------------------------------------------------------

def _int(value, name):
    if isinstance(value, bool) or not isinstance(value, int):
        raise TypeError("%s must be an integer, not %r" % (name, value))
    return value


class Window:
    """One ActionUI window on one host, addressed by UUID. Stateless: every call carries the
    UUID, and the object holds nothing but the UUID and a connection."""

    def __init__(self, uuid, endpoint=None, connection=None, timeout=DEFAULT_TIMEOUT):
        if not uuid:
            raise ValueError("a window UUID is required")
        self.uuid = uuid
        self._connection = connection or connect(endpoint, timeout=timeout)

    @classmethod
    def from_environment(cls, timeout=DEFAULT_TIMEOUT):
        """The window named by $ACTIONUI_WINDOW_UUID on the host at $ACTIONUI_REMOTE_ENDPOINT."""
        uuid = os.environ.get(WINDOW_ENV)
        if not uuid:
            raise EndpointError("%s is not set; this process was not started for an ActionUI window" % WINDOW_ENV)
        return cls(uuid, timeout=timeout)

    def __repr__(self):
        return "Window(%r, endpoint=%r)" % (self.uuid, self._connection.endpoint)

    @property
    def connection(self):
        return self._connection

    # -- plumbing

    def _params(self, more=None, view_id=None, view_part_id=None):
        params = {"window": self.uuid}
        if view_id is not None:
            params["viewID"] = _int(view_id, "view_id")
        if view_part_id:
            params["viewPartID"] = _int(view_part_id, "view_part_id")
        if more:
            params.update(more)
        return params

    def call(self, method, params=None):
        """Escape hatch: any method, with `window` filled in. Host methods (`omc.*`) go here."""
        return self._connection.call(method, self._params(params))

    def batch(self, raise_on_error=True):
        """Collect calls and send them as one batch: `with win.batch() as b: b.set_string(...)`."""
        return Batch(self, raise_on_error=raise_on_error)

    # -- discovery

    def get_element_info(self):
        """{view_id: element type} for every user-assigned (positive) id."""
        return _POST["get_element_info"](self.call("actionui.getElementInfo"))

    def content_size_limits(self):
        """(min_w, min_h, max_w, max_h) of the loaded root element, or None."""
        return _POST["content_size_limits"](self.call("actionui.contentSizeLimits"))

    # -- values

    def get_value(self, view_id, view_part_id=0):
        return self._connection.call("actionui.getValue", self._params(view_id=view_id, view_part_id=view_part_id))

    def set_value(self, view_id, view_part_id, value):
        """Same argument order as the in-process module: (view_id, view_part_id, value)."""
        return self._connection.call("actionui.setValue", self._params({"value": value}, view_id, view_part_id))

    def get_string(self, view_id, view_part_id=0, content_type=None):
        more = {"contentType": content_type} if content_type else None
        return self._connection.call("actionui.getValueString", self._params(more, view_id, view_part_id))

    def set_string(self, view_id, value, view_part_id=0, content_type=None):
        more = {"value": str(value)}
        if content_type:
            more["contentType"] = content_type
        return self._connection.call("actionui.setValueString", self._params(more, view_id, view_part_id))

    def get_int(self, view_id, view_part_id=0):
        return _POST["get_int"](self.get_value(view_id, view_part_id))

    def set_int(self, view_id, value, view_part_id=0):
        return self.set_value(view_id, view_part_id, int(value))

    def get_double(self, view_id, view_part_id=0):
        return _POST["get_double"](self.get_value(view_id, view_part_id))

    def set_double(self, view_id, value, view_part_id=0):
        return self.set_value(view_id, view_part_id, float(value))

    def get_bool(self, view_id, view_part_id=0):
        return _POST["get_bool"](self.get_value(view_id, view_part_id))

    def set_bool(self, view_id, value, view_part_id=0):
        return self.set_value(view_id, view_part_id, bool(value))

    # -- properties and state

    def get_property(self, view_id, name):
        return self._connection.call("actionui.getProperty", self._params({"name": name}, view_id))

    def set_property(self, view_id, name, value):
        return self._connection.call("actionui.setProperty", self._params({"name": name, "value": value}, view_id))

    def set_enabled(self, view_id, enabled):
        """Sugar for the `disabled` property (omc_enable / omc_disable)."""
        return self.set_property(view_id, "disabled", not enabled)

    def set_hidden(self, view_id, hidden):
        """Sugar for the `hidden` property (omc_hide / omc_show)."""
        return self.set_property(view_id, "hidden", bool(hidden))

    def get_state(self, view_id, key):
        return self._connection.call("actionui.getState", self._params({"key": key}, view_id))

    def get_state_string(self, view_id, key):
        return self._connection.call("actionui.getStateString", self._params({"key": key}, view_id))

    def set_state(self, view_id, key, value):
        return self._connection.call("actionui.setState", self._params({"key": key, "value": value}, view_id))

    def set_state_from_string(self, view_id, key, value):
        return self._connection.call("actionui.setStateString", self._params({"key": key, "value": str(value)}, view_id))

    # -- rows and selection

    def get_column_count(self, view_id):
        return self._connection.call("actionui.getColumnCount", self._params(view_id=view_id))

    def get_rows(self, view_id):
        """The table's rows, or None when the element is not a Table or List (as in-process)."""
        return self._connection.call("actionui.getRows", self._params(view_id=view_id))

    def set_rows(self, view_id, rows):
        return self._connection.call("actionui.setRows", self._params({"rows": _rows(rows)}, view_id))

    def append_rows(self, view_id, rows):
        return self._connection.call("actionui.appendRows", self._params({"rows": _rows(rows)}, view_id))

    def clear_rows(self, view_id):
        return self._connection.call("actionui.clearRows", self._params(view_id=view_id))

    def select_row(self, view_id, index):
        """Select a row by 0-based index; returns the row, or None when out of range."""
        return self._connection.call("actionui.selectRow", self._params({"index": _int(index, "index")}, view_id))

    def select_row_with_content(self, view_id, text, column=None):
        """Select the first row whose column (0-based; None = any) equals text. Returns the
        row index, or -1."""
        more = {"text": str(text)}
        if column is not None:
            more["column"] = _int(column, "column")
        return self._connection.call("actionui.selectRowWithContent", self._params(more, view_id))

    def clear_selection(self, view_id):
        return self._connection.call("actionui.clearSelection", self._params(view_id=view_id))

    # -- structural mutation

    def insert_element(self, parent_id, element, container=None, position=None):
        """Insert one element (a dict describing it) into a container; returns its id."""
        more = {"parentID": _int(parent_id, "parent_id"), "element": element}
        if container:
            more["container"] = container
        if position is not None:
            more["position"] = InsertPosition.coerce(position)
        return self.call("actionui.insertElement", more)

    def insert_row(self, parent_id, cells, container=None, position=None):
        """Insert a row of cells (a list of element dicts) into a rows container; returns their ids."""
        more = {"parentID": _int(parent_id, "parent_id"), "cells": list(cells)}
        if container:
            more["container"] = container
        if position is not None:
            more["position"] = InsertPosition.coerce(position)
        return self.call("actionui.insertRow", more)

    def remove_element(self, view_id):
        return self._connection.call("actionui.removeElement", self._params(view_id=view_id))

    # -- presentation

    def present_modal(self, source=None, format=None, style=None, on_dismiss_action_id=None,
                      element=None, json_text=None, path=None):
        """Present a sheet or full-screen cover. `source` (the in-process module's positional
        argument) is a dict (the element) or a string (JSON or plist text, per `format`); the
        keywords `element=`, `json_text=` and `path=` (a resource name or path the host
        resolves) are the explicit forms."""
        if source is not None:
            if isinstance(source, dict):
                element = source
            elif isinstance(source, str):
                json_text = source
            else:
                raise TypeError("source must be a dict (element) or a str (JSON/plist text)")
        more = {}
        if element is not None:
            more["element"] = element
        elif json_text is not None:
            more["json"] = json_text
        elif path is not None:
            more["path"] = path
        else:
            raise ValueError("present_modal needs element, json_text, or path")
        if format:
            more["format"] = format
        if style:
            more["style"] = style
        if on_dismiss_action_id:
            more["onDismissActionID"] = on_dismiss_action_id
        return self.call("actionui.presentModal", more)

    def dismiss_modal(self):
        return self.call("actionui.dismissModal")

    def present_alert(self, title, message=None, buttons=None):
        more = {"title": title}
        if message is not None:
            more["message"] = message
        if buttons:
            more["buttons"] = [DialogButton.coerce(b) for b in buttons]
        return self.call("actionui.presentAlert", more)

    def present_confirmation_dialog(self, title, message=None, buttons=None):
        """Same argument order as the in-process module. `buttons` is required and non-empty."""
        if isinstance(buttons, (str, dict, DialogButton)) or not buttons:
            raise ValueError("present_confirmation_dialog needs a non-empty list of buttons")
        more = {"title": title, "buttons": [DialogButton.coerce(b) for b in buttons]}
        if message is not None:
            more["message"] = message
        return self.call("actionui.presentConfirmationDialog", more)

    def dismiss_dialog(self):
        return self.call("actionui.dismissDialog")

    def present_toast(self, message, duration=None, action_title=None, action_id=None):
        more = {"message": message}
        if duration is not None:
            more["duration"] = float(duration)
        if action_title is not None:
            more["actionTitle"] = action_title
        if action_id is not None:
            more["actionID"] = action_id
        return self.call("actionui.presentToast", more)

    def dismiss_toast(self):
        return self.call("actionui.dismissToast")


def _rows(rows):
    out = []
    for row in rows:
        if isinstance(row, (str, bytes)):
            raise TypeError("each row must be a sequence of cells, not a string: %r" % (row,))
        out.append([str(cell) for cell in row])
    return out


# Post-processing applied to a raw wire result by the typed getters, shared with Batch so that a
# batched b.get_int(...) yields the same value as win.get_int(...).
_POST = {
    "get_int": lambda r: None if r is None else int(r),
    "get_double": lambda r: None if r is None else float(r),
    "get_bool": lambda r: None if r is None else bool(r),
    "get_element_info": lambda r: {int(k): v for k, v in (r or {}).items()},
    "content_size_limits": lambda r: None if not r else (r["minWidth"], r["minHeight"], r["maxWidth"], r["maxHeight"]),
}


# --- Batch ----------------------------------------------------------------------------------

class Batch:
    """Records Window calls and sends them as one JSON-RPC batch on exit.

    Inside the block every Window method is available on the batch object and returns None.
    After the block `results` holds one entry per call, post-processed exactly as the direct
    call would be (get_int yields an int, get_element_info an {int: str} dict), or a RemoteError
    instance in a failed slot. With raise_on_error (the default) the first failure is raised on exit, carrying the
    full list as `err.results`.
    """

    def __init__(self, window, raise_on_error=True):
        self._window = window
        self._raise_on_error = raise_on_error
        self._calls = []
        self.results = None

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        if exc_type is not None:
            return False
        self.send()
        return False

    def send(self):
        if self.results is not None:
            raise RuntimeError("this batch was already sent")
        raw = self._window.connection.call_batch([call for call, _ in self._calls])
        self.results = [outcome if isinstance(outcome, RemoteError) or post is None else post(outcome)
                        for outcome, (_, post) in zip(raw, self._calls)]
        if self._raise_on_error:
            for outcome in self.results:
                if isinstance(outcome, RemoteError):
                    outcome.results = self.results
                    raise outcome
        return self.results

    def __getattr__(self, name):
        method = getattr(Window, name, None)
        if method is None or name.startswith("_") or name in ("batch", "connection", "from_environment"):
            raise AttributeError(name)

        def record(*args, **kwargs):
            recorder = _Recorder(self._window)
            method(recorder, *args, **kwargs)
            post = _POST.get(name)
            self._calls.extend((call, post) for call in recorder.calls)
            return None

        return record


class _Recorder(Window):
    """A Window whose connection records instead of sending; used by Batch."""

    def __init__(self, window):
        self.uuid = window.uuid
        self.calls = []
        self._connection = self

    # Window methods reach the wire in two ways: through Window.call (which adds "window") and
    # through self._connection.call with fully built params. The recorder is both objects, so
    # this single entry point receives complete params in both cases.
    def call(self, method, params=None):
        params = dict(params or {})
        params.setdefault("window", self.uuid)
        self.calls.append((method, params))
        return None

    @property
    def endpoint(self):
        return None


# --- Command line ---------------------------------------------------------------------------
#
# `python3 -m actionui_remote <command>`. The point is the read path: a shell handler is given
# its window's values as environment variables at spawn time and has had no way to ask for them
# again. Setters are here too, but writes already had omc_dialog_control.
#
# Output: JSON on one line for the value commands, the text itself for the string commands (as
# many lines as it holds), one UUID per line for `windows`, and nothing at all for a setter that
# succeeded. `get-string` prints an empty line both for a null value and for an empty string.

EXIT_OK = 0
EXIT_REMOTE_ERROR = 1       # the host answered an error; the message carries the protocol code
EXIT_USAGE = 2              # argparse's own code for a bad command line
EXIT_NO_HOST = 3            # nothing to talk to: no endpoint set, nothing listening, a dead socket

# The commands that do not name an element, so they do not need a window.
_NO_WINDOW_COMMANDS = ("hello", "windows", "call")


def _json_line(value):
    return json.dumps(value, separators=(",", ":"), sort_keys=True) + "\n"


def _run_command(args, connection):
    """Run one parsed command and return what to print, or None to print nothing."""
    if args.command == "hello":
        return _json_line(connection.call("actionui.hello"))
    if args.command == "windows":
        return "".join(uuid + "\n" for uuid in connection.call("actionui.listWindows"))
    if args.command == "call":
        params = args.params if args.params is not None else {}
        if args.window:
            # Window.call fills in "window", and an explicit one in params still wins.
            return _json_line(Window(args.window, connection=connection).call(args.method, params))
        return _json_line(connection.call(args.method, params))

    window = Window(args.window, connection=connection)
    if args.command == "elements":
        return _json_line(window.get_element_info())
    if args.command == "get-value":
        return _json_line(window.get_value(args.view_id, args.part))
    if args.command == "set-value":
        window.set_value(args.view_id, args.part, args.value)
        return None
    if args.command == "get-string":
        text = window.get_string(args.view_id, args.part, args.content_type)
        return ("" if text is None else text) + "\n"
    if args.command == "set-string":
        window.set_string(args.view_id, args.text, args.part, args.content_type)
        return None
    if args.command == "get-rows":
        return _json_line(window.get_rows(args.view_id))
    if args.command == "set-rows":
        window.set_rows(args.view_id, args.rows)
        return None
    if args.command == "get-property":
        return _json_line(window.get_property(args.view_id, args.name))
    if args.command == "set-property":
        window.set_property(args.view_id, args.name, args.value)
        return None
    if args.command == "get-state":
        return _json_line(window.get_state(args.view_id, args.key))
    if args.command == "set-state":
        window.set_state(args.view_id, args.key, args.value)
        return None
    # Unreachable: argparse only yields the commands built below. An AssertionError rather than
    # a ValueError, because main reports a ValueError as a usage error and this is a bug.
    raise AssertionError("unhandled command %r" % (args.command,))


def _build_parser(argparse):
    def json_argument(text):
        try:
            return json.loads(text)
        except ValueError as error:
            raise argparse.ArgumentTypeError("expected JSON, got %r (%s)" % (text, error))

    def timeout_argument(text):
        try:
            seconds = float(text)
        except ValueError:
            raise argparse.ArgumentTypeError("expected a number of seconds, got %r" % text)
        if seconds <= 0:
            raise argparse.ArgumentTypeError("must be greater than zero, got %s" % text)
        return seconds

    parser = argparse.ArgumentParser(
        prog="python3 -m actionui_remote",
        description="Read and drive an ActionUI window from the shell.",
        epilog="--endpoint, --window and --timeout come before the command. "
               "Exit codes: 0 ok, 1 the host answered an error, 2 bad usage, 3 no host to talk to; "
               "an output pipe closed early (| head) is not an error. "
               "An argument starting with a dash that is not a number needs -- before it, "
               "as in `set-string 2 -- -hello`.")
    parser.add_argument("--endpoint", default=os.environ.get(ENDPOINT_ENV),
                        help="socket path (default: $%s)" % ENDPOINT_ENV)
    parser.add_argument("--window", default=os.environ.get(WINDOW_ENV),
                        help="window UUID (default: $%s)" % WINDOW_ENV)
    # Normally inherited, so this is for driving a host by hand from a shell that is not its
    # child - which necessarily means getting the token out of the host deliberately.
    parser.add_argument("--token", default=None,
                        help="token, if the host requires one (default: $%s)" % TOKEN_ENV)
    parser.add_argument("--timeout", type=timeout_argument, default=DEFAULT_TIMEOUT,
                        help="seconds to wait for a reply (default: %g)" % DEFAULT_TIMEOUT)
    commands = parser.add_subparsers(dest="command", required=True, metavar="COMMAND")

    def element_command(name, help_text):
        command = commands.add_parser(name, help=help_text)
        command.add_argument("view_id", type=int, metavar="VIEWID")
        return command

    def with_part(command):
        command.add_argument("--part", type=int, default=0, metavar="N",
                             help="sub-part, notably a 1-based Table column")
        return command

    commands.add_parser("hello", help="print the host's actionui.hello")
    commands.add_parser("windows", help="print every window UUID, one per line")
    commands.add_parser("elements", help="print the window's element ids and types as JSON")

    with_part(element_command("get-value", "print an element's value as JSON"))
    set_value = with_part(element_command("set-value", "set an element's value from JSON"))
    set_value.add_argument("value", type=json_argument, metavar="JSON")

    get_string = with_part(element_command("get-string", "print an element's value as text"))
    get_string.add_argument("--content-type", dest="content_type", metavar="TYPE",
                            help="ask the host for this representation, e.g. plain or markdown")
    set_string = with_part(element_command("set-string", "set an element's value from text"))
    set_string.add_argument("text", metavar="TEXT")
    set_string.add_argument("--content-type", dest="content_type", metavar="TYPE",
                            help="how to read TEXT, e.g. plain or markdown")

    element_command("get-rows", "print a Table's rows as JSON")
    set_rows = element_command("set-rows", "set a Table's rows from a JSON array of arrays")
    set_rows.add_argument("rows", type=json_argument, metavar="JSON")

    get_property = element_command("get-property", "print a property as JSON")
    get_property.add_argument("name", metavar="NAME")
    set_property = element_command("set-property", "set a property from JSON")
    set_property.add_argument("name", metavar="NAME")
    set_property.add_argument("value", type=json_argument, metavar="JSON")

    get_state = element_command("get-state", "print a state key as JSON")
    get_state.add_argument("key", metavar="KEY")
    set_state = element_command("set-state", "set a state key from JSON")
    set_state.add_argument("key", metavar="KEY")
    set_state.add_argument("value", type=json_argument, metavar="JSON")

    call = commands.add_parser("call", help="call any method, host methods included")
    call.add_argument("method", metavar="METHOD")
    call.add_argument("params", nargs="?", type=json_argument, default=None, metavar="JSON")
    return parser


def main(argv=None):
    """The `python3 -m actionui_remote` entry point. Returns the process exit code.

    Except for argparse's own errors, which raise SystemExit(EXIT_USAGE) as argparse does
    everywhere.
    """
    import argparse       # imported here: every OMC handler imports this module, few run it

    parser = _build_parser(argparse)
    args = parser.parse_args(argv)
    if args.command == "call" and args.params is not None and not isinstance(args.params, dict):
        parser.error("params must be a JSON object with named keys")

    try:
        # Before the window check, so a handler running outside an ActionUI window is told there
        # is no host (3) whatever the command, rather than that its command line is wrong.
        connection = connect(args.endpoint, timeout=args.timeout, token=args.token)
    except EndpointError as error:
        sys.stderr.write("%s\n" % error)
        return EXIT_NO_HOST

    if args.command not in _NO_WINDOW_COMMANDS and not args.window:
        parser.error("no window: pass --window or set %s" % WINDOW_ENV)

    try:
        output = _run_command(args, connection)
    except RemoteError as error:
        sys.stderr.write("%s\n" % error)
        return EXIT_REMOTE_ERROR
    except (EndpointError, ProtocolError) as error:
        sys.stderr.write("%s\n" % error)
        return EXIT_NO_HOST
    except TypeError as error:
        # A JSON argument that parsed but is the wrong shape: a string where rows belong.
        sys.stderr.write("%s\n" % error)
        return EXIT_USAGE
    except KeyboardInterrupt:
        return 130      # the shell's convention for a command interrupted by SIGINT

    try:
        if output:
            sys.stdout.write(output)
        sys.stdout.flush()
    except BrokenPipeError:
        # The reader went away, as `| head` does. The command itself succeeded, so this is not
        # an error; point stdout at /dev/null so the interpreter's shutdown flush stays quiet
        # too, which is the only way to avoid a second message on the way out.
        try:
            os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        except OSError:
            pass
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
