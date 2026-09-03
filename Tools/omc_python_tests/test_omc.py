"""Unit tests for the `omc` Python module shipped to applets.

Two halves, matching the module's two mechanisms:

  * ActionUI verbs must reach the remote bridge. Driven against actionui_remote_testing.FakeServer
    and asserted from the server's own request log, so a test cannot pass by the call silently
    doing nothing.
  * OMC verbs must invoke the engine's helper tools with exactly the argv a shell handler would
    use. Driven against stub tools that record their argv, for the same reason.

Run: cd Tools/omc_python_tests && python3 -m unittest test_omc
(By path from the repo root it fails with ModuleNotFoundError: -m unittest puts the CWD on
sys.path, not the test file's directory.)
"""

import json
import os
import stat
import sys
import tempfile
import unittest
import uuid as uuidlib

# Set before the shipped modules are imported below. Importing omc.py from inside
# AppletBuilder.app would otherwise leave __pycache__ in a bundle directory that gets codesigned,
# and .pyc in a bundle must stay loudly visible in git rather than be ignored - so the fix is to
# not write it, the same choice the engine makes with PYTHONPYCACHEPREFIX at runtime.
sys.dont_write_bytecode = True

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_PACKAGES = os.path.join(_REPO_ROOT, "Distribution", "AppletBuilder.app",
                         "Contents", "Library", "Packages")
_ACTIONUI_TESTING = os.path.join(_REPO_ROOT, "..", "ActionUI", "ActionUIRemote", "Python")

# Order matters and is easy to get backwards: insert(0, ...) puts the LAST one first, so
# _PACKAGES goes second and wins. The point of this suite is the SHIPPED modules; the ActionUI
# checkout is on the path only for actionui_remote_testing, which does not ship.
sys.path.insert(0, _ACTIONUI_TESTING)
sys.path.insert(0, _PACKAGES)

import actionui_remote             # noqa: E402  (path set up above)
import actionui_remote_testing     # noqa: E402
import omc                         # noqa: E402

# Asserted at import, not in a test, because every test below is meaningless if it is testing a
# copy that is not the one applets receive.
for _module in (omc, actionui_remote):
    if not os.path.abspath(_module.__file__).startswith(os.path.abspath(_PACKAGES)):
        raise ImportError("%s resolved to %s, not the shipped copy under %s"
                          % (_module.__name__, _module.__file__, _PACKAGES))


# The variables omc.Context reads. Cleared around every test so a stray value in the developer's
# own environment cannot make a test pass.
_OMC_VARS = [
    "ACTIONUI_REMOTE_ENDPOINT", "OMC_ACTIONUI_REMOTE_ENDPOINT",
    "ACTIONUI_WINDOW_UUID", "OMC_ACTIONUI_WINDOW_UUID",
    "OMC_CURRENT_COMMAND_GUID", "OMC_PARENT_COMMAND_GUID",
    "OMC_APP_BUNDLE_PATH", "OMC_OMC_SUPPORT_PATH", "OMC_OMC_RESOURCES_PATH",
    "OMC_OBJ_PATH", "OMC_OBJ_TEXT",
    "OMC_ACTIONUI_TRIGGER_VIEW_ID", "OMC_ACTIONUI_TRIGGER_VIEW_PART_ID",
    "OMC_ACTIONUI_TRIGGER_CONTEXT",
    "OMC_ACTIONUI_VIEW_101_VALUE",
    "OMC_ACTIONUI_TABLE_5_COLUMN_1_VALUE",
    "OMC_ACTIONUI_TABLE_5_COLUMN_1_ALL_ROWS",
]


class OMCTestBase(unittest.TestCase):

    def setUp(self):
        self._saved = {name: os.environ.get(name) for name in _OMC_VARS}
        for name in _OMC_VARS:
            os.environ.pop(name, None)
        self._tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tempdir.cleanup)
        self.addCleanup(self._restore_environment)

    def _restore_environment(self):
        for name, value in self._saved.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value

    def path(self, *parts):
        return os.path.join(self._tempdir.name, *parts)

    def make_stub_tool(self, name, exit_code=0, stderr_text=""):
        """A helper tool that appends its argv, one JSON array per line, to <name>.argv."""
        support = self.path("Support")
        os.makedirs(support, exist_ok=True)
        record = self.path(name + ".argv")
        # The recorder's own failure must not be silent: without this check a bad interpreter
        # path would exit 0 and leave no argv file, and every "did not shell out" assertion of []
        # would pass for the wrong reason. 99 is distinguishable from any exit_code under test.
        script = (
            "#!/bin/sh\n"
            "'%s' -c 'import json,sys; "
            "open(sys.argv[1],\"a\").write(json.dumps(sys.argv[2:])+chr(10))' "
            "'%s' \"$@\"\n"
            "_rc=$?\n"
            "if [ \"$_rc\" -ne 0 ]; then exit 99; fi\n" % (sys.executable, record)
        )
        if stderr_text:
            script += "echo %s >&2\n" % stderr_text
        script += "exit %d\n" % exit_code

        tool_path = os.path.join(support, name)
        with open(tool_path, "w") as handle:
            handle.write(script)
        os.chmod(tool_path, os.stat(tool_path).st_mode | stat.S_IXUSR)
        os.environ["OMC_OMC_SUPPORT_PATH"] = support
        return record

    def recorded_argv(self, record_path):
        if not os.path.exists(record_path):
            return []
        with open(record_path) as handle:
            return [json.loads(line) for line in handle if line.strip()]

    def start_fake_host(self, window_uuid=None):
        """A FakeServer with one window, and the environment pointing at it.

        The window carries the two elements the bridge tests address: a TextField at 101 and a
        Table at 5. Without them the fake answers 1002 (unknown view), which is correct of it.
        """
        window_uuid = window_uuid or str(uuidlib.uuid4())
        socket_path = self.path("omc-test.sock")
        server = actionui_remote_testing.FakeServer(socket_path,
                                                    log_path=self.path("requests.jsonl"),
                                                    host_name="OMCTestHost",
                                                    host_version="5.3")
        server.add_window(window_uuid, elements={101: "TextField", 5: "Table"})
        server.serve_in_thread()
        self.addCleanup(server.stop)

        os.environ["ACTIONUI_REMOTE_ENDPOINT"] = socket_path
        os.environ["ACTIONUI_WINDOW_UUID"] = window_uuid
        return server, window_uuid

    def logged_methods(self):
        """Every method name the fake was asked for, in order."""
        path = self.path("requests.jsonl")
        if not os.path.exists(path):
            return []
        methods = []
        with open(path) as handle:
            for line in handle:
                if not line.strip():
                    continue
                entry = json.loads(line)
                if isinstance(entry, dict) and entry.get("method"):
                    methods.append(entry["method"])
        return methods


class ShippedModuleTests(OMCTestBase):
    """The suite is only worth anything if it exercises what applets receive."""

    def test_the_modules_under_test_are_the_shipped_ones(self):
        packages = os.path.abspath(_PACKAGES)
        self.assertTrue(os.path.abspath(omc.__file__).startswith(packages))
        self.assertTrue(os.path.abspath(actionui_remote.__file__).startswith(packages))

    def test_the_vendored_client_matches_actionui(self):
        """A stale vendored copy is invisible until a handler hits a missing method at run time.

        actionui_remote.py is copied from the ActionUI checkout by update_appletbuilder.sh and is
        never edited here, so any difference means the copy is behind and needs a re-vendor.
        """
        source = os.path.join(_ACTIONUI_TESTING, "actionui_remote.py")
        if not os.path.exists(source):
            self.skipTest("ActionUI checkout not present")
        with open(source, "rb") as handle:
            upstream = handle.read()
        with open(os.path.join(_PACKAGES, "actionui_remote.py"), "rb") as handle:
            shipped = handle.read()
        self.assertEqual(shipped, upstream,
                         "vendored actionui_remote.py is out of date; rerun update_appletbuilder.sh")


class StubToolTests(OMCTestBase):
    """The stub tools carry the OMC-verb assertions, so they have to be shown to work."""

    def test_a_stub_records_what_it_was_called_with(self):
        record = self.make_stub_tool("omc_dialog_control")
        tool = os.path.join(os.environ["OMC_OMC_SUPPORT_PATH"], "omc_dialog_control")
        omc._run_tool(tool, ["one", "two"])
        self.assertEqual(self.recorded_argv(record), [["one", "two"]],
                         "an empty argv list must mean 'not called', never 'recorder broken'")


class ContextTests(OMCTestBase):

    def test_reads_every_documented_field(self):
        os.environ.update({
            "ACTIONUI_REMOTE_ENDPOINT": "/tmp/endpoint.sock",
            "ACTIONUI_WINDOW_UUID": "W-1",
            "OMC_CURRENT_COMMAND_GUID": "C-1",
            "OMC_PARENT_COMMAND_GUID": "C-0",
            "OMC_APP_BUNDLE_PATH": "/Applications/My.app",
            "OMC_OMC_SUPPORT_PATH": "/Applications/My.app/Support",
            "OMC_OMC_RESOURCES_PATH": "/Applications/My.app/Resources",
            "OMC_OBJ_PATH": "/Users/me/file.txt",
            "OMC_OBJ_TEXT": "selected text",
        })
        ctx = omc.context()
        self.assertEqual(ctx.endpoint, "/tmp/endpoint.sock")
        self.assertEqual(ctx.window_uuid, "W-1")
        self.assertEqual(ctx.command_guid, "C-1")
        self.assertEqual(ctx.parent_command_guid, "C-0")
        self.assertEqual(ctx.app_bundle_path, "/Applications/My.app")
        self.assertEqual(ctx.support_path, "/Applications/My.app/Support")
        self.assertEqual(ctx.resources_path, "/Applications/My.app/Resources")
        self.assertEqual(ctx.obj_path, "/Users/me/file.txt")
        self.assertEqual(ctx.obj_text, "selected text")
        self.assertIsNone(ctx.trigger)

    def test_missing_variables_are_empty_not_errors(self):
        ctx = omc.context()      # nothing set at all
        self.assertEqual(ctx.window_uuid, "")
        self.assertEqual(ctx.endpoint, "")
        self.assertEqual(ctx.obj_path, "")
        self.assertIsNone(ctx.trigger)

    def test_the_omc_prefixed_spellings_are_accepted(self):
        # An older host, or a mode that exports only OMC's own names.
        os.environ["OMC_ACTIONUI_REMOTE_ENDPOINT"] = "/tmp/prefixed.sock"
        os.environ["OMC_ACTIONUI_WINDOW_UUID"] = "W-prefixed"
        ctx = omc.context()
        self.assertEqual(ctx.endpoint, "/tmp/prefixed.sock")
        self.assertEqual(ctx.window_uuid, "W-prefixed")

    def test_the_unprefixed_spelling_wins_when_both_are_set(self):
        os.environ["ACTIONUI_REMOTE_ENDPOINT"] = "/tmp/plain.sock"
        os.environ["OMC_ACTIONUI_REMOTE_ENDPOINT"] = "/tmp/prefixed.sock"
        self.assertEqual(omc.context().endpoint, "/tmp/plain.sock")

    def test_an_empty_variable_falls_through_to_the_other_spelling(self):
        os.environ["ACTIONUI_REMOTE_ENDPOINT"] = ""
        os.environ["OMC_ACTIONUI_REMOTE_ENDPOINT"] = "/tmp/prefixed.sock"
        self.assertEqual(omc.context().endpoint, "/tmp/prefixed.sock")


class TriggerTests(OMCTestBase):

    def test_trigger_with_json_object_context(self):
        os.environ["OMC_ACTIONUI_TRIGGER_VIEW_ID"] = "42"
        os.environ["OMC_ACTIONUI_TRIGGER_VIEW_PART_ID"] = "3"
        os.environ["OMC_ACTIONUI_TRIGGER_CONTEXT"] = '{"row": 3, "name": "x"}'
        trigger = omc.context().trigger
        self.assertEqual(trigger.view_id, 42)
        self.assertEqual(trigger.view_part_id, 3)
        self.assertEqual(trigger.context, {"row": 3, "name": "x"})

    def test_trigger_with_number_context(self):
        os.environ["OMC_ACTIONUI_TRIGGER_VIEW_ID"] = "7"
        os.environ["OMC_ACTIONUI_TRIGGER_CONTEXT"] = "12"
        self.assertEqual(omc.context().trigger.context, 12)

    def test_trigger_with_plain_string_context_is_left_alone(self):
        os.environ["OMC_ACTIONUI_TRIGGER_VIEW_ID"] = "7"
        os.environ["OMC_ACTIONUI_TRIGGER_CONTEXT"] = "not json {"
        self.assertEqual(omc.context().trigger.context, "not json {")

    def test_trigger_without_context_payload(self):
        os.environ["OMC_ACTIONUI_TRIGGER_VIEW_ID"] = "7"
        trigger = omc.context().trigger
        self.assertEqual(trigger.view_id, 7)
        self.assertIsNone(trigger.context)
        self.assertIsNone(trigger.view_part_id)

    def test_the_raw_payload_survives_the_lossy_decode(self):
        # "42" decodes to the integer 42 and "null" to None, which is indistinguishable from no
        # payload at all. A handler that needs the literal text has to be able to get it back.
        os.environ["OMC_ACTIONUI_TRIGGER_VIEW_ID"] = "7"
        os.environ["OMC_ACTIONUI_TRIGGER_CONTEXT"] = "42"
        trigger = omc.context().trigger
        self.assertEqual(trigger.context, 42)
        self.assertEqual(trigger.raw, "42")

        os.environ["OMC_ACTIONUI_TRIGGER_CONTEXT"] = "null"
        trigger = omc.context().trigger
        self.assertIsNone(trigger.context)
        self.assertEqual(trigger.raw, "null", "'null' and 'no payload' must stay distinguishable")

    def test_no_trigger_when_not_dispatched_from_a_control(self):
        os.environ["OMC_ACTIONUI_TRIGGER_CONTEXT"] = '{"stale": true}'
        self.assertIsNone(omc.context().trigger,
                          "the view id is what says a control fired, not the payload")


class SnapshotTests(OMCTestBase):

    def test_view_and_table_snapshots(self):
        os.environ["OMC_ACTIONUI_VIEW_101_VALUE"] = "typed text"
        os.environ["OMC_ACTIONUI_TABLE_5_COLUMN_1_VALUE"] = "cell"
        os.environ["OMC_ACTIONUI_TABLE_5_COLUMN_1_ALL_ROWS"] = "a\nb\nc"
        ctx = omc.context()
        self.assertEqual(ctx.view_value(101), "typed text")
        self.assertEqual(ctx.table_value(5, 1), "cell")
        self.assertEqual(ctx.table_all_rows(5, 1), "a\nb\nc")

    def test_absent_snapshots_are_none(self):
        ctx = omc.context()
        self.assertIsNone(ctx.view_value(999))
        self.assertIsNone(ctx.table_value(9, 9))
        self.assertIsNone(ctx.table_all_rows(9, 9))


class WindowResolutionTests(OMCTestBase):

    def test_no_endpoint_names_the_reason(self):
        os.environ["ACTIONUI_WINDOW_UUID"] = "W-1"
        with self.assertRaises(omc.OMCError) as caught:
            omc.window()
        self.assertIn("ACTIONUI_REMOTE_ENDPOINT", str(caught.exception))

    def test_no_window_uuid_names_the_reason(self):
        os.environ["ACTIONUI_REMOTE_ENDPOINT"] = "/tmp/nothing.sock"
        with self.assertRaises(omc.OMCError) as caught:
            omc.window()
        self.assertIn("ACTIONUI_WINDOW_UUID", str(caught.exception))

    def test_window_is_an_actionui_window_for_the_environments_uuid(self):
        _, window_uuid = self.start_fake_host()
        win = omc.window()
        self.addCleanup(win.connection.close)
        self.assertIsInstance(win, omc.OMCWindow)
        self.assertIsInstance(win, actionui_remote.Window)
        self.assertEqual(win.uuid, window_uuid)


class BridgeVerbTests(OMCTestBase):
    """ActionUI verbs must travel over the socket, not through a tool."""

    def test_reads_and_writes_reach_the_server(self):
        self.start_fake_host()
        win = omc.window()
        self.addCleanup(win.connection.close)

        win.set_value(101, 0, "hello")
        self.assertEqual(win.get_value(101), "hello")
        win.set_rows(5, [["a", "b"]])
        self.assertEqual(win.get_rows(5), [["a", "b"]])

        methods = self.logged_methods()
        self.assertIn("actionui.setValue", methods)
        self.assertIn("actionui.getValue", methods)
        self.assertIn("actionui.setRows", methods)
        self.assertIn("actionui.getRows", methods)

    def test_bridge_verbs_never_shell_out(self):
        self.start_fake_host()
        record = self.make_stub_tool("omc_dialog_control")
        win = omc.window()
        self.addCleanup(win.connection.close)

        win.set_value(101, 0, "over the socket")
        self.assertEqual(win.get_value(101), "over the socket")

        # Both halves. Without the first, a no-op override of set_value/get_value would satisfy
        # the second and the test would prove only that nothing happened at all.
        methods = self.logged_methods()
        self.assertIn("actionui.setValue", methods)
        self.assertIn("actionui.getValue", methods)
        self.assertEqual(self.recorded_argv(record), [],
                         "ActionUI verbs must not invoke omc_dialog_control")


class OMCVerbTests(OMCTestBase):
    """OMC verbs must invoke omc_dialog_control with a shell handler's exact argv."""

    def setUp(self):
        super().setUp()
        self.server, self.window_uuid = self.start_fake_host()
        self.record = self.make_stub_tool("omc_dialog_control")
        self.win = omc.window()
        self.addCleanup(self.win.connection.close)

    def test_terminate_ok_and_cancel(self):
        self.win.terminate_ok()
        self.win.terminate_cancel()
        self.assertEqual(self.recorded_argv(self.record), [
            [self.window_uuid, "omc_window", "omc_terminate_ok"],
            [self.window_uuid, "omc_window", "omc_terminate_cancel"],
        ])

    def test_window_placement_and_selection(self):
        self.win.bring_to_front()
        self.win.activate_app()
        self.win.resize(800, 600)
        self.win.move(10, 20)
        self.assertEqual(self.recorded_argv(self.record), [
            [self.window_uuid, "omc_window", "omc_select"],
            [self.window_uuid, "omc_application", "omc_select"],
            [self.window_uuid, "omc_window", "omc_resize", "800", "600"],
            [self.window_uuid, "omc_window", "omc_move", "10", "20"],
        ])

    def test_a_title_that_is_an_instruction_word_is_not_executed(self):
        """omc_dialog_control reads argv[3] as an instruction when it matches one exactly, so the
        three-argument form would CLOSE the dialog for this title rather than display it."""
        self.win.set_title("omc_terminate_cancel")
        self.win.set_title("omc_select")
        self.assertEqual(self.recorded_argv(self.record), [
            [self.window_uuid, "omc_window", "plain", "omc_terminate_cancel"],
            [self.window_uuid, "omc_window", "plain", "omc_select"],
        ], "a colliding title must go through the four-argument form")

    def test_an_ordinary_title_uses_the_plain_form(self):
        # Byte for byte the argv a shell handler writes; the escape above is not the normal path.
        self.win.set_title("Results for 2026")
        self.assertEqual(self.recorded_argv(self.record),
                         [[self.window_uuid, "omc_window", "Results for 2026"]])

    def test_control_verbs_target_the_control_not_the_window(self):
        self.win.set_command_id(101, "MyApp.next")
        self.win.select_control(101)
        self.assertEqual(self.recorded_argv(self.record), [
            [self.window_uuid, "101", "omc_set_command_id", "MyApp.next"],
            [self.window_uuid, "101", "omc_select"],
        ])

    def test_omc_verbs_never_reach_the_bridge(self):
        self.win.terminate_ok()
        self.win.resize(100, 100)
        # Flatly empty, not "contains no omc.* entries": the loop form never executed its body,
        # since these verbs send nothing and the connection is lazy, so it asserted nothing at
        # all. As written, re-implementing a verb as any actionui.* call fails here.
        self.assertEqual(self.logged_methods(), [],
                         "OMC verbs must not send anything over the bridge")
        self.assertEqual(len(self.recorded_argv(self.record)), 2,
                         "and must have gone through the tool instead")


class ToolFailureTests(OMCTestBase):

    def test_a_failing_tool_raises_with_its_stderr(self):
        self.start_fake_host()
        self.make_stub_tool("omc_dialog_control", exit_code=3, stderr_text="no_such_dialog")
        win = omc.window()
        self.addCleanup(win.connection.close)

        with self.assertRaises(omc.OMCError) as caught:
            win.terminate_ok()
        message = str(caught.exception)
        self.assertIn("omc_dialog_control", message)
        self.assertIn("no_such_dialog", message, "the tool's own diagnosis must survive")

    def test_a_missing_tool_names_the_path(self):
        self.start_fake_host()
        win = omc.window()
        self.addCleanup(win.connection.close)
        os.environ["OMC_OMC_SUPPORT_PATH"] = self.path("nowhere")
        with self.assertRaises(omc.OMCError) as caught:
            win.terminate_ok()
        self.assertIn("omc_dialog_control", str(caught.exception))

    def test_no_support_path_at_all_is_a_clear_error(self):
        self.start_fake_host()
        win = omc.window()
        self.addCleanup(win.connection.close)
        os.environ.pop("OMC_OMC_SUPPORT_PATH", None)
        with self.assertRaises(omc.OMCError) as caught:
            win.terminate_ok()
        self.assertIn("OMC_OMC_SUPPORT_PATH", str(caught.exception))


class NextCommandTests(OMCTestBase):

    def test_next_command_uses_the_current_command_guid(self):
        record = self.make_stub_tool("omc_next_command")
        os.environ["OMC_CURRENT_COMMAND_GUID"] = "GUID-1"
        omc.next_command("MyApp.step2")
        self.assertEqual(self.recorded_argv(record), [["GUID-1", "MyApp.step2"]])

    def test_next_command_accepts_an_explicit_guid(self):
        record = self.make_stub_tool("omc_next_command")
        os.environ["OMC_CURRENT_COMMAND_GUID"] = "GUID-1"
        omc.next_command("MyApp.step2", command_guid="GUID-OTHER")
        self.assertEqual(self.recorded_argv(record), [["GUID-OTHER", "MyApp.step2"]])

    def test_next_command_without_a_guid_is_an_error(self):
        self.make_stub_tool("omc_next_command")
        with self.assertRaises(omc.OMCError) as caught:
            omc.next_command("MyApp.step2")
        self.assertIn("OMC_CURRENT_COMMAND_GUID", str(caught.exception))


class AlertTests(OMCTestBase):

    def test_alert_builds_the_tools_argument_list(self):
        record = self.make_stub_tool("alert")
        omc.alert("Something went wrong.", title="MyApp", level="caution")
        self.assertEqual(self.recorded_argv(record),
                         [["--level", "caution", "--title", "MyApp", "Something went wrong."]])

    def test_alert_message_only(self):
        record = self.make_stub_tool("alert")
        omc.alert("Done.")
        self.assertEqual(self.recorded_argv(record), [["Done."]])


if __name__ == "__main__":
    unittest.main()
