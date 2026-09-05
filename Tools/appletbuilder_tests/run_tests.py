#!/usr/bin/env python3
"""
Test harness for the command-line `appletbuilder` agent CLI.

The CLI lives (canonically) in the AppletBuilder bundle at
  Distribution/AppletBuilder.app/Contents/Resources/Agents/appletbuilder
and drives the same shared Scripts/lib.*.sh code as the GUI. This harness invokes
that copy so tests track exactly what ships.

Run:   python3 Tools/appletbuilder_tests/run_tests.py
       AB_TEST_SCREENSHOT=1 python3 …   # also exercise preview's PNG capture
                                          # (needs a logged-in GUI / window-server)
Exit:  0 = all passed, 1 = one or more failures.

Notes:
  * create/build invoke the real toolchain (cp of Abracode.framework, codesign,
    lsregister). They are skipped with a note if `codesign` is unavailable.
  * create persists a BundleIDPrefix in the com.abracode.applet-builder defaults
    domain (as the GUI does); the harness snapshots and restores it.
"""
from __future__ import annotations

import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CLI = REPO / "Distribution" / "AppletBuilder.app" / "Contents" / "Resources" / "Agents" / "appletbuilder"
TEMPLATES = REPO / "Distribution" / "AppletBuilder.app" / "Contents" / "Resources" / "Templates"

_DEFAULTS_DOMAIN = "com.abracode.applet-builder"
_DEFAULTS_KEY = "BundleIDPrefix"

# The ActionUI shell client and the two awk programs it runs. They travel as a set: the .zsh
# sources the .sh, and the .sh refuses to load without both programs beside it.
_SHELL_CLIENT_FILES = ("actionui_remote.sh", "actionui_remote.zsh",
                       "actionui_remote_escape.awk", "actionui_remote_walk.awk")

_passed = 0
_failed = 0


def run(*args: str, cwd: str | None = None):
    """Invoke the CLI; return (returncode, stdout, stderr)."""
    p = subprocess.run([str(CLI), *args], capture_output=True, text=True, cwd=cwd)
    return p.returncode, p.stdout, p.stderr


def check(name: str, cond: bool, detail: str = "") -> None:
    global _passed, _failed
    if cond:
        _passed += 1
        print(f"  ok   {name}")
    else:
        _failed += 1
        print(f"  FAIL {name}{(' — ' + detail) if detail else ''}")


# ── Fixture helpers ───────────────────────────────────────────────────────────

_VALID_COMMAND = {
    "COMMAND_LIST": [
        {"NAME": "Test", "COMMAND_ID": "test.run", "EXECUTION_MODE": "exe_script_file"}
    ],
    "VERSION": 2,
}

_VALID_UI = {
    "type": "VStack",
    "properties": {"spacing": 10},
    "children": [{"type": "Text", "properties": {"text": "hi"}}],
}

_UNKNOWN_UI = {"type": "NoSuchThing", "properties": {}}

_MENUBAR = [
    {"type": "CommandMenu", "properties": {"name": "Commands", "autoPopulate": True}}
]


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def make_bundle(root: Path, *, name: str = "Demo", command_json: str | None = None,
                with_exe: bool = True) -> Path:
    """Synthesize a minimal, valid applet bundle (no real Mach-O needed)."""
    contents = root / "Contents"
    res = contents / "Resources"
    (res / "Scripts").mkdir(parents=True, exist_ok=True)
    (res / "Base.lproj").mkdir(parents=True, exist_ok=True)

    info = {
        "CFBundleExecutable": name,
        "CFBundleName": name,
        "CFBundleIdentifier": f"com.test.{name.lower()}",
    }
    with open(contents / "Info.plist", "wb") as f:
        plistlib.dump(info, f)

    if with_exe:
        (contents / "MacOS").mkdir(parents=True, exist_ok=True)
        _write(contents / "MacOS" / name, "#!/bin/sh\n:\n")

    cmd = command_json if command_json is not None else json.dumps(_VALID_COMMAND, indent=2)
    _write(res / "Command.json", cmd)
    _write(res / "Scripts" / "test.run.sh", "#!/bin/bash\necho hi\n")
    _write(res / "Base.lproj" / "Window.json", json.dumps(_VALID_UI, indent=2))
    return root


# ── Usage & dispatch ──────────────────────────────────────────────────────────

def test_usage() -> None:
    print("Usage & dispatch:")
    rc, out, err = run()
    check("no args → exit 2", rc == 2, f"got {rc}")
    check("no args → usage on stderr", "Usage:" in err)
    rc, out, err = run("bogus-command")
    check("unknown command → exit 2", rc == 2, f"got {rc}")
    check("unknown command → names it", "unknown command" in err)


# ── Listings ──────────────────────────────────────────────────────────────────

def test_listings() -> None:
    print("Listings:")
    rc, out, err = run("list-templates")
    check("list-templates → exit 0", rc == 0, f"got {rc}")
    check("list-templates includes 'ActionUI Window'", "ActionUI Window" in out, out.strip())
    check("list-templates includes 'Empty'", "Empty" in out)
    rc, out, err = run("list-icons")
    check("list-icons → exit 0", rc == 0, f"got {rc}")
    check("list-icons includes 'Bolt'", "Bolt" in out, out.strip())


# ── validate ──────────────────────────────────────────────────────────────────

def test_validate() -> None:
    print("validate:")
    with tempfile.TemporaryDirectory() as d:
        d = Path(d)

        # Bundle — valid.
        good = make_bundle(d / "Good.app", name="Good")
        rc, out, err = run("validate", str(good))
        check("valid bundle → exit 0", rc == 0, f"got {rc}: {err.strip()}")
        check("valid bundle → progress on stderr", "Validating project" in err)

        # Bundle — broken command manifest.
        bad = make_bundle(d / "Bad.app", name="Bad", command_json='{ "COMMAND_LIST": [ , ] ')
        rc, out, err = run("validate", str(bad))
        check("bundle w/ broken Command.json → exit 1", rc == 1, f"got {rc}")

        # Standalone command file.
        cj = d / "Command.json"
        _write(cj, json.dumps(_VALID_COMMAND, indent=2))
        rc, out, err = run("validate", str(cj))
        check("valid Command.json → exit 0", rc == 0, f"got {rc}: {err.strip()}")
        _write(cj, '{ "COMMAND_LIST": [ , ] ')
        rc, out, err = run("validate", str(cj))
        check("malformed Command.json → exit 1", rc == 1, f"got {rc}")
        check("malformed Command.json → syntax message", "INVALID (syntax)" in err, err.strip())

        # Standalone ActionUI JSON.
        ui = d / "View.json"
        _write(ui, json.dumps(_VALID_UI))
        rc, out, err = run("validate", str(ui))
        check("valid ActionUI → exit 0", rc == 0, f"got {rc}: {err.strip()}")
        _write(ui, json.dumps(_UNKNOWN_UI))
        rc, out, err = run("validate", str(ui))
        check("ActionUI unknown type → exit 1", rc == 1, f"got {rc}")
        check("ActionUI error mentions type", "unknown element type" in err, err.strip())

        # Scripts.
        sh = d / "ok.sh"
        _write(sh, "#!/bin/bash\necho hi\n")
        rc, out, err = run("validate", str(sh))
        check("valid script → exit 0", rc == 0, f"got {rc}: {err.strip()}")

        warn = d / "warn.sh"
        _write(warn, 'name=hi\nresult="${name^^}"\necho "$result"\n')
        rc, out, err = run("validate", str(warn))
        check("script w/ bash4-ism → exit 2 (warnings)", rc == 2, f"got {rc}: {err.strip()}")
        check("bash4-ism → WARNINGS reported", "WARNINGS" in err, err.strip())

        broken = d / "broken.sh"
        _write(broken, "if [ 1 = 1 ]; then\n  echo hi\n")  # missing 'fi'
        rc, out, err = run("validate", str(broken))
        check("script syntax error → exit 1", rc == 1, f"got {rc}")
        check("syntax error → SYNTAX ERROR reported", "SYNTAX ERROR" in err, err.strip())

        # Unrecognized / missing.
        txt = d / "notes.txt"
        _write(txt, "hello\n")
        rc, out, err = run("validate", str(txt))
        check("unknown extension → exit 2", rc == 2, f"got {rc}")
        rc, out, err = run("validate", str(d / "nope.json"))
        check("missing file → exit 2", rc == 2, f"got {rc}")
        rc, out, err = run("validate")
        check("validate w/o target → exit 2", rc == 2, f"got {rc}")


# ── prettify ──────────────────────────────────────────────────────────────────

def test_prettify() -> None:
    print("prettify:")
    with tempfile.TemporaryDirectory() as d:
        d = Path(d)
        f = d / "compact.json"
        _write(f, '{"b":2,"a":1}')

        rc, out, err = run("prettify", str(f), "--stdout")
        check("prettify --stdout → exit 0", rc == 0, f"got {rc}")
        check("prettify --stdout → indented output", "\n" in out and '    "b": 2' in out, out)
        check("prettify --stdout → file untouched", f.read_text() == '{"b":2,"a":1}')

        rc, out, err = run("prettify", str(f))
        check("prettify in place → exit 0", rc == 0, f"got {rc}")
        body = f.read_text()
        check("prettify in place → file reformatted", "\n" in body and json.loads(body) == {"b": 2, "a": 1})

        bad = d / "bad.json"
        _write(bad, "{nope")
        rc, out, err = run("prettify", str(bad))
        check("prettify invalid JSON → exit 1", rc == 1, f"got {rc}")
        check("prettify invalid → error on stderr", "invalid JSON" in err, err.strip())


# ── preview ───────────────────────────────────────────────────────────────────

def test_preview() -> None:
    print("preview:")
    with tempfile.TemporaryDirectory() as d:
        d = Path(d)

        # Menu-bar document → textual summary on stdout (no window server needed).
        mb = d / "MainMenu.json"
        _write(mb, json.dumps(_MENUBAR))
        rc, out, err = run("preview", str(mb))
        check("preview menubar → exit 0", rc == 0, f"got {rc}: {err.strip()}")
        check("preview menubar → summary on stdout", "menu-bar customization" in out, out.strip())

        bad = d / "bad.json"
        _write(bad, "{nope")
        rc, out, err = run("preview", str(bad))
        check("preview invalid JSON → exit 1", rc == 1, f"got {rc}")
        rc, out, err = run("preview", str(d / "missing.json"))
        check("preview missing file → exit 2", rc == 2, f"got {rc}")

        # Live screenshot of a view — opt-in (needs a logged-in GUI session).
        if os.environ.get("AB_TEST_SCREENSHOT") == "1":
            view = d / "View.json"
            _write(view, json.dumps(_VALID_UI))
            shot = d / "shot.png"
            rc, out, err = run("preview", str(view), "--screenshot", str(shot))
            check("preview --screenshot → exit 0", rc == 0, f"got {rc}: {err.strip()}")
            check("preview --screenshot → path on stdout", out.strip() == str(shot), out.strip())
            check("preview --screenshot → PNG written", shot.exists() and shot.stat().st_size > 0)
        else:
            print("  skip preview --screenshot (set AB_TEST_SCREENSHOT=1 to run)")


# ── create / build (toolchain) ────────────────────────────────────────────────

def _plist_get(path: Path, key: str) -> str:
    p = subprocess.run(["/usr/bin/plutil", "-extract", key, "raw", str(path)],
                       capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else ""


def test_create_arg_errors() -> None:
    print("create argument errors:")
    with tempfile.TemporaryDirectory() as d:
        rc, out, err = run("create", "--name", "X", "--dest", d)
        check("create w/o template/clone → exit 2", rc == 2, f"got {rc}")
        check("create w/o template → message", "is required" in err)
        rc, out, err = run("create", "--template", "Empty", "--name", "X")
        check("create w/o --dest → exit 2", rc == 2, f"got {rc}")
        check("create w/o --dest → message", "--dest" in err)
        rc, out, err = run("create", "--template", "Empty", "--name", "X",
                           "--dest", d, "--icon", "NoSuchIconXYZ")
        check("create w/ bogus icon → exit 2", rc == 2, f"got {rc}")
        check("create bogus icon → message", "known icon" in err, err.strip())


def test_create_build() -> None:
    print("create / build (toolchain):")
    if not shutil.which("codesign"):
        print("  skip create/build — codesign not available")
        return

    saved = subprocess.run(["/usr/bin/defaults", "read", _DEFAULTS_DOMAIN, _DEFAULTS_KEY],
                           capture_output=True, text=True)
    saved_prefix = saved.stdout.strip() if saved.returncode == 0 else None
    try:
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            name = "TestApplet"
            rc, out, err = run("create", "--template", "Empty", "--name", name,
                               "--dest", str(d), "--python", "--no-codesign",
                               "--bundle-id", "com.test.testapplet")
            check("create Empty --python → exit 0", rc == 0, f"got {rc}: {err.strip()}")
            app = d / f"{name}.app"
            check("create → stdout is the new path", out.strip() == str(app), out.strip())
            check("create → bundle exists", app.is_dir())
            check("create → executable renamed", (app / "Contents" / "MacOS" / name).is_file())
            check("create → Info.plist CFBundleExecutable set",
                  _plist_get(app / "Contents" / "Info.plist", "CFBundleExecutable") == name)
            check("create → bundle id set",
                  _plist_get(app / "Contents" / "Info.plist", "CFBundleIdentifier") == "com.test.testapplet")
            check("create --python → main.py present",
                  (app / "Contents" / "Resources" / "Scripts" / f"{name}.main.py").is_file())
            check("create --python → embedded Python present",
                  (app / "Contents" / "Library" / "Python").is_dir())

            # Re-creating over an existing applet must fail cleanly.
            rc, out, err = run("create", "--template", "Empty", "--name", name, "--dest", str(d))
            check("create over existing → exit 1", rc == 1, f"got {rc}")
            check("create over existing → message", "Already exists" in err, err.strip())

            # The freshly created bundle validates clean.
            rc, out, err = run("validate", str(app))
            check("created bundle validates → exit 0", rc == 0, f"got {rc}: {err.strip()}")

            # Build it (this codesigns ad-hoc).
            rc, out, err = run("build", str(app))
            check("build created bundle → exit 0", rc == 0, f"got {rc}: {err.strip()[-300:]}")
            check("build → 'Build succeeded'", "Build succeeded" in err, err.strip()[-300:])

            packages = app / "Contents" / "Library" / "Packages"
            check("build -> the Python client is installed",
                  (packages / "actionui_remote.py").is_file())
            # An applet with only a Python handler must NOT be given the shell clients: they are
            # gated on a shell handler, and a gate that lets everything through is not a gate.
            check("build -> no shell client without a shell handler",
                  not any((packages / q).exists() for q in _SHELL_CLIENT_FILES),
                  sorted(q.name for q in packages.iterdir()))

            # Now give it a shell handler and rebuild. All four files must arrive together -
            # actionui_remote.zsh sources actionui_remote.sh from its own directory, and the .sh
            # reads its two awk programs from there and refuses to load without them. The two
            # clients must be executable, because cp does not carry the mode across a plain
            # overwrite; the awk programs are read by awk and never run.
            handler = app / "Contents" / "Resources" / "Scripts" / f"{name}.shell.sh"
            handler.write_text("#!/bin/sh\necho hello\n")
            handler.chmod(0o755)
            rc, out, err = run("build", str(app))
            check("rebuild with a shell handler -> exit 0", rc == 0, f"got {rc}: {err.strip()[-300:]}")
            for client in _SHELL_CLIENT_FILES:
                check(f"build -> {client} is installed", (packages / client).is_file())
                if client.endswith(".awk"):
                    check(f"build -> {client} is readable",
                          (packages / client).exists() and os.access(packages / client, os.R_OK))
                else:
                    check(f"build -> {client} is executable",
                          (packages / client).exists() and os.access(packages / client, os.X_OK))
            check("build -> the install is reported",
                  "ActionUI shell client file(s)" in err
                  and "missing from AppletBuilder" not in err
                  and "Removed the ActionUI shell client set" not in err,
                  err.strip()[-300:])
    finally:
        if saved_prefix is None:
            subprocess.run(["/usr/bin/defaults", "delete", _DEFAULTS_DOMAIN, _DEFAULTS_KEY],
                           capture_output=True)
        else:
            subprocess.run(["/usr/bin/defaults", "write", _DEFAULTS_DOMAIN, _DEFAULTS_KEY, saved_prefix],
                           capture_output=True)


def test_shell_client_install() -> None:
    """update_shell_clients, driven directly.

    A real build has no way to make one copy of the four fail, and that is the case the
    function's all-or-nothing rule is about: three of four is an ActionUI shell client that
    refuses to load, which is worse for a handler than never having one at all.
    """
    print("shell client install (update_shell_clients):")
    bundle = REPO / "Distribution" / "AppletBuilder.app"
    packages = bundle / "Contents" / "Library" / "Packages"
    for client in _SHELL_CLIENT_FILES:
        if not (packages / client).is_file():
            check(f"{client} is present to install from", False,
                  "run update_appletbuilder.sh")
            return

    def call(target: Path, source_bundle: Path = bundle) -> str:
        script = (f'export OMC_APP_BUNDLE_PATH="{bundle}"\n'
                  f'source "$OMC_APP_BUNDLE_PATH/Contents/Resources/Scripts/lib.build.sh"\n'
                  f'OMC_APP_BUNDLE_PATH="{source_bundle}" update_shell_clients "{target}"\n')
        p = subprocess.run(["/bin/bash", "-c", script], capture_output=True, text=True)
        return p.stdout + p.stderr

    def make_target(root: Path) -> Path:
        target = root / "Applet.app"
        (target / "Contents" / "Resources" / "Scripts").mkdir(parents=True)
        (target / "Contents" / "Library" / "Packages").mkdir(parents=True)
        handler = target / "Contents" / "Resources" / "Scripts" / "handler.sh"
        handler.write_text("#!/bin/sh\necho hi\n")
        return target

    def installed(target: Path) -> list:
        dst = target / "Contents" / "Library" / "Packages"
        return sorted(q for q in _SHELL_CLIENT_FILES if (dst / q).is_file())

    with tempfile.TemporaryDirectory() as td:
        target = make_target(Path(td))
        # Pre-created with the opposite of the mode each should end up with, because cp takes
        # the source's mode only when it creates the file; over an existing one it keeps what is
        # there. That is the rebuild path, and the only path where the chmod does any work - and
        # the mode has to be wrong in the direction each check reads, or that check cannot fail.
        dst = target / "Contents" / "Library" / "Packages"
        for client in _SHELL_CLIENT_FILES:
            stale = dst / client
            stale.write_text("stale, and not what the source says\n")
            stale.chmod(0o755 if client.endswith(".awk") else 0o600)
        call(target)
        # Presence alone would be true before the call, since the four files were just created
        # here. The contents are what prove the copy happened.
        check("an install over a stale set lands all four files, with the source's contents",
              installed(target) == sorted(_SHELL_CLIENT_FILES)
              and all((dst / q).read_bytes() == (packages / q).read_bytes()
                      for q in _SHELL_CLIENT_FILES),
              str(installed(target)))
        check("the clients are executable",
              all(os.access(dst / q, os.X_OK) for q in _SHELL_CLIENT_FILES
                  if not q.endswith(".awk")))
        check("the awk programs are readable and not executable",
              all(os.access(dst / q, os.R_OK) and not os.access(dst / q, os.X_OK)
                  for q in _SHELL_CLIENT_FILES if q.endswith(".awk")))

    # A copy that fails part way through takes the whole set back out again.
    with tempfile.TemporaryDirectory() as td:
        target = make_target(Path(td))
        blocked = target / "Contents" / "Library" / "Packages" / "actionui_remote_walk.awk"
        blocked.write_text("")
        blocked.chmod(0o444)
        out = call(target)
        check("a failed copy leaves nothing behind", installed(target) == [],
              str(installed(target)))
        check("and says the set was removed", "Removed the ActionUI shell client set" in out,
              out.strip()[-200:])

    # The same, failing on a middle file rather than the last, so the rollback is pinned wherever
    # in the loop the failure lands. It does not distinguish break from continue: once the whole
    # set comes back out, the two leave the same directory behind.
    with tempfile.TemporaryDirectory() as td:
        target = make_target(Path(td))
        blocked = target / "Contents" / "Library" / "Packages" / "actionui_remote.zsh"
        blocked.write_text("")
        blocked.chmod(0o444)
        call(target)
        check("a failure on a middle file rolls back too", installed(target) == [],
              str(installed(target)))

    # A source that is missing one of the four installs none of them.
    with tempfile.TemporaryDirectory() as td:
        target = make_target(Path(td))
        staging = Path(td) / "Staging.app"
        (staging / "Contents" / "Library" / "Packages").mkdir(parents=True)
        for client in _SHELL_CLIENT_FILES:
            if client != "actionui_remote_walk.awk":
                shutil.copy2(packages / client, staging / "Contents" / "Library" / "Packages")
        out = call(target, source_bundle=staging)
        check("a source missing one program installs none", installed(target) == [],
              str(installed(target)))
        # The end state alone does not distinguish this from a rollback, so pin the gate itself:
        # it must refuse before copying, not copy and then undo.
        check("and refuses before copying, rather than rolling back after",
              "missing from AppletBuilder" in out and "Removed the ActionUI shell client set" not in out,
              out.strip()[-200:])

    # Installing into the directory the files come from is a no-op. It must not run the copy at
    # all: cp refuses identical files, and the rollback would then take the source out.
    #
    # Aimed at a throwaway copy of the source, never at the repository's own bundle. If this
    # guard regresses, this case deletes its source - and the repository's copies are the ones
    # AppletBuilder ships.
    with tempfile.TemporaryDirectory() as td:
        staging = Path(td) / "Staging.app"
        staged_packages = staging / "Contents" / "Library" / "Packages"
        staged_packages.mkdir(parents=True)
        for client in _SHELL_CLIENT_FILES:
            shutil.copy2(packages / client, staged_packages)
        target = make_target(Path(td))
        shutil.rmtree(target / "Contents" / "Library" / "Packages")
        (target / "Contents" / "Library" / "Packages").symlink_to(staged_packages)
        out = call(target, source_bundle=staging)
        check("installing into its own source leaves the source alone",
              sorted(q for q in _SHELL_CLIENT_FILES if (staged_packages / q).is_file())
              == sorted(_SHELL_CLIENT_FILES),
              str(sorted(q.name for q in staged_packages.iterdir())))
        check("and does it silently, having copied nothing",
              "Installed" not in out and "Removed" not in out, out.strip()[-200:])
        # The check above would also pass if the function had never run at all, so prove the
        # same source still installs normally into a target that is not itself.
        other = make_target(Path(td) / "second")
        call(other, source_bundle=staging)
        check("and the staged source still installs into a real target",
              installed(other) == sorted(_SHELL_CLIENT_FILES), str(installed(other)))


def main() -> int:
    if not CLI.exists():
        print(f"appletbuilder CLI not found: {CLI}", file=sys.stderr)
        return 1
    test_usage()
    test_listings()
    test_validate()
    test_prettify()
    test_preview()
    test_create_arg_errors()
    test_create_build()
    test_shell_client_install()
    print(f"\n{_passed} passed, {_failed} failed.")
    return 1 if _failed else 0


if __name__ == "__main__":
    sys.exit(main())
