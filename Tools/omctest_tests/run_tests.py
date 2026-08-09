#!/usr/bin/env python3
"""
Self-tests for the omctest applet test harness.

The harness lives (canonically) in the AppletBuilder bundle at
  Distribution/AppletBuilder.app/Contents/Resources/Agents/omctest.sh
and is driven by `appletbuilder test`. This script invokes that shipped copy, so
the self-tests track exactly what ships.

What it does: synthesizes a minimal applet whose handlers exist only to exercise
one contract each, writes shell test files beside it, runs the real
`appletbuilder test` over them, and asserts both on the suite's own report and on
the artifacts the harness left behind.

The point of the shell test files carrying the assertions is that a failure names
itself in the harness's own vocabulary. This script additionally pins the EXACT
pass count of each file, because the failure mode that matters most in test
infrastructure is a check that silently does not run - a green report with fewer
checks than expected is the bug this catches.

Run:   python3 Tools/omctest_tests/run_tests.py
Exit:  0 = all passed, 1 = one or more failures.
"""
from __future__ import annotations

import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
AB = REPO / "Distribution" / "AppletBuilder.app"
CLI = AB / "Contents" / "Resources" / "Agents" / "appletbuilder"
OMCTEST = AB / "Contents" / "Resources" / "Agents" / "omctest.sh"
AB_SUPPORT = AB / "Contents" / "Frameworks" / "Abracode.framework" / "Versions" / "A" / "Support"

# The engine's installed-python candidate chain, in order (OmcExecutor.cp:55-78).
# Used to compute what omc_run SHOULD resolve to on this machine rather than
# hardcoding /usr/bin/python3, which is the last resort and rarely the answer.
PYTHON_CANDIDATES = [
    "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
    "/opt/homebrew/bin/python3",
    "/usr/local/bin/python3",
    "/opt/local/bin/python3",
]

_passed = 0
_failed = 0

# Every CLI invocation gets a TMPDIR this script owns, so the harness's own
# "mktemp -d $TMPDIR/omctest.XXXXXX" lands somewhere nobody else writes. Without
# it the scratch-cleanup assertions are not hermetic: any other omctest run on
# the machine - another developer, a CI job, a second copy of these self-tests -
# puts an omctest.* directory in the shared TMPDIR and the check reports a leak
# that is not ours. Set by main().
_PRIVATE_TMP: Path | None = None


def check(name: str, cond: bool, detail="") -> None:
    global _passed, _failed
    detail = "" if detail is None else str(detail)
    if cond:
        _passed += 1
        print(f"  ok   {name}")
    else:
        _failed += 1
        print(f"  FAIL {name}{(' - ' + detail) if detail else ''}")


def _child_env() -> dict:
    env = dict(os.environ)
    if _PRIVATE_TMP is not None:
        env["TMPDIR"] = str(_PRIVATE_TMP) + "/"
    return env


# Generous, but finite. Without a deadline a harness regression that hangs - a
# restored app-modal alert, a chain drain with no depth limit - stops the suite
# dead with no output, which is what it would also do to "build --test" in a
# release flow. stdin carries data rather than being inherited: with it
# inherited, the "handlers get no terminal on stdin" checks could not fail in the
# one environment that matters, since CI and build --test both hand over
# /dev/null anyway.
_CLI_TIMEOUT = 300


def run_cli(*args: str, timeout: int = _CLI_TIMEOUT):
    try:
        p = subprocess.run([str(CLI), *args], capture_output=True, text=True,
                           env=_child_env(), input="not for the handler\n",
                           timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        return 124, exc.stdout or "", (exc.stderr or "") + f"\nTIMEOUT after {timeout}s"
    return p.returncode, p.stdout, p.stderr


def expected_python() -> str:
    for candidate in PYTHON_CANDIDATES:
        if os.access(candidate, os.X_OK):
            return candidate
    return "/usr/bin/python3"


def suite_counts(stdout: str):
    """Parse the runner's one machine-readable line."""
    m = re.search(r"omctest: (\d+) passed, (\d+) failed, (\d+) files", stdout)
    if not m:
        return None
    return int(m.group(1)), int(m.group(2)), int(m.group(3))


def _write(path: Path, text: str, *, executable: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    if executable:
        path.chmod(0o755)


# --- The fixture applet -------------------------------------------------------

# Every id here is declared in Main.json, so a write to any OTHER id must land in
# unknown_ids.log. 4242 is deliberately absent.
_MAIN_JSON = {
    "type": "VStack",
    "id": 1,
    "children": [
        {"type": "TextField", "id": 130},
        {"type": "Text", "id": 131},
        {"type": "Table", "id": 100},
        {"type": "List", "id": 101},
        {"type": "Button", "id": 10},
        {"type": "Button", "id": 11},
        # Declared control defaults, for omc_control_defaults. Each one is a
        # case the extractor has to get right:
        {"type": "Toggle", "id": 140, "properties": {"isOn": True}},
        # isOn OMITTED - the schema says that means off, and treating it as
        # "no declared value" is the bug this pins down.
        {"type": "Toggle", "id": 141, "properties": {"title": "off by omission"}},
        # A leading section header carries no tag and is never delivered, so
        # the default is the first option that can be.
        {"type": "Picker", "id": 142, "properties": {"options": [
            {"section": "Group"},
            {"title": "First", "tag": "alpha"},
            {"title": "Second", "tag": "beta"},
        ]}},
        # Plain-string options deliver a 1-based index instead of a tag.
        {"type": "Picker", "id": 143, "properties": {"options": ["one", "two"]}},
        {"type": "TextField", "id": 144, "properties": {"text": "typed"}},
        # A prompt is placeholder wording, not a value.
        {"type": "TextField", "id": 145, "properties": {"prompt": "hint only"}},
        # Awkward on purpose: the assignments are eval'd, so a value carrying
        # quotes and a backslash has to survive the round trip intact.
        {"type": "TextField", "id": 146,
         "properties": {"text": "a 'b' \"c\" \\d"}},
    ],
}

# A second document, so the known-ids union covers ids from more than one file -
# which is also the harness's admitted v1 masking limitation.
_SHEET_JSON = {
    "type": "VStack",
    "id": 70,
    "children": [
        {"type": "TextField", "id": 71},
        # Deliberately reuses id 140 with the OPPOSITE default. Ids are unique
        # only within a document, so this is what makes "omc_control_defaults
        # takes one document, never a union" a testable rule rather than a
        # style preference.
        {"type": "Toggle", "id": 140, "properties": {"isOn": False}},
    ],
}

# A third document, shipped unlocalized at the Resources root.
_ROOT_JSON = {
    "type": "VStack",
    "id": 149,
    "children": [{"type": "TextField", "id": 150, "properties": {"text": "rooted"}}],
}

_HANDLERS = {
    # Pushes a value, rows, an enable and a title - the ordinary init shape.
    "Fixture.main.init.sh": r'''
d="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"; u="$OMC_ACTIONUI_WINDOW_UUID"
"$d" "$u" 130 "loaded:$(/usr/bin/basename "${OMC_OBJ_PATH:-none}")"
printf 'alpha\tone\nbeta\ttwo\n' | "$d" "$u" 100 omc_table_set_rows_from_stdin
"$d" "$u" 10 omc_enable
"$d" "$u" 11 omc_disable
"$d" "$u" omc_window "Fixture - Untitled"
exit 0
''',
    # Echoes the whole environment the harness claims to provide.
    "Fixture.env.sh": r'''
out="${TMPDIR}env.txt"
: > "$out"
for name in OMC_APP_BUNDLE_PATH OMC_OMC_SUPPORT_PATH OMC_OMC_RESOURCES_PATH \
            OMC_ACTIONUI_WINDOW_UUID OMC_PARENT_DIALOG_GUID OMC_CURRENT_COMMAND_GUID \
            OMC_NIB_DLG_GUID TMPDIR OMCTEST_WORK OMCTEST_UI OMCTEST_FIXTURES; do
    eval "value=\${$name-<<UNSET>>}"
    printf '%s=%s\n' "$name" "$value" >> "$out"
done
printf 'CWD=%s\n' "$(pwd)" >> "$out"
printf 'PATHHEAD=%s\n' "${PATH%%:*}" >> "$out"
exit 0
''',
    # Reports what event variables it can see, so lifetime is observable.
    "Fixture.event.sh": r'''
out="${TMPDIR}event.txt"
printf 'TRIGGER=%s\nPART=%s\nCONTEXT=%s\nDLG=%s\nVIEW130=%s\nOBJ=%s\n' \
    "${OMC_ACTIONUI_TRIGGER_VIEW_ID-unset}" "${OMC_ACTIONUI_TRIGGER_VIEW_PART_ID-unset}" \
    "${OMC_ACTIONUI_TRIGGER_CONTEXT-unset}" "${OMC_DLG_SAVE_AS_PATH-unset}" \
    "${OMC_ACTIONUI_VIEW_130_VALUE-unset}" "${OMC_OBJ_PATH-unset}" > "$out"
exit 0
''',
    # Two alerts in one run, so the answer QUEUE is observable (one variable
    # cannot express a sequence).
    "Fixture.twoalerts.sh": r'''
"$OMC_OMC_SUPPORT_PATH/alert" --title First "Save changes?"
printf '%s\n' "$?" > "${TMPDIR}rc1.txt"
"$OMC_OMC_SUPPORT_PATH/alert" --title Second "Discard them?"
printf '%s\n' "$?" > "${TMPDIR}rc2.txt"
exit 0
''',
    # A multi-line alert body, the normal shape for a real message.
    "Fixture.longalert.sh": r'''
"$OMC_OMC_SUPPORT_PATH/alert" --title T "Could not save.
The disk is full."
exit 0
''',
    # Empty bodies. The stubs log "$*", so flags would keep the line non-empty -
    # a bare empty message is what actually produces an empty log line.
    "Fixture.emptyalert.sh": r'''
"$OMC_OMC_SUPPORT_PATH/alert" ""
printf '%s\n' "$?" > "${TMPDIR}rc-empty.txt"
exit 0
''',
    "Fixture.emptynotify.sh": r'''
"$OMC_OMC_SUPPORT_PATH/notify" ""
"$OMC_OMC_SUPPORT_PATH/notify" "with text"
exit 0
''',
    "Fixture.chain.a.sh": r'''
printf 'a\n' >> "${TMPDIR}chain.log"
"$OMC_OMC_SUPPORT_PATH/omc_next_command" "$OMC_CURRENT_COMMAND_GUID" "Fixture.chain.b"
exit 0
''',
    # b chains c, so the drain runs a REAL chain and its order is observable.
    # With only one queued command, FIFO and LIFO are indistinguishable.
    "Fixture.chain.c.sh": r'''
printf 'c\n' >> "${TMPDIR}chain.log"
exit 0
''',
    "Fixture.chain.b.sh": r'''
printf 'b\n' >> "${TMPDIR}chain.log"
"$OMC_OMC_SUPPORT_PATH/omc_next_command" "$OMC_CURRENT_COMMAND_GUID" "Fixture.chain.c"
exit 0
''',
    # Two requests in ONE handler: the real tool truncates its single slot, so
    # only the last survives for the engine to dispatch.
    "Fixture.chain.twice.sh": r'''
"$OMC_OMC_SUPPORT_PATH/omc_next_command" "$OMC_CURRENT_COMMAND_GUID" "Fixture.chain.b"
"$OMC_OMC_SUPPORT_PATH/omc_next_command" "$OMC_CURRENT_COMMAND_GUID" "Fixture.chain.c"
exit 0
''',
    # Rows with blank lines, which the tool eats, and an empty ARGUMENT, which it
    # keeps - two different rules the stub has to tell apart.
    "Fixture.blankrows.sh": r'''
d="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"; u="$OMC_ACTIONUI_WINDOW_UUID"
printf 'r1\n\nr3\n\n' | "$d" "$u" 100 omc_table_set_rows_from_stdin
"$d" "$u" 101 omc_table_set_rows a "" b
exit 0
''',
    # A chained handler that fails, so the drain's status is observable.
    "Fixture.chain.fails.sh": r'''
exit 3
''',
    # A deliberately circular chain, to trip the depth limit.
    "Fixture.loop.sh": r'''
"$OMC_OMC_SUPPORT_PATH/omc_next_command" "$OMC_CURRENT_COMMAND_GUID" "Fixture.loop"
exit 0
''',
    # One call per replay verb class.
    "Fixture.verbs.sh": r'''
d="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"; u="$OMC_ACTIONUI_WINDOW_UUID"
"$d" "$u" 100 omc_table_set_columns Name Size
printf 'r1\tx\nr2\ty\nr3\tz\n' | "$d" "$u" 100 omc_table_set_rows_from_stdin
printf 'r4\tw\n' | "$d" "$u" 100 omc_table_add_rows_from_stdin
"$d" "$u" 100 omc_select_row 2
"$d" "$u" 101 omc_list_set_items i1 i2 i3
"$d" "$u" 130 omc_set_value_from_stdin markdown <<'MD'
# heading
MD
"$d" "$u" 131 omc_set_property options '["A","B"]'
"$d" "$u" 131 omc_set_state expanded true
# A key needing sanitization, so the stub's tr set and ui_prop's must agree.
"$d" "$u" 131 omc_set_property "odd key/name" sanitized
# The 2-arg form of set_value_from_stdin: no content type may be recorded.
printf 'plain body' | "$d" "$u" 11 omc_set_value_from_stdin
# Out of range and non-numeric both clear an EXISTING selection, on views of
# their own so they cannot disturb view 100's selection asserted above.
"$d" "$u" 101 omc_select_row 1
"$d" "$u" 101 omc_select_row 99
"$d" "$u" 11 omc_list_set_items only1 only2
"$d" "$u" 11 omc_select_row 0
"$d" "$u" 11 omc_select_row abc
"$d" "$u" 10 omc_show
"$d" "$u" 11 omc_hide
"$d" "$u" omc_window omc_present_alert "Title" "Message" "OK::ok.act" "Cancel:cancel:"
# A missing from_file must NOT truncate the rows.
"$d" "$u" 100 omc_table_set_rows_from_file "${TMPDIR}nosuchfile"
# A journal-only verb changes nothing.
"$d" "$u" 100 omc_resize 400 300
exit 0
''',
    # The engine treats an unmatched word as a VALUE, and argc decides whether
    # the word before it is a content type. Both are easy to get wrong.
    "Fixture.argc.sh": r'''
d="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"; u="$OMC_ACTIONUI_WINDOW_UUID"
printf 'q1\nq2\nq3\n' | "$d" "$u" 100 omc_table_set_rows_from_stdin
# argc == 4: the word IS the value, and on a row-bearing view it destroys rows.
"$d" "$u" 101 omc_list_set_items keep1 keep2
"$d" "$u" 130 mytype
# argc == 5 with an unrecognized word: argv[3] is the content type.
"$d" "$u" 131 mytype "the real value"
# argc == 6: not a content-type call, so the first word is the value.
"$d" "$u" 10 json a b
# argc < 4: the engine refuses and writes NOTHING.
"$d" "$u" 100
printf '%s\n' "$?" > "${TMPDIR}argc3.txt"
# A typo'd verb is a value, not a no-op - it wipes the list.
"$d" "$u" 101 omc_lst_set_items oops
exit 0
''',
    "Fixture.unknownid.sh": r'''
"$OMC_OMC_SUPPORT_PATH/omc_dialog_control" "$OMC_ACTIONUI_WINDOW_UUID" 4242 "typo"
exit 0
''',
    "Fixture.failwrite.sh": r'''
"$OMC_OMC_SUPPORT_PATH/omc_dialog_control" "$OMC_ACTIONUI_WINDOW_UUID" 130 "blocked"
printf '%s\n' "$?" > "${TMPDIR}failrc.txt"
exit 0
''',
    # Writes to both the sheet's own window and the parent's, which is what real
    # child-sheet handlers do.
    "Fixture.sheet.sh": r'''
d="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
"$d" "$OMC_ACTIONUI_WINDOW_UUID" 71 "sheet side"
"$d" "$OMC_PARENT_DIALOG_GUID" 130 "parent side"
exit 0
''',
    "Fixture.exit7.sh": r'''
exit 7
''',
    # Backgrounds work, for omc_wait_for.
    "Fixture.slow.sh": r'''
( /bin/sleep 0.4; printf 'done\n' > "${TMPDIR}slow.txt" ) &
exit 0
''',
    # A bash-4 construct: this MUST fail, because the engine runs .sh under
    # /bin/sh (bash 3.2 POSIX mode) and never under a newer shell.
    "Fixture.whichshell.sh": r'''
# What shell am I? The engine runs .sh under /bin/sh, which on macOS is bash 3.2
# with POSIX mode ON - there is no bash 4/5 here. A syntax-error probe cannot be
# used for this: the bundle validator would reject the applet and the suite would
# never run, which is the validator behaving correctly.
posix_state="$(set -o | /usr/bin/grep '^posix' | /usr/bin/awk '{ print $2 }')"
printf 'VERSION=%s\nPOSIX=%s\n' "${BASH_VERSION:-none}" "${posix_state:-none}" \
    > "${TMPDIR}shell.txt"
exit 0
''',
    "Fixture.readsstdin.sh": r'''
read line
printf '%s\n' "${line:-nothing}" > "${TMPDIR}stdin.txt"
exit 0
''',
    # Deliberately mixed case in the FILE name; the request will be lowercase.
    "Fixture.MixedCase.sh": r'''
printf 'resolved\n' > "${TMPDIR}mixed.txt"
exit 0
''',
}

# A bundle-local module for the probe to import. Importing it is the ONLY thing
# that mints a __pycache__ under the bundle, so without it the "bundle stays
# clean" assertion could not fail however wrong PYTHONPYCACHEPREFIX was.
_PY_MODULE = "MARKER = 'imported'\n"

_PY_HANDLER = r'''
import os, sys, subprocess
sys.path.insert(0, os.path.join(os.environ["OMC_APP_BUNDLE_PATH"], "Contents", "Resources", "Scripts"))
import fixture_helper
out = os.environ["TMPDIR"] + "py.txt"
with open(out, "w") as fh:
    fh.write(sys.executable + "\n")
    fh.write(os.environ.get("PYTHONPYCACHEPREFIX", "") + "\n")
    fh.write(os.environ.get("PATH", "").split(":")[0] + "\n")
subprocess.run([os.path.join(os.environ["OMC_OMC_SUPPORT_PATH"], "omc_dialog_control"),
                os.environ["OMC_ACTIONUI_WINDOW_UUID"], "131", "from python"])
sys.exit(3)
'''


def make_applet(root: Path, *, name: str = "Fixture", broken_manifest: bool = False) -> Path:
    """Synthesize an applet that passes validate_project and exercises the harness."""
    app = root / f"{name}.app"
    contents = app / "Contents"
    res = contents / "Resources"
    (res / "Scripts").mkdir(parents=True, exist_ok=True)
    (res / "Base.lproj").mkdir(parents=True, exist_ok=True)
    (contents / "MacOS").mkdir(parents=True, exist_ok=True)

    info = {
        "CFBundleExecutable": name,
        "CFBundleName": name,
        "CFBundleIdentifier": f"com.test.{name.lower()}",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "14.6",
    }
    # The engine hands handlers the framework's real Resources directory; the
    # fixture needs one to exist or the assertion about it cannot fail.
    (contents / "Frameworks" / "Abracode.framework" / "Versions" / "A" / "Resources").mkdir(
        parents=True, exist_ok=True)
    with open(contents / "Info.plist", "wb") as f:
        plistlib.dump(info, f)
    _write(contents / "MacOS" / name, "#!/bin/sh\n:\n", executable=True)

    command_ids = sorted({h[:-3] for h in _HANDLERS} | {"Fixture.probe"})
    commands = [{
        "NAME": name,
        "COMMAND_ID": "Fixture.main",
        "EXECUTION_MODE": "exe_script_file",
        "ACTIVATION_MODE": "act_always",
        "ACTIONUI_WINDOW": {"JSON_NAME": "Main", "INIT_SUBCOMMAND_ID": "Fixture.main.init"},
    }]
    for cid in command_ids:
        commands.append({
            "NAME": name,
            "COMMAND_ID": cid,
            "EXECUTION_MODE": "exe_script_file",
            "ACTIVATION_MODE": "act_always",
        })
    manifest = "{ this is not json" if broken_manifest else json.dumps(
        {"COMMAND_LIST": commands, "VERSION": 2}, indent=2)
    _write(res / "Command.json", manifest)

    _write(res / "Base.lproj" / "Main.json", json.dumps(_MAIN_JSON, indent=2))
    _write(res / "Base.lproj" / "Sheet.json", json.dumps(_SHEET_JSON, indent=2))
    # No .lproj at all: the engine resolves JSON_NAME through pathForResource,
    # which finds this, so the harness has to as well.
    _write(res / "RootLevel.json", json.dumps(_ROOT_JSON, indent=2))

    for filename, body in _HANDLERS.items():
        _write(res / "Scripts" / filename, body.lstrip("\n"))
    _write(res / "Scripts" / "Fixture.probe.py", _PY_HANDLER.lstrip("\n"))
    _write(res / "Scripts" / "fixture_helper.py", _PY_MODULE)

    # The applet's OWN tools, copied from AppletBuilder's framework. The four the
    # harness stubs get replaced anyway; plister and pasteboard stay real.
    support = contents / "Frameworks" / "Abracode.framework" / "Versions" / "A" / "Support"
    support.mkdir(parents=True, exist_ok=True)
    for tool in AB_SUPPORT.iterdir():
        shutil.copy2(tool, support / tool.name)
    return app


# --- The shell test files -----------------------------------------------------
#
# Each is a real omctest test file. The count in EXPECTED_COUNTS is asserted
# exactly, so a check that silently stops running is a failure here.

TEST_FILES: dict[str, str] = {}

TEST_FILES["10-environment.test.sh"] = r'''
#!/bin/sh
. "${OMCTEST_LIB:?}"

section "the mock environment reaches a handler"
omc_run Fixture.env
env_file="${TMPDIR}env.txt"
field() { /usr/bin/awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$env_file"; }
check "app bundle"        "$OMC_APP_BUNDLE_PATH"    "$(field OMC_APP_BUNDLE_PATH)"
check "support dir"       "$OMC_OMC_SUPPORT_PATH"   "$(field OMC_OMC_SUPPORT_PATH)"
check "resources dir is a real directory" "yes"     "$([ -d "$(field OMC_OMC_RESOURCES_PATH)" ] && echo yes || echo no)"
check "window uuid"       "$OMC_ACTIONUI_WINDOW_UUID" "$(field OMC_ACTIONUI_WINDOW_UUID)"
# Exported AND empty, not merely absent - "$(field X)" cannot tell those apart
# without the <<UNSET>> sentinel the probe now emits.
check "parent guid exported empty" ""               "$(field OMC_PARENT_DIALOG_GUID)"
check "command guid"      "OMCTEST-CMD"             "$(field OMC_CURRENT_COMMAND_GUID)"
check "nib guid exported empty"   ""               "$(field OMC_NIB_DLG_GUID)"
check "TMPDIR is ours"    "$TMPDIR"                 "$(field TMPDIR)"
check "TMPDIR keeps its trailing slash" "yes"       "$(case "$TMPDIR" in (*/) echo yes ;; (*) echo no ;; esac)"
check "TMPDIR is in the scratch" "yes"              "$(case "$TMPDIR" in ("$OMCTEST_SCRATCH"/*) echo yes ;; (*) echo no ;; esac)"
check "handlers run from the work dir" "$(cd "$OMCTEST_WORK" && /bin/pwd -P)" "$(cd "$(field CWD)" && /bin/pwd -P)"
check "fixtures dir exported" "$OMCTEST_FIXTURES"   "$(field OMCTEST_FIXTURES)"

section "the window uuid is unique per run"
check "it embeds a pid" "yes" "$(case "$OMC_ACTIONUI_WINDOW_UUID" in (OMCTEST-10-environment-*[0-9]) echo yes ;; (*) echo no ;; esac)"

omctest_end
'''

TEST_FILES["20-lifetime.test.sh"] = r'''
#!/bin/sh
. "${OMCTEST_LIB:?}"

section "one-shot variables are cleared, current ones persist"
omc_object "$OMCTEST_WORK/doc.txt"
omc_control 130 "typed"
omc_trigger 130 2 '{"k":1}'
omc_dialog_answer save_as "$OMCTEST_WORK/Saved.txt"
omc_run Fixture.event
e() { /usr/bin/awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "${TMPDIR}event.txt"; }
check "the handler saw the trigger" "130"                    "$(e TRIGGER)"
check "and the part id"             "2"                      "$(e PART)"
check "and the context"             '{"k":1}'                "$(e CONTEXT)"
check "and the dialog answer"       "$OMCTEST_WORK/Saved.txt" "$(e DLG)"
check "and the control value"       "typed"                  "$(e VIEW130)"
check "and the object"              "$OMCTEST_WORK/doc.txt"  "$(e OBJ)"
# After the run: event data gone, current state kept.
check "trigger cleared"             ""                       "${OMC_ACTIONUI_TRIGGER_VIEW_ID-}"
check "part cleared"                ""                       "${OMC_ACTIONUI_TRIGGER_VIEW_PART_ID-}"
check "context cleared"             ""                       "${OMC_ACTIONUI_TRIGGER_CONTEXT-}"
check "dialog answer cleared"       ""                       "${OMC_DLG_SAVE_AS_PATH-}"
check "control value persists"      "typed"                  "$OMC_ACTIONUI_VIEW_130_VALUE"
check "object persists"             "$OMCTEST_WORK/doc.txt"  "$OMC_OBJ_PATH"

section "a run that could not dispatch clears them too"
omc_dialog_answer save_as "$OMCTEST_WORK/Armed.txt"
omc_run Fixture.nosuchhandler 2>/dev/null
check_status "reported 127" 127
check "and did not leave the answer armed" "" "${OMC_DLG_SAVE_AS_PATH-}"

section "the derived dialog family"
omc_dialog_answer save_as "$OMCTEST_WORK/My Doc.tar.gz"
check "path"              "$OMCTEST_WORK/My Doc.tar.gz" "$OMC_DLG_SAVE_AS_PATH"
check "parent"            "$OMCTEST_WORK"               "$OMC_DLG_SAVE_AS_PARENT_PATH"
check "name"              "My Doc.tar.gz"               "$OMC_DLG_SAVE_AS_NAME"
check "name no extension" "My Doc.tar"                  "$OMC_DLG_SAVE_AS_NAME_NO_EXTENSION"
check "extension only"    "gz"                          "$OMC_DLG_SAVE_AS_EXTENSION_ONLY"
omc_dialog_answer save_as ""
check "an empty answer unsets the family" "" "${OMC_DLG_SAVE_AS_PATH-}"
check "and the name with it"              "" "${OMC_DLG_SAVE_AS_NAME-}"
omc_dialog_answer input_text "typed text"
check "input_text is its own channel" "typed text" "$OMC_DLG_INPUT_TEXT"

section "a dotfile has no extension"
omc_object "$OMCTEST_WORK/.zshrc"
check "stem is the whole name" ".zshrc" "$OMC_OBJ_NAME_NO_EXTENSION"
check "and there is no extension" ""     "${OMC_OBJ_EXTENSION_ONLY-}"

section "the derived object family"
omc_object "$OMCTEST_WORK/My Doc.tar.gz"
check "obj path"            "$OMCTEST_WORK/My Doc.tar.gz" "$OMC_OBJ_PATH"
check "obj parent"          "$OMCTEST_WORK"               "$OMC_OBJ_PARENT_PATH"
check "obj name"            "My Doc.tar.gz"               "$OMC_OBJ_NAME"
check "obj stem"            "My Doc.tar"                  "$OMC_OBJ_NAME_NO_EXTENSION"
check "obj extension"       "gz"                          "$OMC_OBJ_EXTENSION_ONLY"
check "obj path no extension" "$OMCTEST_WORK/My Doc.tar"  "$OMC_OBJ_PATH_NO_EXTENSION"
check "obj display name"    "My Doc.tar.gz"               "$OMC_OBJ_DISPLAY_NAME"

section "table cells"
omc_table_cell 100 1 "col one"
omc_table_cell 100 0 "whole	row"
check "a column value is set" "col one"    "$OMC_ACTIONUI_TABLE_100_COLUMN_1_VALUE"
check "column 0 is the whole row" "whole	row" "$OMC_ACTIONUI_TABLE_100_COLUMN_0_VALUE"

section "explicit resets"
omc_control 130 "x"
omc_table_cell 100 1 "cell"
omc_reset_controls
check "view value cleared" "" "${OMC_ACTIONUI_VIEW_130_VALUE-}"
check "table cell cleared" "" "${OMC_ACTIONUI_TABLE_100_COLUMN_1_VALUE-}"
omc_object ""
check "object cleared"     "" "$OMC_OBJ_PATH"

omctest_end
'''

TEST_FILES["30-omcrun.test.sh"] = r'''
#!/bin/sh
. "${OMCTEST_LIB:?}"

section "dispatch mirrors the engine"
omc_run fixture.mixedcase
check_status "resolution is case-insensitive" 0
check "and it ran"      "resolved"  "$(/bin/cat "${TMPDIR}mixed.txt" 2>/dev/null)"

# If this is not /bin/sh, every test in every suite is measuring the wrong
# thing: a handler that works here would die under the engine.
omc_run Fixture.whichshell
sh_field() { /usr/bin/awk -F= -v k="$1" '$1 == k { print $2; exit }' "${TMPDIR}shell.txt"; }
check "handlers run under bash 3.2"  "3.2"  "$(sh_field VERSION | /usr/bin/cut -d. -f1,2)"
check "with POSIX mode on"           "on"   "$(sh_field POSIX)"

section "a python handler"
omc_run Fixture.probe
check_status "its exit code is carried" 3
py_line() { /usr/bin/sed -n "$1p" "${TMPDIR}py.txt"; }
check "pycache is inside the scratch" "$OMCTEST_SCRATCH/pyc" "$(py_line 2)"
check "no pycache under the bundle"   "0" "$(/usr/bin/find "$OMC_APP_BUNDLE_PATH" -name '__pycache__' 2>/dev/null | /usr/bin/grep -c . | /usr/bin/tr -d ' ')"
check "python reached the stub"       "from python" "$(ui_value 131)"

section "handler output is captured"
check "the log has a header" "1" "$(/usr/bin/grep -c -- '^-- Fixture.probe --' "$OMCTEST_UI/handlers.log" | /usr/bin/tr -d ' ')"

section "a handler gets no terminal on stdin"
omc_run Fixture.readsstdin
check_status "it did not hang" 0
check "and read nothing"  "nothing" "$(/bin/cat "${TMPDIR}stdin.txt" 2>/dev/null)"

section "omc_wait_for"
omc_run Fixture.slow
omc_wait_for "[ -f \"${TMPDIR}slow.txt\" ]" 4
check "the predicate came true" "yes" "$([ -f "${TMPDIR}slow.txt" ] && echo yes || echo no)"
omc_wait_for "[ -f \"${TMPDIR}never\" ]" 1
check "and a timeout returns 1" "1" "$?"

omctest_end
'''

TEST_FILES["40-alerts.test.sh"] = r'''
#!/bin/sh
. "${OMCTEST_LIB:?}"

section "the alert stub answers and records"
alerts_reset
check "nothing raised yet" "0" "$(alerts_count)"
omc_run Fixture.twoalerts
check "both were recorded" "2" "$(alerts_count)"
check "the first is named"  "1" "$(alerts_mention 'Save changes')"
check "the second too"      "1" "$(alerts_mention 'Discard them')"
check "the default answer is OK" "0" "$(/bin/cat "${TMPDIR}rc1.txt")"

section "a queue scripts a SEQUENCE within one run"
alerts_reset
alert_answer 1 3
omc_run Fixture.twoalerts
check "first answer popped"  "1" "$(/bin/cat "${TMPDIR}rc1.txt")"
check "second answer popped" "3" "$(/bin/cat "${TMPDIR}rc2.txt")"

section "the documented error value reaches the shell as 255"
alerts_reset
alert_answer -1
omc_run Fixture.twoalerts
check "-1 is normalized" "255" "$(/bin/cat "${TMPDIR}rc1.txt")"
check "and the queue is empty again, so the default returns" "0" "$(/bin/cat "${TMPDIR}rc2.txt")"

section "one multi-line alert is one alert"
alerts_reset
omc_run Fixture.longalert
check "counted once"            "1" "$(alerts_count)"
check "and matched across the break" "1" "$(alerts_mention 'Could not save. The disk is full')"

section "an unconsumed answer does not leak into the next section"
# alerts_reset truncates the LOG, not the QUEUE. A scripted answer the handler
# never reached would otherwise answer the next alert.
alert_answer 2
alerts_reset
alert_answers_reset
omc_run Fixture.emptyalert
check "the leftover 2 was discarded" "0" "$(/bin/cat "${TMPDIR}rc-empty.txt" 2>/dev/null)"

section "an alert with no text is still an alert"
check "counted" "1" "$(alerts_count)"

section "and so is a notification with no text"
# notify_count and alerts_count are the same helper for two tools. This one used
# to count non-empty lines only, so an empty-bodied notification vanished - the
# defect alerts_count was fixed for, missed here.
omc_run Fixture.emptynotify
check "both counted"              "2" "$(notify_count)"
check "the one with text matches" "1" "$(notify_mention 'with text')"

section "alerts_reset clears"
alerts_reset
check "back to zero" "0" "$(alerts_count)"

omctest_end
'''

TEST_FILES["50-chain.test.sh"] = r'''
#!/bin/sh
. "${OMCTEST_LIB:?}"

section "omc_next_command queues rather than running"
omc_run Fixture.chain.a
check "the request was recorded" "1"  "$(chain_requested Fixture.chain.b)"
check "but b has not run"        "a"  "$(/usr/bin/tr -d '\n' < "${TMPDIR}chain.log")"
# A regex that WOULD match, so removing grep -F flips this.
check "a literal id, not a pattern" "0" "$(chain_requested 'F.xture.chain.b')"

section "draining runs it, in order"
omc_drain_chain
check "the whole chain ran, in order" "abc" "$(/usr/bin/tr -d '\n' < "${TMPDIR}chain.log")"
check "and the queue is empty" "0" "$(chain_requested Fixture.chain.c)"

section "omc_next_command is one slot, not a queue"
# The real tool does fopen(path, "w") - it truncates. Two requests in one handler
# therefore leave only the LAST for the engine, and a harness that queued both
# would run a command the engine had already discarded.
: > "${TMPDIR}chain.log"
asked_b_before="$(chain_asked Fixture.chain.b)"
omc_run Fixture.chain.twice
asked_b_after="$(chain_asked Fixture.chain.b)"
check "only the last request is pending" "0" "$(chain_requested Fixture.chain.b)"
check "and it is the one that survives"  "1" "$(chain_requested Fixture.chain.c)"
check "but the history recorded the overwritten ask" "1" "$((asked_b_after - asked_b_before))"
omc_drain_chain
check "so only c ran"                    "c" "$(/usr/bin/tr -d '\n' < "${TMPDIR}chain.log")"

section "a failing link is not swallowed"
omc_run Fixture.chain.a
# Redirect the queue at the failing handler by asking for it directly.
"$OMC_OMC_SUPPORT_PATH/omc_next_command" "$OMC_CURRENT_COMMAND_GUID" "Fixture.chain.fails"
omc_drain_chain
check "the drain reports the failure" "3" "$?"

section "a circular chain is a named failure, not a hung run"
omc_run Fixture.loop
omc_drain_chain 5 2>/dev/null
check "drain refused" "1" "$?"

omctest_end
'''

TEST_FILES["55-defaults.test.sh"] = r'''
#!/bin/sh
# omc_control_defaults, and chains_reset.
. "$OMCTEST_LIB"

section "the API version says the feature is here"
check "api is at least 2" "yes" \
    "$([ "${OMCTEST_API_VERSION:-0}" -ge 2 ] && echo yes || echo no)"

section "declared defaults are applied"
omc_control_defaults Main
check "a toggle that ships on"                    "true"  "$OMC_ACTIONUI_VIEW_140_VALUE"
check "a toggle that ships off by omission"       "false" "$OMC_ACTIONUI_VIEW_141_VALUE"
check "a picker skips the section header"         "alpha" "$OMC_ACTIONUI_VIEW_142_VALUE"
check "plain-string options give a 1-based index" "1"     "$OMC_ACTIONUI_VIEW_143_VALUE"
check "a text field takes its text"               "typed" "$OMC_ACTIONUI_VIEW_144_VALUE"
check "a prompt is not a value"                   ""      "$OMC_ACTIONUI_VIEW_145_VALUE"
check "quotes and a backslash survive the eval"   "a 'b' \"c\" \\d" \
    "$OMC_ACTIONUI_VIEW_146_VALUE"
check "an element with no declared value is left alone" "" "${OMC_ACTIONUI_VIEW_100_VALUE-}"
check "the count is reported" "yes" \
    "$([ "${OMCTEST_DEFAULTS_APPLIED:-0}" -ge 7 ] && echo yes || echo no)"

section "it resets first, so one call is the whole freshly-opened window"
omc_control 140 "meddled"
omc_control 130 "left over from the last section"
omc_control_defaults Main
check "a meddled control went back to its default" "true" "$OMC_ACTIONUI_VIEW_140_VALUE"
check "and one with no default was cleared"        ""     "${OMC_ACTIONUI_VIEW_130_VALUE-}"

section "each document answers only for itself"
# Sheet.json declares id 140 too, with the opposite default. A union across the
# bundle would let one document answer for the other document's control.
omc_control_defaults Sheet
check "the sheet's own 140 wins"          "false" "$OMC_ACTIONUI_VIEW_140_VALUE"
check "and the main window's 144 is gone" ""      "${OMC_ACTIONUI_VIEW_144_VALUE-}"
omc_control_defaults Main
check "and back again"                    "true"  "$OMC_ACTIONUI_VIEW_140_VALUE"

section "it takes exactly one document, never a list"
# Two documents in one call would let the second one's id 140 overwrite the
# first one's - the same collision the single-document rule exists to prevent,
# just moved up into the API. So the list form is refused outright.
check "two documents are refused"      "1" \
    "$(omc_control_defaults Main Sheet 2>/dev/null; echo $?)"

section "a name that does not exist fails loudly"
check "an unknown document is refused" "1" \
    "$(omc_control_defaults NoSuchDocument 2>/dev/null; echo $?)"
# Outside a substitution again: the point is the variable it leaves behind, and
# a subshell would take that with it.
omc_control_defaults NoSuchDocument 2>/dev/null
check "and so is no argument at all"   "1" \
    "$(omc_control_defaults 2>/dev/null; echo $?)"
# The count must not survive a failed call, or a test asserting only on the
# count would pass for a call that applied nothing.
check "a failed call leaves the count at zero" "0" "${OMCTEST_DEFAULTS_APPLIED:-unset}"

section "the document is found at the Resources root too"
# The engine resolves JSON_NAME through pathForResource, which finds a document
# with no .lproj at all. An unlocalized applet has to work.
# Called OUTSIDE a command substitution on purpose: it exports, and an export
# from inside $( ) dies with the subshell.
omc_control_defaults RootLevel
check "a root-level document is found" "0"       "$?"
check "and its default was applied"    "rooted"  "$OMC_ACTIONUI_VIEW_150_VALUE"

section "chains_reset forgets both the pending slot and the history"
"$OMC_OMC_SUPPORT_PATH/omc_next_command" "$OMC_CURRENT_COMMAND_GUID" Fixture.probe
check "the request was recorded" "1" "$(chain_asked Fixture.probe)"
check "and is pending"           "1" "$(chain_requested Fixture.probe)"
chains_reset
check "the history was cleared"  "0" "$(chain_asked Fixture.probe)"
check "and the pending slot too" "0" "$(chain_requested Fixture.probe)"

omctest_end
'''

TEST_FILES["60-window.test.sh"] = r'''
#!/bin/sh
. "${OMCTEST_LIB:?}"

section "init writes what the window would show"
omc_object "$OMCTEST_WORK/Sample.doc"
omc_run Fixture.main.init
check "value pushed"   "loaded:Sample.doc"  "$(ui_value 130)"
check "rows fed"       "2"                  "$(ui_row_count 100)"
check "first row kept its tab" "alpha	one" "$(ui_rows 100 | /usr/bin/head -n 1)"
check "enabled"        "1"                  "$(ui_enabled 10)"
check "disabled"       "0"                  "$(ui_enabled 11)"
check "untouched is empty" ""               "$(ui_visible 10)"
check "title"          "Fixture - Untitled" "$(ui_title)"
check "no unknown writes" ""                "$(ui_unknown_writes)"

section "the replay verbs"
ui_reset
omc_run Fixture.verbs
check "columns"        "Name Size " "$(ui_columns 100 | /usr/bin/tr '\n' ' ')"
check "rows set then added" "4"    "$(ui_row_count 100)"
check "selection"      "2"         "$(ui_selection 100)"
check "list items"     "3"         "$(ui_row_count 101)"
check "value from stdin" "# heading" "$(ui_value 130)"
check "with its content type" "markdown" "$(ui_content_type 130)"
check "a property"     '["A","B"]' "$(ui_prop 131 options)"
check "a state"        "true"      "$(ui_state 131 expanded)"
check "a key that needs sanitizing" "sanitized" "$(ui_prop 131 'odd key/name')"
check "the 2-arg form records no content type" "" "$(ui_content_type 11)"
check "and still sets the value" "plain body" "$(ui_value 11)"
check "view 100 keeps its valid selection"      "2" "$(ui_selection 100)"
check "an out-of-range row clears the selection" "" "$(ui_selection 101)"
# A non-numeric index is a SILENT NO-OP in the tool, not a clear: its
# one-argument branch is gated on the argument count, so the previous selection
# survives. Reproducing that is the point - the classic handler bug
# "omc_select_row $idx" with $idx empty must test the way it behaves live.
check "a non-numeric index changes nothing" "0" "$(ui_selection 11)"
check "shown"          "1"         "$(ui_visible 10)"
check "hidden"         "0"         "$(ui_visible 11)"
check "the alert title" "Title"    "$(ui_alert_title)"
check "its message"    "Message"   "$(ui_alert_message)"
check "a button actionID" "ok.act" "$(ui_alert_action OK)"
check "a missing from_file did not truncate" "4" "$(ui_row_count 100)"
check "a journal-only verb changed nothing"  "4" "$(ui_row_count 100)"
check "but was journaled" "1" "$(ui_calls omc_resize)"

section "the argument-count rule, as the tool applies it"
ui_reset
omc_run Fixture.argc
check "argc<4 wrote nothing"        "3"   "$(ui_row_count 100)"
check "and reported the refusal"    "255" "$(/bin/cat "${TMPDIR}argc3.txt")"
check "argc==4: the word is the value" "mytype" "$(ui_value 130)"
check "and no content type"         ""    "$(ui_content_type 130)"
check "argc==5: an unrecognized word IS a content type" "mytype" "$(ui_content_type 131)"
check "with argv[4] as the value"   "the real value" "$(ui_value 131)"
check "argc==6 is a plain value"    "json" "$(ui_value 10)"
check "a typo'd verb destroys rows, as the engine does" "1" "$(ui_row_count 101)"
# argc is 5 here, so by the tool's own rule the typo is taken as the content
# type and its argument as the value - which is what lands in the rows.
check "the value is what was written" "oops" "$(ui_value 101)"
check "and the destruction is flagged" "1"  "$(printf '%s' "$(ui_suspect_writes)" | /usr/bin/grep -c 'bare value onto rows')"

section "blank lines follow the tool's two different rules"
ui_reset
omc_run Fixture.blankrows
check "blank lines from stdin are eaten" "2" "$(ui_row_count 100)"
check "and the real rows survive"        "r1" "$(ui_rows 100 | /usr/bin/head -n 1)"
# The argv form keeps an empty argument as an empty row - a different rule, and
# filtering both the same way would be wrong in one direction or the other.
check "an empty ARGUMENT is still a row"  "3" "$(ui_row_count 101)"

section "a window uuid is a token, not a path"
"$OMC_OMC_SUPPORT_PATH/omc_dialog_control" "../../../OMCTEST_ESCAPED" 100 "outside" 2>/dev/null
check "a traversal uuid is refused"      "1" "$(printf '%s' "$(ui_errors)" | /usr/bin/grep -c 'bad window uuid')"
check "and nothing was written outside"  "no" "$([ -e "$OMCTEST_SCRATCH/../OMCTEST_ESCAPED" ] && echo yes || echo no)"

section "writes to an undeclared id are flagged"
ui_reset
omc_run Fixture.unknownid
check "the id is named" "1" "$(printf '%s' "$(ui_unknown_writes)" | /usr/bin/grep -c '^4242 ')"

section "a scripted write failure reaches the handler"
ui_reset
ui_fail 130
omc_run Fixture.failwrite
check "the tool returned 1" "1" "$(/bin/cat "${TMPDIR}failrc.txt")"

section "two windows do not share state"
ui_reset
omc_run Fixture.main.init
first="$OMC_ACTIONUI_WINDOW_UUID"
omc_window_switch second
check "a fresh window is blank" "" "$(ui_value 130)"
check "and the first still has its value" "loaded:Sample.doc" "$(ui_value 130 "$first")"

section "a child sheet addresses both windows"
omc_window_switch parent
omc_run Fixture.main.init
parent_uuid="$OMC_ACTIONUI_WINDOW_UUID"
omc_child_sheet creds
check "the parent guid is set" "$parent_uuid" "$OMC_PARENT_DIALOG_GUID"
omc_run Fixture.sheet
check "the sheet side"  "sheet side"  "$(ui_value 71)"
check "the parent side" "parent side" "$(ui_value 130 "$OMC_PARENT_DIALOG_GUID")"
omc_leave_sheet
check "leaving restores the window" "$parent_uuid" "$OMC_ACTIONUI_WINDOW_UUID"
check "and clears the parent guid" ""             "$OMC_PARENT_DIALOG_GUID"

omctest_end
'''

TEST_FILES["70-tools.test.sh"] = r'''
#!/bin/sh
. "${OMCTEST_LIB:?}"

section "the interposition directory"
check "alert is a stub, not a link"   "no"  "$([ -L "$OMC_OMC_SUPPORT_PATH/alert" ] && echo yes || echo no)"
check "notify too"                    "no"  "$([ -L "$OMC_OMC_SUPPORT_PATH/notify" ] && echo yes || echo no)"
check "omc_dialog_control too"        "no"  "$([ -L "$OMC_OMC_SUPPORT_PATH/omc_dialog_control" ] && echo yes || echo no)"
check "omc_next_command too"          "no"  "$([ -L "$OMC_OMC_SUPPORT_PATH/omc_next_command" ] && echo yes || echo no)"
check "plister is the real tool"      "yes" "$([ -L "$OMC_OMC_SUPPORT_PATH/plister" ] && echo yes || echo no)"
check "pasteboard too"                "yes" "$([ -L "$OMC_OMC_SUPPORT_PATH/pasteboard" ] && echo yes || echo no)"
# The tools come from the APPLET's own framework, not AppletBuilder's.
check "the real tools are the applet's own" "yes" \
    "$(case "$OMCTEST_REAL_SUPPORT" in ("$OMC_APP_BUNDLE_PATH"/*) echo yes ;; (*) echo no ;; esac)"

section "the real plister works"
printf '{}' > "$OMCTEST_WORK/m.json"
"$OMC_OMC_SUPPORT_PATH/plister" insert K string V "$OMCTEST_WORK/m.json" / >/dev/null 2>&1
check "it wrote a value" "V" "$("$OMC_OMC_SUPPORT_PATH/plister" get value "$OMCTEST_WORK/m.json" /K 2>/dev/null)"

section "omc_stub replaces and omc_unstub restores"
omc_stub plister <<'SH'
#!/bin/sh
exit 1
SH
"$OMC_OMC_SUPPORT_PATH/plister" get value "$OMCTEST_WORK/m.json" /K >/dev/null 2>&1
check "the override is in force" "1" "$?"
omc_unstub plister
check "restored as a symlink" "yes" "$([ -L "$OMC_OMC_SUPPORT_PATH/plister" ] && echo yes || echo no)"
check "and it works again"    "V"   "$("$OMC_OMC_SUPPORT_PATH/plister" get value "$OMCTEST_WORK/m.json" /K 2>/dev/null)"
# Restoring one of the four defaults must give back the STUB, never the real
# app-modal binary - that would hang the suite.
omc_unstub alert
check "unstubbing alert keeps a stub" "no" "$([ -L "$OMC_OMC_SUPPORT_PATH/alert" ] && echo yes || echo no)"
alerts_reset
omc_run Fixture.longalert
check "and it still records"          "1"  "$(alerts_count)"

section "the check primitives themselves"
# check_exists / check_absent / check_grep had no coverage at all. Each is
# asserted in BOTH directions, because an inverted check_absent or a check_grep
# that always succeeds would otherwise be invisible.
probe_dir="$OMCTEST_WORK/primitives"
/bin/mkdir -p "$probe_dir"
printf 'hello world\nsecond line\n' > "$probe_dir/there.txt"
check_exists "check_exists finds a file"      "$probe_dir/there.txt"
check_exists "and a directory"                "$probe_dir"
check_absent "check_absent misses a file"     "$probe_dir/not-there.txt"
check_grep   "check_grep finds a pattern"     "second line" "$probe_dir/there.txt"
# The negative halves matter as much as the positive ones - an inverted
# check_absent, or a check_grep that always succeeds, is invisible otherwise. The
# counters are files keyed off $OMCTEST_UI, so pointing that at a scratch
# directory runs these four against a ledger of their own and leaves this file's
# total untouched. Their FAIL lines are expected, so stderr is muted.
saved_ui="$OMCTEST_UI"
OMCTEST_UI="$OMCTEST_WORK/probe-ui"
/bin/mkdir -p "$OMCTEST_UI"
omctest_reset_counts
{
    check_exists "expected to fail: a file that is not there" "$probe_dir/not-there.txt"
    check_absent "expected to fail: a file that is there"     "$probe_dir/there.txt"
    check_grep   "expected to fail: a pattern that is absent" "no such text" "$probe_dir/there.txt"
    check_grep   "expected to fail: a file that is not there" "hello" "$probe_dir/not-there.txt"
} 2>/dev/null
negative_fails="$(omctest_count fail)"
negative_passes="$(omctest_count pass)"
OMCTEST_UI="$saved_ui"
check "all four negatives are counted as failures" "4" "$negative_fails"
check "and none of them as a pass"                 "0" "$negative_passes"

section "fixtures are read-only; copies are writable"
src="$(fixture Sample.txt)"
check "the fixture path resolves" "yes" "$([ -f "$src" ] && echo yes || echo no)"
copy="$(fixture_copy Sample.txt)"
check "the copy is in the work dir" "yes" "$(case "$copy" in ("$OMCTEST_WORK"/*) echo yes ;; (*) echo no ;; esac)"
# Asserted before anything appends to it: the append below CREATES the file, so
# without this every check here passed when fixture_copy copied nothing at all.
check "and it carries the fixture" "fixture" "$(/bin/cat "$copy" 2>/dev/null)"
printf 'changed\n' >> "$copy"
check "the copy is writable"        "yes" "$([ -w "$copy" ] && echo yes || echo no)"
check "the original is untouched"   "fixture" "$(/bin/cat "$src")"
fixture nosuchfixture 2>/dev/null
check "a missing fixture is refused" "1" "$?"

omctest_end
'''

# A file that dies before omctest_end, to prove the runner reports it.
TEST_FILES["80-crash.test.sh"] = r'''
#!/bin/sh
. "${OMCTEST_LIB:?}"
section "this file exits before reporting"
check "one real check ran" "a" "a"
exit 7
'''

# A file that stops partway through with a SUCCESS status. This is the quiet
# truncation - an "exit" in a helper, a handler that takes the shell with it -
# and it is the case a hand-declared check count used to claim to be the only
# guard against. It is not: omctest_end is the only writer of the counts file,
# so the runner sees the file never finished whatever the exit status was.
TEST_FILES["81-truncated.test.sh"] = r'''
#!/bin/sh
. "${OMCTEST_LIB:?}"
section "this file stops early, successfully"
check "one real check ran" "a" "a"
exit 0
check "this one never runs" "a" "a"
omctest_end
'''

# A file that reaches the end having asserted nothing. Green by arithmetic and
# broken in fact.
TEST_FILES["82-empty.test.sh"] = r'''
#!/bin/sh
. "${OMCTEST_LIB:?}"
section "a file with no assertions in it"
omctest_end
'''

# A file that prints to stdout. The counts must not absorb it.
TEST_FILES["85-noise.test.sh"] = r'''
#!/bin/sh
. "${OMCTEST_LIB:?}"
printf 'stray output with no newline'
printf 'and a line\nand another\n'
section "debug output from a test file is normal"
check "a pass" "a" "a"
omctest_end
'''

# Expected pass/fail per file, asserted exactly.
EXPECTED_COUNTS = {
    "10-environment.test.sh": (13, 0),
    "20-lifetime.test.sh": (36, 0),
    "30-omcrun.test.sh": (13, 0),
    "40-alerts.test.sh": (16, 0),
    "50-chain.test.sh": (11, 0),
    "55-defaults.test.sh": (25, 0),
    "60-window.test.sh": (54, 0),
    "70-tools.test.sh": (25, 0),
    "85-noise.test.sh": (1, 0),
}


def write_tests(project: Path, names=None) -> Path:
    tests = project / "Tests"
    (tests / "fixtures").mkdir(parents=True, exist_ok=True)
    _write(tests / "fixtures" / "Sample.txt", "fixture")
    (tests / "fixtures" / "Sample.txt").chmod(0o444)
    for filename, body in TEST_FILES.items():
        if names is not None and filename not in names:
            continue
        _write(tests / filename, body.lstrip("\n"))
    return tests


# --- Tests --------------------------------------------------------------------

def test_hygiene() -> None:
    print("Hygiene:")
    p = subprocess.run(["/bin/sh", "-n", str(OMCTEST)], capture_output=True, text=True)
    check("omctest.sh passes /bin/sh -n", p.returncode == 0, p.stderr.strip())
    # scan_bash4_isms, with a canary first: an empty result from a scanner that
    # failed to load is indistinguishable from a clean scan.
    driver = (
        f'export OMC_APP_BUNDLE_PATH="{AB}"\n'
        f'source "{AB}/Contents/Resources/Scripts/lib.validate.sh" || exit 9\n'
        'printf "declare -A x\\n" > "$1/canary.sh"\n'
        '[ -n "$(scan_bash4_isms "$1/canary.sh")" ] || exit 8\n'
        f'scan_bash4_isms "{OMCTEST}"\n'
    )
    with tempfile.TemporaryDirectory() as td:
        p = subprocess.run(["/bin/bash", "-c", driver, "bash", td],
                           capture_output=True, text=True)
    check("the bash4 scanner is live", p.returncode not in (8, 9),
          "canary did not trip" if p.returncode == 8 else "lib.validate.sh failed to load")
    check("omctest.sh has no bash 4 constructs", p.returncode == 0 and not p.stdout.strip(),
          p.stdout.strip())
    p = subprocess.run(["/bin/bash", "-n", str(CLI)], capture_output=True, text=True)
    check("appletbuilder passes bash -n", p.returncode == 0, p.stderr.strip())


def test_emitted_stubs() -> None:
    print("Emitted stubs:")
    with tempfile.TemporaryDirectory() as td:
        driver = (
            f'OMCTEST_RUNNER=1 . "{OMCTEST}"\n'
            'for t in alert notify omc_dialog_control omc_next_command; do\n'
            f'  omctest_emit_stub_"$t" > "{td}/$t" || exit 1\n'
            'done\n'
        )
        p = subprocess.run(["/bin/sh", "-c", driver], capture_output=True, text=True)
        check("all four stubs were emitted", p.returncode == 0, p.stderr.strip())
        for tool in ("alert", "notify", "omc_dialog_control", "omc_next_command"):
            path = Path(td) / tool
            q = subprocess.run(["/bin/sh", "-n", str(path)], capture_output=True, text=True)
            check(f"{tool} stub passes /bin/sh -n", q.returncode == 0, q.stderr.strip())
            body = path.read_text()
            # Single-quoted here-doc delimiters mean nothing expanded at emit
            # time: the variables must still be there as text.
            check(f"{tool} stub expanded nothing at emit time",
                  "$OMCTEST_UI" in body, body[:120])


def test_usage_and_list(project: Path, app: Path) -> None:
    print("Usage, --list and --filter:")
    rc, out, err = run_cli("test")
    check("no bundle -> exit 2", rc == 2, f"got {rc}")
    rc, out, err = run_cli("test", str(project / "NoSuch.app"))
    check("a path that is not a bundle -> exit 2", rc == 2, f"got {rc}")
    rc, out, err = run_cli("test", str(app), "--tests", str(project / "NoTests"))
    check("a missing tests dir -> exit 2", rc == 2, f"got {rc}")
    rc, out, err = run_cli("test", str(app), "--list")
    listed = [Path(line).name for line in out.strip().splitlines() if line.strip()]
    check("--list -> exit 0", rc == 0, f"got {rc}")
    check("--list names every test file", listed == sorted(TEST_FILES), str(listed))
    check("--list prints nothing but paths", all(x.endswith(".test.sh") for x in listed))
    rc, out, err = run_cli("test", str(app), "--list", "--filter", "4*")
    check("--filter narrows the list", [Path(x).name for x in out.split()] == ["40-alerts.test.sh"],
          out.strip())
    rc, out, err = run_cli("test", str(app), "--list", "--filter", "zz*")
    check("--filter matching nothing -> exit 2", rc == 2, f"got {rc}")
    check("even with --list, which never runs anything", "no test files matched" in err)


def test_validation_gate(project: Path) -> None:
    print("Validation gate:")
    broken = make_applet(project / "broken", name="Fixture", broken_manifest=True)
    write_tests(project / "broken", names={"85-noise.test.sh"})
    rc, out, err = run_cli("test", str(broken))
    check("a malformed manifest aborts -> exit 1", rc == 1, f"got {rc}")
    check("and says so", "validation failed" in err)
    check("and no test ran", suite_counts(out) is None, out.strip())


def test_suite(app: Path) -> None:
    print("The suite:")
    rc, out, err = run_cli("test", str(app))
    counts = suite_counts(out)
    check("the summary line is on stdout", counts is not None, out.strip()[:200])
    if counts is None:
        return
    total_pass, total_fail, files = counts
    expected_pass = sum(p for p, _ in EXPECTED_COUNTS.values())
    check("a crashed file is reported", "CRASH 80-crash.test.sh (exit 7)" in err,
          [l for l in err.splitlines() if "CRASH" in l])
    # A file that stopped early with a SUCCESS status is the one worth naming
    # apart: "CRASH (exit 0)" reads like a contradiction, and this is the shape
    # that used to be argued for a hand-declared check count. No count is
    # declared anywhere in this suite and it is caught anyway.
    check("a file that stopped early with exit 0 is named for it",
          "INCOMPLETE 81-truncated.test.sh" in err,
          [l for l in err.splitlines() if "INCOMPLETE" in l or "81-truncated" in l])
    check("and it is not called a crash",
          "CRASH 81-truncated" not in err,
          [l for l in err.splitlines() if "81-truncated" in l])
    check("the check it did run is not reported as the file's result",
          "-- 1 passed, 0 failed --" not in _stderr_block(err, "81-truncated.test.sh"),
          _stderr_block(err, "81-truncated.test.sh").strip()[-200:])
    # A file that asserts nothing is broken, not passing.
    check("a file that ran no checks fails",
          "FAIL this file ran no checks at all" in _stderr_block(err, "82-empty.test.sh"),
          _stderr_block(err, "82-empty.test.sh").strip()[-200:])
    check("and counted as a failure", total_fail == 3, f"failed={total_fail}")
    check("the run exits 1 because of it", rc == 1, f"got {rc}")
    check("every file was run", files == len(TEST_FILES), f"files={files}")
    # The exact total is the point: a check that silently stops running shows up
    # here and nowhere else.
    check(f"the pass total is exactly {expected_pass}", total_pass == expected_pass,
          f"got {total_pass}")
    # 82-empty is the one file expected to produce a FAIL line.
    unexpected = [l for l in err.splitlines()
                  if l.startswith("FAIL ") and "ran no checks at all" not in l]
    check("no file reported an unexpected failing check", not unexpected, unexpected[:6])
    # Per-file, so a shortfall names the file.
    for name, (want_pass, _) in EXPECTED_COUNTS.items():
        block = _stderr_block(err, name)
        got = block.count("\nok   ") + (1 if block.startswith("ok   ") else 0)
        check(f"{name} ran {want_pass} checks", got == want_pass, f"got {got}")
    check("sections are grouped on stderr", "== the mock environment reaches a handler ==" in err)
    # The noise file printed to stdout. Two things must be true and they are
    # different things: its own count is 1 (the leak was not parsed as part of
    # the number), and the leaked text is nowhere on the runner's stdout, which
    # is reserved for the one machine-readable line.
    check("a test file's stray stdout stays off the runner's stdout",
          "stray output with no newline" not in out, out.strip()[:200])
    check("and stdout carries only the summary line",
          out.strip().count("\n") == 0, out.strip()[:200])


def _stderr_block(err: str, filename: str) -> str:
    """The stderr between this file's header and the next file's."""
    marker = f"### {filename}"
    start = err.find(marker)
    if start < 0:
        return ""
    rest = err[start + len(marker):]
    nxt = rest.find("\n### ")
    return rest if nxt < 0 else rest[:nxt]


def test_scratch_and_flags(app: Path) -> None:
    print("Scratch, --verbose and --keep-scratch:")
    before = set(_scratch_dirs())
    rc, out, err = run_cli("test", str(app), "--filter", "50-*")
    after = set(_scratch_dirs())
    check("the scratch is removed after a run", after == before,
          str(sorted(after - before)))

    rc, out, err = run_cli("test", str(app), "--filter", "50-*", "--keep-scratch")
    kept = [l.split("scratch kept at ", 1)[1].strip()
            for l in err.splitlines() if "scratch kept at" in l]
    check("--keep-scratch prints the path", bool(kept), err.strip()[-200:])
    if kept:
        path = Path(kept[-1])
        check("and the directory is still there", path.is_dir(), str(path))
        # Every stub the runner actually emitted must also be sh-clean.
        stubs = list(path.glob("*/support/*"))
        emitted = [s for s in stubs if not s.is_symlink()]
        check("it kept the emitted stubs", len(emitted) >= 4, str([s.name for s in emitted]))
        for stub in emitted:
            q = subprocess.run(["/bin/sh", "-n", str(stub)], capture_output=True, text=True)
            check(f"emitted {stub.name} passes /bin/sh -n", q.returncode == 0, q.stderr.strip())
        shutil.rmtree(path, ignore_errors=True)

    rc, out, err = run_cli("test", str(app), "--filter", "30-*", "--verbose")
    check("--verbose streams handler output", "-- Fixture.probe --" in err)
    rc, out, err = run_cli("test", str(app), "--filter", "30-*")
    check("and does not without it", "-- Fixture.probe --" not in err)


def _scratch_dirs():
    """omctest scratch directories in OUR private TMPDIR only."""
    tmp = _PRIVATE_TMP if _PRIVATE_TMP is not None else Path(os.environ.get("TMPDIR", "/tmp"))
    return [p for p in tmp.glob("omctest.*") if p.is_dir()]


def test_uuid_uniqueness(app: Path) -> None:
    print("Per-run isolation:")
    uuids = []
    for _ in range(2):
        rc, out, err = run_cli("test", str(app), "--filter", "60-*", "--keep-scratch")
        kept = [l.split("scratch kept at ", 1)[1].strip()
                for l in err.splitlines() if "scratch kept at" in l]
        if not kept:
            continue
        path = Path(kept[-1])
        # The window directory name is authoritative: it is keyed off the uuid
        # each omc_dialog_control call actually passed.
        # Only the window keyed off the FILE LABEL. omc_window_switch mints
        # further names from the same pid, and comparing the whole set let the
        # label window collide across runs while the check stayed green.
        wins = sorted(w.name for w in path.glob("*/ui/win-OMCTEST-60-window-*"))
        if wins:
            uuids.append(tuple(wins))
        shutil.rmtree(path, ignore_errors=True)
    check("two runs get different window uuids", len(uuids) == 2 and uuids[0] != uuids[1],
          str(uuids))


def _run_standalone(project: Path, env: dict):
    try:
        return subprocess.run(["/bin/sh", "Tests/50-chain.test.sh"], cwd=str(project),
                              capture_output=True, text=True, env=env,
                              input="not for the handler\n", timeout=_CLI_TIMEOUT)
    except subprocess.TimeoutExpired as exc:
        class _Timeout:
            returncode = 124
            stdout = exc.stdout or ""
            stderr = (exc.stderr or "") + "\nTIMEOUT"
        return _Timeout()


def test_standalone(project: Path, app: Path) -> None:
    print("Standalone mode:")
    env = _child_env()
    env["OMCTEST_APP"] = str(app)
    env["OMCTEST_LIB"] = str(OMCTEST)
    p = _run_standalone(project, env)
    check("one file runs with no runner", p.returncode == 0, p.stderr.strip()[-300:])
    check("and reports its own summary", "11 passed, 0 failed" in p.stderr,
          p.stderr.strip()[-200:])
    # Without OMCTEST_APP it must find the single .app beside Tests/.
    env.pop("OMCTEST_APP")
    p = _run_standalone(project, env)
    check("it locates the .app beside Tests/", p.returncode == 0, p.stderr.strip()[-300:])
    check("standalone leaves no scratch behind", not _scratch_dirs(),
          str([p.name for p in _scratch_dirs()]))


def test_regressions(app: Path) -> None:
    print("Regression pins:")
    # The python interpreter must be the one the engine's chain would pick.
    rc, out, err = run_cli("test", str(app), "--filter", "30-*", "--keep-scratch")
    kept = [l.split("scratch kept at ", 1)[1].strip()
            for l in err.splitlines() if "scratch kept at" in l]
    if not kept:
        check("could read the python probe", False, "no scratch kept")
        return
    path = Path(kept[-1])
    probes = list(path.glob("tmp/py.txt"))
    if not probes:
        check("the python handler wrote its probe", False, str(list(path.rglob("py.txt"))))
        shutil.rmtree(path, ignore_errors=True)
        return
    lines = probes[0].read_text().splitlines()
    want = expected_python()
    check("the interpreter is the engine's first executable candidate",
          os.path.realpath(lines[0]) == os.path.realpath(want),
          f"got {lines[0]}, expected {want}")
    # No embedded python in this fixture, so PATH must NOT have been prepended
    # for the .sh handlers - only for the .py one, inside its own dispatch.
    check("the .py handler saw the interpreter's bin on PATH",
          lines[2] == str(Path(want).parent), f"got {lines[2]}")
    shutil.rmtree(path, ignore_errors=True)

def test_build_integration(project: Path, app: Path) -> None:
    """Phase 4: build --test runs the suite after the refresh and before signing."""
    print("build --test:")
    tests = project / "Tests"
    stash = project / "Tests-stashed"
    # The suite the rest of this script uses deliberately contains files that
    # fail on purpose - one that crashes, one that stops early with exit 0, and
    # one that asserts nothing - to prove the runner reports each. A build
    # cannot be green with those present, so they step aside for this section.
    deliberately_bad = ["80-crash.test.sh", "81-truncated.test.sh", "82-empty.test.sh"]
    bad_bodies = {}
    for name in deliberately_bad:
        path = tests / name
        bad_bodies[name] = path.read_text()
        path.unlink()
    red = tests / "99-red.test.sh"
    red_body = ('#!/bin/sh\n. "${OMCTEST_LIB:?}"\n'
                'check "deliberately red" "a" "b"\nomctest_end\n')
    try:
        # --test with nothing to run is an error, not a silent skip: the flag is
        # an explicit request, and a release flow must not believe tests ran.
        tests.rename(stash)
        rc, out, err = run_cli("build", str(app), "--test")
        check("--test with no Tests/ -> exit 1", rc == 1, f"got {rc}")
        check("and it names the reason", "no Tests/ directory beside" in err, err.strip()[-200:])
        check("and never reached signing", "Codesigning" not in err)
        stash.rename(tests)

        # Green: the suite runs, then the app is signed.
        rc, out, err = run_cli("build", str(app), "--test")
        check("a green suite builds -> exit 0", rc == 0, err.strip()[-300:])
        check("the suite reported on stdout", "omctest:" in out, out.strip())
        check("and the app was signed", "Build succeeded" in err)
        # Order is the whole point: after the runtime refresh, before signing.
        pos_info = err.find("Info.plist content passed")
        pos_tests = err.find("Running tests...")
        pos_sign = err.find("Codesigning")
        check("tests run after the refresh", -1 < pos_info < pos_tests, f"{pos_info} < {pos_tests}")
        check("and before signing", -1 < pos_tests < pos_sign, f"{pos_tests} < {pos_sign}")

        # Red: halted, and nothing signed.
        _write(red, red_body)
        rc, out, err = run_cli("build", str(app), "--test")
        check("a red suite halts the build -> exit 1", rc == 1, f"got {rc}")
        check("and says tests failed", "tests failed" in err, err.strip()[-200:])
        check("and stopped before signing", "Codesigning" not in err)
        check("so it never claims success", "Build succeeded" not in err)

        # Without --test the same applet still builds, red tests and all.
        rc, out, err = run_cli("build", str(app))
        check("a plain build ignores red tests", rc == 0, err.strip()[-200:])
        red.unlink()

        # And the validate nudge, which must never change an exit status.
        tests.rename(stash)
        rc, out, err = run_cli("validate", str(app))
        check("validate nudges when there is no Tests/", "no Tests/ directory" in err)
        check("and still exits by its own rules", rc in (0, 1), f"got {rc}")
        stash.rename(tests)
        rc, out, err = run_cli("validate", str(app))
        check("and says nothing when there is one", "no Tests/ directory" not in err)
    finally:
        # The fixture is shared with every other test_* in this file, so it is
        # restored even when a check above raised.
        if stash.is_dir() and not tests.is_dir():
            stash.rename(tests)
        if red.exists():
            red.unlink()
        for name, body in bad_bodies.items():
            _write(tests / name, body)

def main() -> int:
    for required in (CLI, OMCTEST, AB_SUPPORT):
        if not required.exists():
            print(f"not found: {required}", file=sys.stderr)
            return 1

    test_hygiene()
    test_emitted_stubs()

    global _PRIVATE_TMP
    with tempfile.TemporaryDirectory(prefix="omctest-selftest-") as td:
        _PRIVATE_TMP = Path(td) / "tmp"
        _PRIVATE_TMP.mkdir(parents=True)
        project = Path(td) / "project"
        project.mkdir(parents=True)
        app = make_applet(project)
        write_tests(project)

        rc, out, err = run_cli("validate", str(app))
        check("the fixture applet validates", rc in (0, 2), err.strip()[-300:])

        test_usage_and_list(project, app)
        test_validation_gate(Path(td))
        test_suite(app)
        test_scratch_and_flags(app)
        test_uuid_uniqueness(app)
        test_standalone(project, app)
        test_regressions(app)
        test_build_integration(project, app)

    print(f"\n{_passed} passed, {_failed} failed.")
    return 1 if _failed else 0


if __name__ == "__main__":
    sys.exit(main())
