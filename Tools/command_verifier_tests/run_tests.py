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


def main() -> int:
    if not VERIFIER.exists():
        print(f"verifier not found: {VERIFIER}", file=sys.stderr)
        return 1
    test_flat_fixtures()
    test_layer2()
    print(f"\n{_passed} passed, {_failed} failed.")
    return 1 if _failed else 0


if __name__ == "__main__":
    sys.exit(main())
