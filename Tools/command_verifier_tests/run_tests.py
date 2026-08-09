#!/usr/bin/env python3
"""
Test harness for the Command.plist verifier.

The verifier itself lives (canonically) in the AppletBuilder bundle at
  Distribution/AppletBuilder.app/Contents/Library/command_verifier/
This harness invokes that copy so tests track exactly what ships.

Run:  python3 Tools/command_verifier_tests/run_tests.py
Exit: 0 = all passed, 1 = one or more failures.
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
VERIFIER = REPO / "Distribution" / "AppletBuilder.app" / "Contents" / "Library" / "command_verifier" / "validate_command_plist.py"
FIXTURES = Path(__file__).resolve().parent / "fixtures"
PY = sys.executable

_passed = 0
_failed = 0


def run(target: str) -> tuple[int, str]:
    p = subprocess.run([PY, str(VERIFIER), target], capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def check(name: str, cond: bool, detail: str = "") -> None:
    global _passed, _failed
    if cond:
        _passed += 1
        print(f"  ok   {name}")
    else:
        _failed += 1
        print(f"  FAIL {name}{(' — ' + detail) if detail else ''}")


# ── Layer 1: flat fixtures, exit-code contract ────────────────────────────────
def test_flat_fixtures() -> None:
    print("Layer 1 fixtures:")
    rc, _ = run(str(FIXTURES / "valid_basic.plist"))
    check("valid_basic → exit 0", rc == 0, f"got {rc}")
    # CF/plutil accept a plist DOCTYPE with no SYSTEM id; expat doesn't. The loader
    # must parse it leniently (Sips.app regression), not call the file invalid.
    rc, out = run(str(FIXTURES / "valid_doctype_no_system.plist"))
    check("SYSTEM-less DOCTYPE → exit 0", rc == 0, f"got {rc}: {out.strip()}")
    rc, out = run(str(FIXTURES / "bad_basic.plist"))
    check("bad_basic → exit 1 (errors)", rc == 1, f"got {rc}")
    check("bad_basic reports VERSION error", "VERSION is 3" in out)
    check("bad_basic reports deprecated alias", "exe_popen" in out and "deprecated" in out)
    check("bad_basic reports mutual exclusion", "mutually exclusive" in out)
    rc, out = run(str(FIXTURES / "bad_conditionals.plist"))
    check("bad_conditionals → exit 2 (warnings only)", rc == 2, f"got {rc}")
    check("bad_conditionals: appliesWhen fires", "has no effect" in out)
    check("bad_conditionals: requiredWhen fires", "should be set when" in out)
    check("bad_conditionals: range fires", "outside the expected range" in out)
    check("bad_conditionals: hexColor fires", "not a 6-digit hex" in out)


# ── Layer 2: synthesized bundles ──────────────────────────────────────────────
_VALID_BUNDLE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>COMMAND_LIST</key><array>
    <dict>
      <key>NAME</key><string>MyApp</string>
      <key>COMMAND_ID</key><string>myapp.run</string>
      <key>EXECUTION_MODE</key><string>exe_script_file</string>
    </dict>
  </array>
  <key>VERSION</key><integer>2</integer>
</dict></plist>
"""

# A dialog-only command: EXECUTION_MODE=exe_shell_script with no COMMAND, presenting an
# ACTIONUI_WINDOW whose JSON resolves. This is the common "no executable body" pattern
# (the dialog's subcommands do the work) and must produce NO error/warning. Regression
# test for the AIChat.app false positive.
_DIALOG_BUNDLE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>COMMAND_LIST</key><array>
    <dict>
      <key>NAME</key><string>MyApp</string>
      <key>COMMAND_ID</key><string>myapp.new</string>
      <key>EXECUTION_MODE</key><string>exe_shell_script</string>
      <key>ACTIONUI_WINDOW</key><dict>
        <key>JSON_NAME</key><string>MyWindow</string>
      </dict>
    </dict>
  </array>
  <key>VERSION</key><integer>2</integer>
</dict></plist>
"""

# A command with no executable body and no dialog/chain — a no-op. Should be reported
# at info level only (never error/warning), so the bundle still exits 0.
_NOOP_BUNDLE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>COMMAND_LIST</key><array>
    <dict>
      <key>NAME</key><string>MyApp</string>
      <key>COMMAND_ID</key><string>myapp.missing</string>
      <key>EXECUTION_MODE</key><string>exe_script_file</string>
    </dict>
  </array>
  <key>VERSION</key><integer>2</integer>
</dict></plist>
"""

_BROKEN_BUNDLE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>COMMAND_LIST</key><array>
    <dict>
      <key>NAME</key><string>MyApp</string>
      <key>COMMAND_ID</key><string>myapp.dialog</string>
      <key>ACTIONUI_WINDOW</key><dict>
        <key>JSON_NAME</key><string>NoSuchWindow</string>
        <key>END_OK_SUBCOMMAND_ID</key><string>does.not.exist</string>
      </dict>
    </dict>
  </array>
  <key>VERSION</key><integer>2</integer>
</dict></plist>
"""


# A subcommand that chains to the no-COMMAND_ID main command by its conventional
# implicit id "<NAME>.main" (here MyApp.main). The engine's FindCommandIndex maps
# <NAME>.main / main / top! to the main command, so this reference must resolve.
# Regression test: it used to be flagged as unresolved because the main command was
# only recorded under the legacy 'top!' id and <NAME>.main scripts aren't synthesized.
_MAIN_REF_BUNDLE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>COMMAND_LIST</key><array>
    <dict>
      <key>NAME</key><string>MyApp</string>
      <key>EXECUTION_MODE</key><string>exe_script_file</string>
      <key>ACTIONUI_WINDOW</key><dict>
        <key>JSON_NAME</key><string>MyWindow</string>
      </dict>
    </dict>
    <dict>
      <key>NAME</key><string>MyApp</string>
      <key>COMMAND_ID</key><string>myapp.open</string>
      <key>EXECUTION_MODE</key><string>exe_script_file</string>
      <key>NEXT_COMMAND_ID</key><string>MyApp.main</string>
    </dict>
  </array>
  <key>VERSION</key><integer>2</integer>
</dict></plist>
"""


# The main command identified the explicit way — COMMAND_ID="<NAME>.main" — must behave
# exactly like a no-COMMAND_ID main command (backward compat both ways). A subcommand
# chaining to it via the legacy "top!" must still resolve, and the explicit-id main must
# not be flagged as a duplicate or a no-op.
_EXPLICIT_MAIN_BUNDLE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>COMMAND_LIST</key><array>
    <dict>
      <key>NAME</key><string>MyApp</string>
      <key>COMMAND_ID</key><string>MyApp.main</string>
      <key>EXECUTION_MODE</key><string>exe_script_file</string>
      <key>ACTIONUI_WINDOW</key><dict>
        <key>JSON_NAME</key><string>MyWindow</string>
      </dict>
    </dict>
    <dict>
      <key>NAME</key><string>MyApp</string>
      <key>COMMAND_ID</key><string>myapp.open</string>
      <key>EXECUTION_MODE</key><string>exe_script_file</string>
      <key>NEXT_COMMAND_ID</key><string>top!</string>
    </dict>
  </array>
  <key>VERSION</key><integer>2</integer>
</dict></plist>
"""


# actionID cross-check. The main command presents MyWindow; myapp.save is declared;
# myapp.synth has no COMMAND_LIST entry but a script the engine would synthesize into
# a command. Everything a UI document may legitimately target is present here, so any
# warning this bundle produces must come from the two deliberate typos below.
_ACTIONID_BUNDLE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>COMMAND_LIST</key><array>
    <dict>
      <key>NAME</key><string>MyApp</string>
      <key>EXECUTION_MODE</key><string>exe_script_file</string>
      <key>ACTIONUI_WINDOW</key><dict>
        <key>JSON_NAME</key><string>MyWindow</string>
      </dict>
    </dict>
    <dict>
      <key>NAME</key><string>MyApp</string>
      <key>COMMAND_ID</key><string>myapp.save</string>
      <key>EXECUTION_MODE</key><string>exe_script_file</string>
    </dict>
  </array>
  <key>VERSION</key><integer>2</integer>
</dict></plist>
"""

# A window document exercising each way an actionID may legitimately resolve, plus one
# typo. The handler keys are deliberately non-canonical (onDrop/valueChange/viewDidLoad)
# - the checker matches any key whose name ends in "ActionID", not a fixed list.
_ACTIONID_WINDOW_JSON = """{
  "type": "VStack",
  "children": [
    { "type": "Button", "properties": { "title": "Save", "actionID": "myapp.save" } },
    { "type": "Button", "properties": { "title": "Close", "actionID": "omc.dialog.cancel" } },
    { "type": "List", "properties": { "onDropActionID": "myapp.synth" } },
    { "type": "TextField", "properties": { "valueChangeActionID": "myapp.tpyo" } },
    { "type": "LoadableView", "properties": { "viewDidLoadActionID": "MyApp.main" } }
  ]
}
"""

# MainMenu.json is loaded by the app lifecycle - no command references it - and its root
# is a JSON array. Both facts have to be handled or its wiring goes unchecked. The same
# bad id twice must collapse into one finding that says so.
_ACTIONID_MENU_JSON = """[
  {
    "type": "CommandGroup",
    "children": [
      { "type": "Button", "properties": { "title": "Open", "actionID": "myapp.gone" } },
      { "type": "Button", "properties": { "title": "Open Again", "actionID": "myapp.gone" } }
    ]
  }
]
"""

# A fragment template: a handler substitutes the __TOKENS__ before loading it, so as
# stored it is not JSON at all. It must be skipped without a peep.
_ACTIONID_TEMPLATE_JSON = """{
  "type": "Button",
  "id": __ID_BUTTON__,
  "properties": { "title": "__LABEL__", "actionID": "myapp.never.declared" }
}
"""

# Foundation's JSONSerialization - what the engine parses with - accepts trailing
# commas, so this document loads and renders fine and its wiring must be checked.
# The help string carries a ", }" of its own: the repair tracks string state, so it
# must not be mistaken for a trailing comma.
_ACTIONID_TRAILING_COMMA_JSON = """{
  "type": "VStack",
  "children": [
    { "type": "Button", "properties": { "help": "prints a, } brace", "actionID": "myapp.save", } },
    { "type": "Button", "properties": { "actionID": "myapp.comma.gone", } },
  ],
}
"""

# Case is load-bearing: every engine lookup on this path is case-sensitive, and a
# synthesized COMMAND_ID keeps its script's filesystem case on purpose. 'MyApp.Save'
# against a declared 'myapp.save' is a dead button that reads as correct.
_ACTIONID_CASE_JSON = """{
  "type": "Button",
  "properties": { "title": "Save", "actionID": "MyApp.Save" }
}
"""

# Keys that merely END in a lowercase "actionid" are data, not wiring. Real ActionUI
# handler keys are exactly "actionID" or end in "ActionID" with the capital A.
_ACTIONID_LOOKALIKE_JSON = """{
  "type": "Table",
  "properties": { "transactionID": "not.a.command", "interactionID": "also.not.a.command" }
}
"""

# Documents the engine cannot load as UI for THIS bundle: an example in a docs
# subtree, and a whole nested applet template with its own command list. Both carry
# dangling ids that belong to someone else, and neither may be reported.
_ACTIONID_OUT_OF_SCOPE_JSON = """{
  "type": "Button",
  "properties": { "actionID": "example.only.not.mine" }
}
"""

# COMMAND_ID 'myapp.main' under NAME 'MyApp' only LOOKS like the main command's
# implicit id. The engine normalizes to the 'top!' sentinel on an exact match alone
# (CFStringCompare(id,"main",0) / CFEqual against "<NAME>.main"), so this command
# keeps its literal id: 'myapp.main' dispatches it, while 'MyApp.main', 'main' and
# 'top!' reach nothing at all. Getting this backwards calls a working control dead
# and waves three dead ones through.
_NEAR_MISS_MAIN_BUNDLE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>COMMAND_LIST</key><array>
    <dict>
      <key>NAME</key><string>MyApp</string>
      <key>COMMAND_ID</key><string>myapp.main</string>
      <key>EXECUTION_MODE</key><string>exe_script_file</string>
      <key>ACTIONUI_WINDOW</key><dict>
        <key>JSON_NAME</key><string>Near</string>
      </dict>
    </dict>
  </array>
  <key>VERSION</key><integer>2</integer>
</dict></plist>
"""

_NEAR_MISS_WINDOW_JSON = """{
  "type": "VStack",
  "children": [
    { "type": "Button", "properties": { "title": "Works", "actionID": "myapp.main" } },
    { "type": "Button", "properties": { "title": "Dead", "actionID": "MyApp.main" } },
    { "type": "Button", "properties": { "title": "Dead too", "actionID": "top!" } }
  ]
}
"""

# Degenerate but engine-faithful: a NAME that is present and EMPTY still forms an
# implicit main id, '.main', so this IS the main command and answers to 'top!'. A
# missing NAME would form no implicit id at all.
_EMPTY_NAME_MAIN_BUNDLE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>COMMAND_LIST</key><array>
    <dict>
      <key>NAME</key><string></string>
      <key>COMMAND_ID</key><string>.main</string>
      <key>EXECUTION_MODE</key><string>exe_script_file</string>
      <key>ACTIONUI_WINDOW</key><dict>
        <key>JSON_NAME</key><string>Empty</string>
      </dict>
    </dict>
  </array>
  <key>VERSION</key><integer>2</integer>
</dict></plist>
"""

_EMPTY_NAME_WINDOW_JSON = """{
  "type": "Button",
  "properties": { "title": "Go", "actionID": "top!" }
}
"""

# A command file that happens to carry a key ending in ActionID. It is validated by
# Layer 1, never scanned as a UI document.
_ACTIONID_COMMAND_JSON = """{
  "COMMAND_LIST": [
    { "NAME": "MyApp", "COMMAND_ID": "myapp.save", "EXECUTION_MODE": "exe_script_file",
      "onDropActionID": "not.a.ui.document" }
  ],
  "VERSION": 2
}
"""


def _make_bundle(root: Path, plist: str, scripts: list[str],
                 resources: dict[str, str] | None = None) -> Path:
    res = root / "Contents" / "Resources"
    (res / "Scripts").mkdir(parents=True, exist_ok=True)
    (res / "Command.plist").write_text(plist, encoding="utf-8")
    for s in scripts:
        (res / "Scripts" / s).write_text("#!/bin/bash\necho hi\n", encoding="utf-8")
    for rel, content in (resources or {}).items():
        path = res / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    return root


def test_layer2() -> None:
    print("Layer 2 bundle cross-references:")
    with tempfile.TemporaryDirectory() as d:
        valid = _make_bundle(Path(d) / "Valid.app", _VALID_BUNDLE, ["myapp.run.sh"])
        rc, out = run(str(valid))
        check("valid bundle → exit 0", rc == 0, out.strip())

        # Dialog-only command with no COMMAND must not be flagged (AIChat.app regression).
        dialog = _make_bundle(Path(d) / "Dialog.app", _DIALOG_BUNDLE, [],
                              {"MyWindow.json": "{}\n"})
        rc, out = run(str(dialog))
        check("dialog-only no-COMMAND → exit 0", rc == 0, f"got {rc}: {out.strip()}")
        check("dialog-only: no error/warning emitted",
              "[ERROR]" not in out and "[WARNING]" not in out, out.strip())

        # No body, no dialog/chain → info only, still exit 0.
        noop = _make_bundle(Path(d) / "Noop.app", _NOOP_BUNDLE, [])
        rc, out = run(str(noop))
        check("no-op command → exit 0 (info only)", rc == 0, f"got {rc}: {out.strip()}")
        check("no-op command: info note, not error/warning",
              "[INFO]" in out and "[ERROR]" not in out and "[WARNING]" not in out, out.strip())
        check("no-op command: names missing script", "no script named 'myapp.missing.*'" in out)

        # NEXT_COMMAND_ID referencing the main command by its implicit "<NAME>.main"
        # id must resolve (regression: previously flagged as unresolved).
        mainref = _make_bundle(Path(d) / "MainRef.app", _MAIN_REF_BUNDLE,
                               ["MyApp.main.sh", "myapp.open.sh"],
                               {"MyWindow.json": "{}\n"})
        rc, out = run(str(mainref))
        check("<NAME>.main reference → exit 0", rc == 0, f"got {rc}: {out.strip()}")
        check("<NAME>.main resolves (no dangling error)",
              "'MyApp.main' does not resolve" not in out, out.strip())

        # Explicit COMMAND_ID="<NAME>.main" main command behaves like a no-id main:
        # a legacy "top!" reference resolves, and it is not flagged duplicate/no-op.
        explicit = _make_bundle(Path(d) / "ExplicitMain.app", _EXPLICIT_MAIN_BUNDLE,
                                ["MyApp.main.sh", "myapp.open.sh"],
                                {"MyWindow.json": "{}\n"})
        rc, out = run(str(explicit))
        check("explicit <NAME>.main main → exit 0", rc == 0, f"got {rc}: {out.strip()}")
        check("explicit main: legacy top! reference resolves",
              "'top!' does not resolve" not in out, out.strip())
        check("explicit main: no error/warning",
              "[ERROR]" not in out and "[WARNING]" not in out, out.strip())

        broken = _make_bundle(Path(d) / "Broken.app", _BROKEN_BUNDLE, [])
        rc, out = run(str(broken))
        check("broken bundle → exit 1", rc == 1, f"got {rc}")
        check("missing JSON detected", "no JSON resource named 'NoSuchWindow.json'" in out)
        check("dangling subcommand detected", "does not resolve to any command" in out)


def test_action_ids() -> None:
    print("Layer 2 ActionUI actionID cross-references:")
    with tempfile.TemporaryDirectory() as d:
        docs = {
            "Base.lproj/MyWindow.json": _ACTIONID_WINDOW_JSON,
            "Base.lproj/MainMenu.json": _ACTIONID_MENU_JSON,
            "card.template.json": _ACTIONID_TEMPLATE_JSON,
            "Base.lproj/Trailing.json": _ACTIONID_TRAILING_COMMA_JSON,
            "Base.lproj/Case.json": _ACTIONID_CASE_JSON,
            "Base.lproj/Lookalike.json": _ACTIONID_LOOKALIKE_JSON,
            "Documentation/Elements/Sample.json": _ACTIONID_OUT_OF_SCOPE_JSON,
            "Templates/Demo.applet/Contents/Resources/Base.lproj/Window.json": _ACTIONID_OUT_OF_SCOPE_JSON,
            # 4000-deep nesting: the walk must not blow the interpreter's stack and
            # take the whole verifier run down with it. This only exercises the walk
            # on a Python whose C json scanner gets this deep (3.12+, and the runtime
            # AppletBuilder embeds is 3.14) - on an older one the parse itself fails
            # first and the document is skipped, which passes for the wrong reason.
            "Base.lproj/Deep.json": "[" * 4000 + "]" * 4000,
        }
        app = _make_bundle(Path(d) / "Actions.app", _ACTIONID_BUNDLE,
                           ["MyApp.main.sh", "myapp.save.sh", "myapp.synth.sh"], docs)
        rc, out = run(str(app))

        check("typo'd actionID -> exit 2 (warnings, no errors)", rc == 2, f"got {rc}: {out.strip()}")
        check("typo'd valueChangeActionID reported",
              "valueChangeActionID 'myapp.tpyo' does not resolve" in out, out.strip())
        check("finding is a warning, never an error",
              "[ERROR]" not in out, out.strip())
        check("finding is labeled by document path",
              "Base.lproj/MyWindow.json:" in out, out.strip())

        # Everything a UI document may legitimately target must stay silent.
        check("declared COMMAND_ID resolves", "actionID 'myapp.save'" not in out, out.strip())
        check("synthesizable script resolves (no COMMAND_LIST entry)",
              "'myapp.synth'" not in out, out.strip())
        check("implicit <NAME>.main resolves", "'MyApp.main'" not in out, out.strip())
        check("engine-reserved omc.dialog.* id resolves",
              "omc.dialog.cancel" not in out, out.strip())

        # MainMenu.json: array root, referenced by no command, still checked - and not
        # complained about for being unreferenced.
        check("array-root MainMenu.json is scanned",
              "actionID 'myapp.gone' does not resolve" in out, out.strip())
        check("repeated bad id collapses into one counted finding",
              out.count("'myapp.gone'") == 1 and "(2 occurrences)" in out, out.strip())
        check("unreferenced document draws exactly one finding, about its wiring",
              len([ln for ln in out.splitlines() if "MainMenu.json" in ln]) == 1, out.strip())

        # Unparsable fragment template: skipped silently, not reported as broken.
        check("placeholder template skipped silently",
              "card.template.json" not in out, out.strip())

        # Trailing commas: Foundation loads such a document, so it must be scanned.
        check("trailing-comma document is scanned",
              "actionID 'myapp.comma.gone' does not resolve" in out, out.strip())
        check("a ', }' inside a string is not mistaken for a trailing comma",
              "actionID 'myapp.save'" not in out, out.strip())

        # Case mismatch: resolvable only when folded, therefore dead at runtime.
        check("case-mismatched actionID reported distinctly",
              "actionID 'MyApp.Save' matches 'myapp.save' only case-insensitively" in out,
              out.strip())

        # Keys that only look like handler keys are data.
        check("transactionID / interactionID are not treated as wiring",
              "not.a.command" not in out, out.strip())

        # Documents the engine cannot load as UI for this bundle.
        check("docs-subtree example not scanned",
              "Documentation/Elements" not in out, out.strip())
        check("nested applet template not scanned",
              "Templates/" not in out and "example.only.not.mine" not in out, out.strip())

        # Deep nesting must not crash the verifier (exit 2 = warnings, not a traceback).
        check("deeply nested document does not crash the run",
              "RecursionError" not in out and "Traceback" not in out, out.strip())

        # Fix the two typos and the same bundle must come back clean.
        clean_docs = dict(docs)
        clean_docs["Base.lproj/MyWindow.json"] = _ACTIONID_WINDOW_JSON.replace("myapp.tpyo", "myapp.save")
        clean_docs["Base.lproj/MainMenu.json"] = _ACTIONID_MENU_JSON.replace("myapp.gone", "myapp.synth")
        clean_docs["Base.lproj/Case.json"] = _ACTIONID_CASE_JSON.replace("MyApp.Save", "myapp.save")
        clean_docs["Base.lproj/Trailing.json"] = _ACTIONID_TRAILING_COMMA_JSON.replace("myapp.comma.gone", "myapp.save")
        good = _make_bundle(Path(d) / "Clean.app", _ACTIONID_BUNDLE,
                            ["MyApp.main.sh", "myapp.save.sh", "myapp.synth.sh"], clean_docs)
        rc, out = run(str(good))
        check("all actionIDs resolving -> exit 0", rc == 0, f"got {rc}: {out.strip()}")

        # A COMMAND_ID that only looks like the implicit main id is not the main
        # command: its literal spelling works, the three main aliases do not.
        near = _make_bundle(Path(d) / "NearMiss.app", _NEAR_MISS_MAIN_BUNDLE,
                            ["myapp.main.sh"], {"Base.lproj/Near.json": _NEAR_MISS_WINDOW_JSON})
        rc, out = run(str(near))
        check("near-miss main: its literal COMMAND_ID resolves",
              "actionID 'myapp.main'" not in out, out.strip())
        check("near-miss main: '<NAME>.main' is reported as case-only match",
              "actionID 'MyApp.main' matches 'myapp.main' only case-insensitively" in out,
              out.strip())
        check("near-miss main: 'top!' resolves to nothing",
              "actionID 'top!' does not resolve" in out, out.strip())

        # An empty NAME still forms the implicit '.main' id, so that command IS main
        # and 'top!' reaches it. (A missing NAME would not.)
        empty = _make_bundle(Path(d) / "EmptyName.app", _EMPTY_NAME_MAIN_BUNDLE,
                             [".main.sh"], {"Base.lproj/Empty.json": _EMPTY_NAME_WINDOW_JSON})
        rc, out = run(str(empty))
        check("empty NAME still forms the implicit main id",
              "actionID 'top!'" not in out, out.strip())

        # The command file is JSON too. It is Layer 1's business, never scanned as a
        # UI document, even when it carries a key ending in ActionID.
        cmdjson = _make_bundle(Path(d) / "CommandJson.app", "", ["myapp.save.sh"],
                               {"Command.json": _ACTIONID_COMMAND_JSON})
        (cmdjson / "Contents" / "Resources" / "Command.plist").unlink()
        rc, out = run(str(cmdjson))
        check("Command.json is not scanned as a UI document",
              "not.a.ui.document" not in out, out.strip())


def main() -> int:
    if not VERIFIER.exists():
        print(f"verifier not found: {VERIFIER}", file=sys.stderr)
        return 1
    test_flat_fixtures()
    test_layer2()
    test_action_ids()
    print(f"\n{_passed} passed, {_failed} failed.")
    return 1 if _failed else 0


if __name__ == "__main__":
    sys.exit(main())
