"""omc - an OMC applet's view of its own ActionUI window and its runtime context.

Import this from a Python command handler and you get two things:

  * `omc.window()`, an `actionui_remote.Window` for the ActionUI window that dispatched the
    handler, so the handler can READ what is on screen rather than work from the snapshot the
    engine took when the command was dispatched.
  * `omc.context()`, everything OMC put in the environment, parsed once and named.

    import omc

    win = omc.window()
    name = win.get_string(101)                  # over the socket, live
    win.set_rows(5, [[name, "ready"]])          # over the socket
    if not name:
        win.terminate_cancel()                  # through omc_dialog_control
        return

Two mechanisms, deliberately. Everything ActionUI defines - values, rows, properties, state,
element insertion, modals, toasts - travels over the remote bridge, because reads are only
possible there. Everything OMC defines on top of a window - terminating it, selecting it,
retargeting a control's command, resizing, moving, chaining to the next command - shells out to
the `omc_dialog_control` and `omc_next_command` tools, which have always implemented those verbs
and remain the single implementation of them. The split is invisible from the calling side.

Requires Python 3.9 or newer, matching actionui_remote. Standard library only. Importing has no
side effect beyond reading os.environ, so a handler with no window can import this safely; only
`omc.window()` raises when there is no window to talk to.
"""

import json
import os
import subprocess
import sys

if sys.version_info < (3, 9):
    raise ImportError("omc requires Python 3.9 or newer (running %d.%d)"
                      % (sys.version_info[0], sys.version_info[1]))

import actionui_remote

__all__ = [
    "OMCWindow", "Context", "Trigger", "OMCError",
    "window", "context", "next_command", "alert",
    "RemoteError", "EndpointError", "ProtocolError",
]

# Re-exported so a handler can catch bridge failures without a second import.
#
# EndpointError matters as much as RemoteError and is easy to miss: omc.window() only checks that
# the variables are set, and actionui_remote opens the socket lazily on the first verb. A host
# that stopped its server after this handler was launched therefore fails at the first get, not
# at omc.window(), and raises this rather than OMCError.
RemoteError = actionui_remote.RemoteError
EndpointError = actionui_remote.EndpointError
ProtocolError = actionui_remote.ProtocolError


class OMCError(RuntimeError):
    """An OMC-side failure: a missing runtime variable, or a helper tool that failed."""


# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

def _env(name, default=""):
    return os.environ.get(name, default)


def _first_env(*names):
    """The first of these variables that is set and non-empty, or ''.

    Both spellings exist for the bridge's two variables: OMC exports its own OMC_-prefixed name
    through the special-word table, and ActionUI exports the unprefixed one the protocol defines.
    They carry the same value; preferring the unprefixed one keeps this module's behavior
    identical to any other ActionUI client.
    """
    for name in names:
        value = os.environ.get(name, "")
        if value:
            return value
    return ""


def _support_tool(name):
    """Absolute path to one of the engine's helper tools, or raise."""
    support = _env("OMC_OMC_SUPPORT_PATH")
    if not support:
        raise OMCError("OMC_OMC_SUPPORT_PATH is not set; this script is not running under OMC")
    path = os.path.join(support, name)
    if not os.path.exists(path):
        raise OMCError("%s not found at %s" % (name, path))
    return path


def _run_tool(path, args):
    """Run a helper tool, raising OMCError with its stderr when it fails."""
    completed = subprocess.run([path] + [str(a) for a in args],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if completed.returncode != 0:
        message = completed.stderr.decode("utf-8", "replace").strip()
        raise OMCError("%s failed (exit %d)%s"
                       % (os.path.basename(path), completed.returncode,
                          ": " + message if message else ""))
    return completed.stdout.decode("utf-8", "replace")


class Trigger:
    """Which control fired the action that dispatched this handler, when one did.

    `context` is the control's opaque payload, JSON-decoded when it parses as JSON and left as
    the raw string when it does not - the engine serializes strings, numbers and JSON through the
    same variable.

    `raw` is that payload exactly as the engine wrote it. The decode is lossy - a control whose
    context is the string "42" arrives as the integer 42, "true" as True, and "null" as None,
    which is indistinguishable from having sent nothing - so a handler that needs the literal
    text reads `raw`.
    """

    __slots__ = ("view_id", "view_part_id", "context", "raw")

    def __init__(self, view_id, view_part_id, context, raw):
        self.view_id = view_id
        self.view_part_id = view_part_id
        self.context = context
        self.raw = raw

    def __repr__(self):
        return ("Trigger(view_id=%r, view_part_id=%r, context=%r, raw=%r)"
                % (self.view_id, self.view_part_id, self.context, self.raw))


class Context:
    """Everything OMC put in the environment for this command, named and typed.

    Read once at construction. A field the engine did not set is '' (or None for the integers
    and for `trigger`), never a KeyError, because which variables exist depends on how the
    command was dispatched.
    """

    __slots__ = ("window_uuid", "endpoint", "command_guid", "parent_command_guid",
                 "app_bundle_path", "support_path", "resources_path",
                 "obj_path", "obj_text", "trigger")

    def __init__(self):
        self.window_uuid = _first_env("ACTIONUI_WINDOW_UUID", "OMC_ACTIONUI_WINDOW_UUID")
        self.endpoint = _first_env("ACTIONUI_REMOTE_ENDPOINT", "OMC_ACTIONUI_REMOTE_ENDPOINT")
        self.command_guid = _env("OMC_CURRENT_COMMAND_GUID")
        self.parent_command_guid = _env("OMC_PARENT_COMMAND_GUID")
        self.app_bundle_path = _env("OMC_APP_BUNDLE_PATH")
        self.support_path = _env("OMC_OMC_SUPPORT_PATH")
        self.resources_path = _env("OMC_OMC_RESOURCES_PATH")
        self.obj_path = _env("OMC_OBJ_PATH")
        self.obj_text = _env("OMC_OBJ_TEXT")
        self.trigger = self._read_trigger()

    @staticmethod
    def _read_trigger():
        raw_view_id = _env("OMC_ACTIONUI_TRIGGER_VIEW_ID")
        if not raw_view_id:
            return None   # not dispatched from a control action

        def as_int(text):
            try:
                return int(text)
            except ValueError:
                return None

        payload = _env("OMC_ACTIONUI_TRIGGER_CONTEXT")
        decoded = payload
        if payload:
            try:
                decoded = json.loads(payload)
            except ValueError:
                decoded = payload   # a plain string the engine passed through
        else:
            decoded = None

        return Trigger(as_int(raw_view_id),
                       as_int(_env("OMC_ACTIONUI_TRIGGER_VIEW_PART_ID")),
                       decoded,
                       payload if payload else None)

    def view_value(self, view_id):
        """The snapshot the engine took of a view's value when this command was dispatched.

        This is the OMC_ACTIONUI_VIEW_<N>_VALUE variable, not a live read - use
        `omc.window().get_value(view_id)` for what is on screen now. Returns None when the
        variable is absent, which it is unless the command asked for it.
        """
        return os.environ.get("OMC_ACTIONUI_VIEW_%d_VALUE" % int(view_id))

    def table_value(self, view_id, column):
        """Likewise for a table's selected row, column `column` (1-based; 0 means all columns,
        tab-separated). Returns None when absent."""
        return os.environ.get("OMC_ACTIONUI_TABLE_%d_COLUMN_%d_VALUE"
                              % (int(view_id), int(column)))

    def table_all_rows(self, view_id, column):
        """Likewise for every row of one column, newline-separated. None when absent."""
        return os.environ.get("OMC_ACTIONUI_TABLE_%d_COLUMN_%d_ALL_ROWS"
                              % (int(view_id), int(column)))

    def __repr__(self):
        return ("Context(window_uuid=%r, endpoint=%r, command_guid=%r, trigger=%r)"
                % (self.window_uuid, self.endpoint, self.command_guid, self.trigger))


# ---------------------------------------------------------------------------
# The window
# ---------------------------------------------------------------------------

# The literal omc_dialog_control uses for "the window itself" rather than a numbered control.
_WINDOW_TARGET = "omc_window"
_APPLICATION_TARGET = "omc_application"


class OMCWindow(actionui_remote.Window):
    """An ActionUI window in an OMC applet.

    Every method of `actionui_remote.Window` works here unchanged and travels over the bridge.
    The methods added below are OMC's own verbs, and each one runs `omc_dialog_control` with
    exactly the arguments a shell handler would use - the docstrings name the instruction word so
    the two guides stay in step.

    Mutations through the tool are delivered to the window on the main thread, the same as
    bridge calls, but through a different channel; do not depend on ordering between a tool call
    and a bridge call made from the same script.
    """

    def _dialog_control(self, target, *args):
        tool = _support_tool("omc_dialog_control")
        _run_tool(tool, [self.uuid, target] + list(args))

    # -- Ending the dialog ---------------------------------------------------

    def terminate_ok(self):
        """Close the window and run its END_OK subcommand. `omc_terminate_ok`."""
        self._dialog_control(_WINDOW_TARGET, "omc_terminate_ok")

    def terminate_cancel(self):
        """Close the window and run its END_CANCEL subcommand. `omc_terminate_cancel`."""
        self._dialog_control(_WINDOW_TARGET, "omc_terminate_cancel")

    # -- Window itself -------------------------------------------------------

    def bring_to_front(self):
        """Bring this window forward. `omc_select` on the window."""
        self._dialog_control(_WINDOW_TARGET, "omc_select")

    def activate_app(self):
        """Bring the whole application forward. `omc_select` on the application."""
        self._dialog_control(_APPLICATION_TARGET, "omc_select")

    def set_title(self, title):
        """Set the window's title bar text. A value set on the window itself.

        omc_dialog_control reads its third argument as an instruction word when it matches one
        exactly, so the plain three-argument form would execute a title of "omc_select" or
        "omc_terminate_cancel" instead of displaying it - closing the dialog, in the second case.
        The tool's four-argument form exists for this: a third argument that is NOT an instruction
        makes it a content-type hint and the fourth unambiguously the value.

        Only titles that could collide take that path, so an ordinary title produces byte for byte
        the argv a shell handler would use. "omc_" is a superset of the instruction words - every
        one begins with it - so no table has to be mirrored here and kept in step.
        """
        text = str(title)
        if text.startswith("omc_"):
            self._dialog_control(_WINDOW_TARGET, "plain", text)
        else:
            self._dialog_control(_WINDOW_TARGET, text)

    def resize(self, width, height):
        """Resize the window's content. `omc_resize` on the window."""
        self._dialog_control(_WINDOW_TARGET, "omc_resize", int(width), int(height))

    def move(self, x, y):
        """Move the window. `omc_move` on the window."""
        self._dialog_control(_WINDOW_TARGET, "omc_move", int(x), int(y))

    # -- Controls ------------------------------------------------------------

    def set_command_id(self, view_id, command_id):
        """Retarget which command a control dispatches. `omc_set_command_id`."""
        self._dialog_control(str(int(view_id)), "omc_set_command_id", str(command_id))

    def select_control(self, view_id):
        """Give a control focus or selection. `omc_select` on the control."""
        self._dialog_control(str(int(view_id)), "omc_select")


# ---------------------------------------------------------------------------
# Module entry points
# ---------------------------------------------------------------------------

def window(timeout=actionui_remote.DEFAULT_TIMEOUT):
    """The ActionUI window this handler was dispatched from.

    Raises OMCError with a specific message when the applet is not serving a bridge (no ActionUI
    window has opened) or when this command was not dispatched from one.
    """
    ctx = Context()
    if not ctx.endpoint:
        raise OMCError(
            "ACTIONUI_REMOTE_ENDPOINT is not set: this host is not serving the ActionUI remote "
            "bridge. It is started by the first ActionUI window an applet opens, so a command "
            "file with no ACTIONUI_WINDOW never starts one.")
    if not ctx.window_uuid:
        raise OMCError(
            "ACTIONUI_WINDOW_UUID is not set: this command was not dispatched from an ActionUI "
            "window, so there is no window to address.")
    return OMCWindow(ctx.window_uuid, endpoint=ctx.endpoint, timeout=timeout)


def context():
    """A fresh snapshot of this command's runtime environment."""
    return Context()


def next_command(command_id, command_guid=None):
    """Schedule another command to run when this handler exits. `omc_next_command`.

    `command_guid` defaults to OMC_CURRENT_COMMAND_GUID, which is what a handler wants.
    """
    guid = command_guid if command_guid else _env("OMC_CURRENT_COMMAND_GUID")
    if not guid:
        raise OMCError("OMC_CURRENT_COMMAND_GUID is not set; cannot chain to '%s'" % command_id)
    _run_tool(_support_tool("omc_next_command"), [guid, command_id])


def alert(message, title=None, level=None, ok=None):
    """Show a system alert through the engine's `alert` tool.

    `level` is one of the tool's levels ("caution", "critical", ...); `ok` overrides the button
    title. Kept here so a Python handler does not have to rebuild the argument list.
    """
    args = []
    if level:
        args += ["--level", str(level)]
    if title:
        args += ["--title", str(title)]
    if ok:
        args += ["--ok", str(ok)]
    args.append(str(message))
    return _run_tool(_support_tool("alert"), args)
