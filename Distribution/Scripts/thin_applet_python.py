#!/usr/bin/env python3
"""thin_applet_python.py - closure-thin the embedded Python of an OMC applet.

This is the OMC-specific front end. Everything it knows that the generic tooling does
not is the applet layout:

    Contents/Library/Python     the embedded interpreter that gets thinned
    Contents/Resources/Scripts  the handler scripts - the app's Python entry points
    Contents/Library/Packages   third-party deps on PYTHONPATH, audited but never
                                thinned automatically

The analysis itself lives in the sibling Python-Embedding checkout, which is deliberately
app-agnostic: it is told where the distribution, the scripts and the deps are, and knows
nothing about bundles.

Two phases, with a reviewable JSON plan in between:

    plan  <App.app>    -> writes <App>.thinning-plan.json next to the bundle (commit it)
    apply <App.app>    -> performs the removal recorded in the plan, then verifies

The plan records module NAMES, not paths, so apply resolves them against the current
interpreter. When AppletBuilder reinstalls or upgrades the app's Python and wipes the
thinned dist, re-running apply with the committed plan re-thins it. That cycle is exactly
why third-party modules belong in Contents/Library/Packages rather than on the
interpreter's own site-packages.

NO HANDLER SCRIPT IS EXECUTED. An entry point's value to this analysis is its import
graph, and every import is a syntactically visible statement, so the scripts are scanned
for the imports they name and those are imported directly. --execute-entry-points
restores the old run-everything behaviour; measured on one applet scanning keeps 40.3 MB
and executing keeps 40.0 MB.

Module-level code of the IMPORTED modules still runs, so the confinement stays either
way: `plan` clones the bundle and executes only the clone, every traced subprocess runs
under sandbox-exec with no network and no writes outside the staging area, and the
interpreter's environment is scrubbed so it cannot import Python from outside the bundle.
(`apply` verifies against the real bundle when the plan's workload is an import probe -
there is no app layout to reproduce - but still under the sandbox profile.)

Shell scripts, generated configs and plists are SCANNED (never run) for `python -m NAME`
launches into Packages and for uses of Packages names, comments stripped first. That is
what discovers an out-of-process entry point - a watcher CLI, an MCP server - without
anyone having to declare it.
"""

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OMC_ROOT = os.path.dirname(os.path.dirname(HERE))
PE = os.path.join(os.path.dirname(OMC_ROOT), "Python-Embedding")
ANALYZER = os.path.join(PE, "analyze_python_deps.py")
APPLY = os.path.join(PE, "thin_with_plan.sh")

# --- the applet layout, in one place -----------------------------------------
REL_PYTHON = os.path.join("Contents", "Library", "Python")
REL_SCRIPTS = os.path.join("Contents", "Resources", "Scripts")
REL_PACKAGES = os.path.join("Contents", "Library", "Packages")
REL_SCAN = "Contents"          # app-authored text to scan for entry points


class Layout:
    def __init__(self, app):
        self.app = os.path.abspath(app.rstrip("/"))
        self.python = os.path.join(self.app, REL_PYTHON)
        self.scripts = os.path.join(self.app, REL_SCRIPTS)
        self.packages = os.path.join(self.app, REL_PACKAGES)
        self.scan = os.path.join(self.app, REL_SCAN)

    @property
    def pybin(self):
        return os.path.join(self.python, "bin", "python3")

    def default_plan(self):
        name = os.path.basename(self.app)
        name = name[:-4] if name.endswith(".app") else name
        return os.path.join(os.path.dirname(self.app), name + ".thinning-plan.json")


def fail(msg):
    print("Error: %s" % msg, file=sys.stderr)
    raise SystemExit(1)


def clone_bundle(app, dest):
    """Copy-on-write clone where the filesystem supports it. On APFS `cp -Rc` makes an
    80 MB bundle cost no measurable time and no extra disk, which is what makes cloning
    on every run affordable rather than a thing to skip."""
    for args in (["/bin/cp", "-Rc", app, dest], ["/bin/cp", "-R", app, dest]):
        if subprocess.run(args, capture_output=True).returncode == 0:
            return dest
    fail("could not clone %s" % app)


def write_sandbox_profile(path, work):
    """Confine a traced subprocess: no network, and no writes outside the staging area.

    sandbox-exec matches `subpath` against the CANONICAL path and a trailing slash
    defeats the match outright - mktemp hands back /var/folders/... which the kernel
    resolves to /private/var/..., and getconf appends a slash. Unresolved, the allow-list
    silently matches nothing and the traced process gets no writable directory at all.

    `allow default` also leaves mach-lookup open, so a daemon will act on the process's
    behalf from outside the sandbox: cfprefsd writes real preferences, pasteboard reads
    the real clipboard. Both were verified escapes, hence the explicit denials.
    """
    work_real = os.path.realpath(work)
    tmp_real = os.path.realpath(
        subprocess.run(["/usr/bin/getconf", "DARWIN_USER_TEMP_DIR"],
                       capture_output=True, text=True).stdout.strip().rstrip("/") or "/tmp")
    with open(path, "w") as f:
        f.write("""(version 1)
(allow default)
(deny network*)
(deny file-write*)
(allow file-write*
    (subpath "%s")
    (subpath "%s")
    (literal "/dev/null") (literal "/dev/stdout") (literal "/dev/stderr")
    (literal "/dev/dtracehelper") (regex #"^/dev/tty"))
(deny mach-lookup
    (global-name "com.apple.pasteboard.1")
    (global-name "com.apple.cfprefsd.daemon")
    (global-name "com.apple.cfprefsd.agent")
    (global-name "com.apple.coreservices.launchservicesd")
    (global-name "com.apple.lsd.mapdb"))
(deny process-exec*
    (literal "/usr/bin/open") (literal "/usr/bin/osascript")
    (literal "/usr/bin/defaults") (literal "/usr/bin/pbcopy") (literal "/usr/bin/pbpaste"))
""" % (work_real, tmp_real))
    return path


def analyzer_driver(pybin):
    """The analyzer needs json/ast/datetime, which an ALREADY-thinned interpreter no
    longer has - re-planning after an apply died on "No module named 'datetime'". Fall
    back to the system interpreter; the traces themselves always run under the target."""
    probe = subprocess.run([pybin, "-c", "import json, ast, datetime, argparse"],
                           capture_output=True)
    if probe.returncode == 0:
        return pybin
    for cand in ("/usr/bin/python3", sys.executable):
        if cand and os.path.exists(cand):
            return cand
    fail("the app's Python is already thinned and no system python3 was found")


def sweep_stale(*prefixes):
    """Clones abandoned by a run that was killed outright (SIGKILL leaves no chance to
    run a cleanup). Each is a full bundle copy, so they are not small.

    Both prefixes are swept whichever verb is running, because a killed `apply` leaves an
    omcverify clone that only a later `apply` would otherwise reclaim. The age threshold
    is what keeps this safe: a concurrent run's clone is minutes old, never hours."""
    import time
    tmp = tempfile.gettempdir()
    try:
        for name in os.listdir(tmp):
            if not any(name.startswith(p) for p in prefixes):
                continue
            p = os.path.join(tmp, name)
            try:
                if os.path.isdir(p) and time.time() - os.path.getmtime(p) > 7200:
                    shutil.rmtree(p, ignore_errors=True)
            except OSError:
                pass
    except OSError:
        pass


# --------------------------------------------------------------------------- plan
def cmd_plan(args):
    lay = Layout(args.app)
    if not os.path.isdir(lay.app):
        fail("not a bundle directory: %s" % lay.app)
    if not os.access(lay.pybin, os.X_OK):
        fail("no embedded Python at %s\nThis tool only thins applets that bundle their own."
             % lay.pybin)
    plan_path = args.plan or lay.default_plan()
    sweep_stale("omcthin", "omcverify")

    print("Planning thinning for %s" % os.path.basename(lay.app))
    ver = subprocess.run([lay.pybin, "--version"], capture_output=True, text=True)
    print("  Python   : %s  (%s)" % ((ver.stdout or ver.stderr).strip(), lay.python))
    if os.path.isdir(lay.packages):
        print("  Packages : %s (audited; never removed automatically)" % lay.packages)
    print("  Plan     : %s" % plan_path)
    print()

    work = tempfile.mkdtemp(prefix="omcthin")
    try:
        os.makedirs(os.path.join(work, "scratch"), exist_ok=True)
        print("Cloning the bundle so nothing in the real app is ever executed...")
        clone = clone_bundle(lay.app, os.path.join(work, os.path.basename(lay.app)))
        cl = Layout(clone)
        print("  Clone    : %s" % clone)

        aargs = [
            "--python", cl.python,
            "--root", clone, "--check-isolation",
            "--scratch", os.path.join(work, "scratch"),
            "--trace-timeout", str(args.timeout),
            "--arch", args.arch or "",
        ]
        if os.path.isdir(cl.scripts):
            aargs += ["--auto-trace-scripts", cl.scripts, "--static", cl.scripts]
        else:
            print("  (no %s - nothing to analyse)" % REL_SCRIPTS)
        if os.path.isdir(cl.packages):
            aargs += ["--packages", cl.packages]
        aargs += ["--scan-app-code", cl.scan]
        for kf in args.keep_file:
            aargs += ["--keep-file", kf]
        if args.sandbox:
            aargs += ["--sandbox-profile",
                      write_sandbox_profile(os.path.join(work, "trace.sb"), work)]
            print("  Sandbox  : no network, no writes outside the clone")
        else:
            print("  Sandbox  : DISABLED - imported modules run unconfined")
        if args.execute_entry_points:
            aargs.append("--execute-entry-points")
            print("  Closure  : EXECUTING each entry point (handler bodies will run)")
        else:
            print("  Closure  : importing what the scripts import - nothing is executed")
        if not args.inline_conditional:
            aargs.append("--no-inline-conditional")
            print("  Lazy imps: DISABLED - only literal imports are kept")
        else:
            print("  Lazy imps: conditional imports in loaded modules count as dependencies")
        for t in args.trace or []:
            aargs += ["--trace", t]
        if args.keep:
            aargs += ["--keep", args.keep]

        print("Analysing...")
        driver = analyzer_driver(lay.pybin)
        out = subprocess.run([driver, ANALYZER] + aargs + ["--print", "plan"],
                             capture_output=True, text=True)
        sys.stderr.write(out.stderr)
        if out.returncode != 0:
            fail("planning failed.")
        try:
            plan = json.loads(out.stdout)
        except ValueError as e:
            fail("planning produced no usable plan (%s)" % e)

        # The plan records paths from the clone, which is about to disappear. Rewrite the
        # ones apply has to resolve later against the real bundle.
        pkgs = plan.get("packages")
        if isinstance(pkgs, dict) and isinstance(pkgs.get("dir"), str):
            pkgs["dir"] = pkgs["dir"].replace(clone, lay.app, 1)
        tmp_out = plan_path + ".tmp"
        with open(tmp_out, "w") as f:
            json.dump(plan, f, indent=2)
        os.replace(tmp_out, plan_path)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    n = len(plan.get("remove", {}).get("modules", []))
    orphans = (plan.get("packages") or {}).get("orphan_candidates", [])
    print()
    print("Wrote thinning plan: %s  (%d modules to remove)" % (plan_path, n))
    if orphans:
        print("  packages: %d orphan candidate(s) reported for review "
              "(packages.remove is empty)" % len(orphans))
    print("Review/tweak remove.modules, commit it next to the app, then:")
    print("  %s apply \"%s\"" % (os.path.basename(sys.argv[0]), args.app))
    return 0


# --------------------------------------------------------------------------- apply
def cmd_apply(args):
    lay = Layout(args.app)
    if not os.path.isdir(lay.app):
        fail("not a bundle directory: %s" % lay.app)
    plan_path = args.plan or lay.default_plan()
    if not os.path.isfile(plan_path):
        fail("thinning plan not found: %s\nRun '%s plan \"%s\"' first (or pass --plan)."
             % (plan_path, os.path.basename(sys.argv[0]), args.app))
    sweep_stale("omcthin", "omcverify")

    # Verification may need to re-run entry points, which only makes sense inside a
    # staged copy of the app - and staging one is layout knowledge, so the generic
    # applier asks for it through a hook rather than guessing. The work dir is created
    # here and removed here; the hook only fills it.
    work = tempfile.mkdtemp(prefix="omcverify")
    cmd = [APPLY, "--python", lay.python, "--plan", plan_path]
    if args.dry_run:
        cmd.append("--dry-run")
    if args.skip_verify:
        cmd.append("--skip-verify")
    else:
        # Quoted: an app path with a space would otherwise split into two hook words.
        hook = " ".join(shlex.quote(a) for a in (
            sys.executable, os.path.abspath(__file__), "prepare-verify",
            lay.app, work, "--plan-file", plan_path))
        cmd += ["--verify-prepare", hook]
    try:
        return subprocess.run(cmd).returncode
    finally:
        shutil.rmtree(work, ignore_errors=True)


def cmd_prepare_verify(args):
    """Hook for thin_with_plan.sh: stage whatever verification needs and print the extra
    analyzer arguments, one per line.

    Called AFTER the deletions, so a clone made here shares the thinned interpreter and
    an ImportError surfaces exactly as it would in the shipped app. A plan with no
    recorded entry points has no app layout to reproduce - its workload is a generated
    import probe - so that case verifies in place and only needs the confinement.
    """
    lay = Layout(args.app)
    work = args.workdir
    os.makedirs(os.path.join(work, "scratch"), exist_ok=True)
    profile = write_sandbox_profile(os.path.join(work, "verify.sb"), work)

    plan = {}
    try:
        with open(args.plan_file or lay.default_plan()) as f:
            plan = json.load(f)
    except (OSError, ValueError):
        pass
    needs_clone = bool((plan.get("trace") or {}).get("entry_points"))

    if needs_clone:
        clone = clone_bundle(lay.app, os.path.join(work, os.path.basename(lay.app)))
        cl = Layout(clone)
        out = ["--python", cl.python, "--root", clone]
        if os.path.isdir(cl.packages):
            out += ["--packages", cl.packages]
    else:
        out = ["--python", lay.python, "--root", lay.app]
        if os.path.isdir(lay.packages):
            out += ["--packages", lay.packages]
    out += ["--sandbox-profile", profile, "--scratch", os.path.join(work, "scratch")]
    print("\n".join(out))
    return 0


def main(argv):
    p = argparse.ArgumentParser(
        description="Closure-thin the embedded Python of an OMC applet (plan/apply).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="The plan's `packages` section is an AUDIT, not a removal list: entries are\n"
               "classified as imported, required by another installed distribution, named in\n"
               "the app's own shell/config text, backing a console script, of unknown\n"
               "provenance, or an orphan candidate. packages.remove is emitted EMPTY on\n"
               "purpose - an unimported dependency is usually a lazy TLS/auth/timezone path,\n"
               "not dead weight. Move a name into it by hand, then re-run apply.")
    sub = p.add_subparsers(dest="verb", required=True)

    sp = sub.add_parser("plan", help="analyse the applet and write a reviewable plan")
    sp.add_argument("app")
    sp.add_argument("--plan", help="plan file to write (default: next to the bundle)")
    sp.add_argument("--trace", action="append", default=[],
                    help="extra workload for out-of-process code, as the args AFTER "
                         "`python3 -X importtime` (no leading python3). Repeatable.")
    sp.add_argument("--arch", default="", help="also record an arm64|x86_64 slice in the plan")
    sp.add_argument("--keep", default="", help="comma-separated modules to force-keep")
    sp.add_argument("--timeout", type=float, default=30, help="seconds before a trace is killed")
    sp.add_argument("--no-sandbox", dest="sandbox", action="store_false",
                    help="do not confine traced subprocesses (debugging the tooling only)")
    sp.add_argument("--execute-entry-points", action="store_true",
                    help="run each handler script instead of importing what it imports")
    sp.add_argument("--no-inline-conditional", dest="inline_conditional", action="store_false",
                    help="keep only literal imports (NOT recommended: lazily imported "
                         "modules get removed and the app crashes on an untraced path)")
    sp.add_argument("--keep-file", action="append", default=[],
                    help="file of extra module names to force-keep, one per line - for "
                         "plugins loaded by a name no analysis can discover. Repeatable.")
    sp.set_defaults(fn=cmd_plan)

    sa = sub.add_parser("apply", help="perform the plan's removal, then verify")
    sa.add_argument("app")
    sa.add_argument("--plan", help="plan file to read (default: next to the bundle)")
    sa.add_argument("--dry-run", action="store_true", help="show what would be removed")
    sa.add_argument("--skip-verify", action="store_true", help="do not verify afterwards")
    sa.set_defaults(fn=cmd_apply)

    sh = sub.add_parser("prepare-verify", help=argparse.SUPPRESS)
    sh.add_argument("app")
    sh.add_argument("workdir")
    sh.add_argument("--plan-file", default=None)
    sh.set_defaults(fn=cmd_prepare_verify)

    args = p.parse_args(argv)
    for tool, what in ((ANALYZER, "analyze_python_deps.py"), (APPLY, "thin_with_plan.sh")):
        if not os.path.exists(tool):
            fail("Python-Embedding not found at %s (missing %s)\n"
                 "Fetch it as a sibling of OMC: https://github.com/abra-code/Python-Embedding"
                 % (PE, what))
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
