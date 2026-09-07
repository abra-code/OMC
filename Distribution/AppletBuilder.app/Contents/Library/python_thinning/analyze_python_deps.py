#!/usr/bin/env python3
"""analyze_python_deps.py - compute the precise module closure an embedded Python needs.

Part of the Python-Embedding toolkit. Use it to decide what is safe to strip from a
relocatable/embedded CPython: it reports which top-level stdlib and site-packages
modules are actually reachable from your app, and which are dead weight.

WHY NOT TRANSITIVE STATIC ANALYSIS
  modulefinder follows every `import` it finds in the bytecode, including imports in
  dead branches (e.g. shutil naming tarfile/zlib in archive helpers you never call,
  argparse -> gettext -> locale). On a real app it ends up "needing" almost the whole
  stdlib, so it badly OVER-keeps. It also cannot see across a subprocess boundary
  (an app that shells out to a bin script like `watchmedo` looks like it imports
  nothing). Measured here: a static fixpoint over import edges recovers only half the
  saving AND is app-independent - two unrelated apps produced keep sets sharing 243
  of ~245 names, because it measures the stdlib's import graph rather than the app.

WHAT WORKS
  Take the import NAMES statically - they are syntactically visible, including the ones
  in branches that never run - and resolve their closure DYNAMICALLY, by importing them
  under the target interpreter with `-X importtime`. Real imports do not pull dead
  branches the way modulefinder does. Then DELETE the complement and re-attempt the
  same imports: a missed dependency is an immediate ImportError, not a silent break.

MODES (combine freely; all results are unioned into the KEEP set)
  --auto-trace-scripts DIR
                       derive the closure from the app's scripts in DIR, with no
                       hand-written workload. Repeatable. By DEFAULT nothing in DIR is
                       executed: every Python source file - *.py, and extension-less
                       files with a python shebang, which is how a CLI helper ships - is
                       AST-scanned for the imports it names at any depth, and those are
                       imported directly. Imports of sibling scripts in the same DIR are
                       dropped as seeds - they are not dependencies of the distribution,
                       and each sibling is scanned in its own right anyway.
                       --execute-entry-points instead RUNS each script. That adds only
                       the branches which happen to run, and costs executing a handler
                       with none of its usual arguments; in one measured app scanning kept
                       40.3 MB and executing kept 40.0 MB.
                       Either way, module-level code of the imported modules runs, so
                       ALWAYS pair this with --sandbox-profile.

  KNOWN BLIND SPOT: a module loaded by computed name - importlib.import_module(var),
  __import__(name), a codec looked up by string - is invisible to both modes, because
  the name is not in the source. -X importtime does not even log import_module's target
  (only its nested C extension), so tracing does not save you either. Use --keep for
  those. A forced name is IMPORTED, not just listed, so whatever it needs is kept with
  it; if it belongs to the distribution being thinned it also becomes a verification
  seed, and if it cannot be imported at all it is recorded as already-missing, which
  means a typo there is silently inert rather than an error.
  --scan-app-code DIR  read (never run) the app's own text under DIR to find entry points
                       nothing declares. Repeatable. Two finds: `python -m NAME` launches
                       into --packages, and extension-less files with a python shebang -
                       CLI helpers that a handler or a shell script starts BY PATH, so no
                       `-m` and no import statement anywhere names them. Each such tool's
                       DIRECTORY is then analyzed exactly as --auto-trace-scripts would,
                       which is what reads the package sitting beside it.
  --trace "CMD ARGS"   run CMD under the embedded interpreter with -X importtime and
                       record every module imported. Repeatable. CMD's first token is
                       usually a bin script (e.g. .../bin/watchmedo) or a .py file.
                       Use --trace-timeout for commands that block (watchers/servers).
                       Still needed for code served OUT OF PROCESS from --packages,
                       which no scan of the app's own scripts can see.
  --static DIR         AST-scan every *.py in DIR for direct imports (repeatable). A
                       coverage cross-check for --trace/--execute-entry-points: a module
                       your source names but the run never loaded means an unexercised
                       path. It is VACUOUS in the default imports-only mode, where the
                       seeds come from the same scan, so nothing can be uncovered.
  --runtime-log FILE   newline-separated module names captured by your own harness
                       (e.g. dumping sorted(sys.modules)). Repeatable.

CONDITIONAL IMPORTS (on by default; --no-inline-conditional turns it off)
  A trace records the branches it happened to take. Modules import lazily all the time -
  argparse imports _colorize inside a function, shutil imports zipfile/tarfile only in
  make_archive, hashlib imports _hashlib in a try block - so a trace-only closure is
  precise about one run and wrong about the program.
  Whether a branch fires is not something a dependency scan can decide, so it should not
  try: if a loaded module CAN import X, X is a dependency. After tracing, every
  conditional import found in the modules that actually loaded is written into a
  generated _inlines.py as an unconditional import, and that file is traced too.
  Measured on a real app this is not a nicety. Without it the thinned interpreter raises
  ModuleNotFoundError on `import hashlib` and on shutil.make_archive - breakage on paths
  the entry points never took, which verification cannot catch because verification only
  re-runs traced paths. It costs ~12 MB there, over half of it libcrypto.dylib, which is
  retained precisely because hashlib really does prefer _hashlib when it exists.

ISOLATION (traces execute real code; treat every trace as running the app)
  --sandbox-profile F  wrap every traced subprocess in `sandbox-exec -f F`. Point it at
                       a profile that denies network and denies writes outside a scratch
                       dir. Without this, tracing an entry point lets it do whatever it
                       would normally do, in whatever environment it happens to find.
  --root DIR           the tree the embedded Python belongs to. Traces then run
                       with a scrubbed environment (no inherited PYTHONPATH/PYTHONHOME,
                       no user site-packages) so the interpreter cannot import Python
                       code from outside ROOT, and --check-isolation can prove it.
  --check-isolation    assert every sys.path entry resolves inside --root, and fail
                       if not. A stray PYTHONPATH silently shadowing one of your modules is
                       otherwise invisible and would poison the whole closure.

PACKAGES (third-party deps installed beside the interpreter, never on its site-packages)
  --packages DIR       the app's Packages dir. It is put on PYTHONPATH for traces, and
                       audited into the plan's `packages` section. Entries there are
                       REPORT-ONLY: `packages.remove` is emitted empty, because "the
                       trace never imported it" is NOT evidence a dependency is dead -
                       TLS, auth and timezone deps are all reached only on paths a
                       build-time trace never takes. The report classifies each entry by
                       the far stronger signal of the installed dependency graph
                       (Requires-Dist across every dist-info present), so a genuine
                       orphan - imported by nothing AND required by nothing - is visible
                       without being acted on.

  --python DIR         embedded Python distribution to analyze. Default: the
                       interpreter running this script. Run this script WITH the
                       interpreter you intend to thin for the most accurate result.
  --keep NAME[,NAME]   extra top-level names to force into KEEP (belt-and-suspenders).

OUTPUT (--print)
  report               human-readable breakdown (default).
  removable-names      newline list of top-level names not in the closure.
  removable-paths      newline list of their filesystem paths.
  keep-names           newline list of the closure (kept) names.
  plan                 a JSON THINNING PLAN: the resolved removal list plus the trace
                       provenance and chosen options (arch, include/, bytecode). Commit
                       it next to the app and apply it later with thin_with_plan.sh -
                       the plan is reviewable, tweakable, and re-applicable after a
                       Python reinstall wipes the thinned dist.
  --arch ARCH          record this target arch (arm64|x86_64) in --print plan.
  --no-extras          record "do NOT remove include/ + bytecode" in --print plan.

APPLY MODE
  --plan FILE          resolve removals from an existing plan instead of tracing.
                       Combine with --print removable-paths (or removable-names) to
                       map the plan's module names to paths in --python. This is how
                       thin_with_plan.sh turns a committed plan into deletions,
                       resolved against the CURRENT distribution (so it survives a
                       Python reinstall).

EXAMPLES
  This tool knows nothing about how your app is laid out. Point it at the embedded
  distribution, the directory holding your Python entry points, and (if you keep
  third-party deps outside the interpreter) that directory - whatever they are called.

  # Plan: derive the closure from your scripts and emit a committable plan.
  PY=/path/to/embedded/python
  "$PY/bin/python3" analyze_python_deps.py --python "$PY" \
      --auto-trace-scripts /path/to/your/scripts \
      --packages /path/to/your/deps \
      --root /path/to/your/app-root --check-isolation \
      --sandbox-profile /tmp/trace.sb \
      --arch arm64 --print plan > app.thinning-plan.json

  # A workload the script scan cannot see (something launched out of process):
  #     --trace "-m your_pkg.cli --serve"

  # Apply (done by thin_with_plan.sh): resolve the plan to deletable paths.
  "$PY/bin/python3" analyze_python_deps.py --python "$PY" \
      --plan app.thinning-plan.json --print removable-paths
"""

import argparse
import ast
import datetime
import json
import os
import re
import shlex
import subprocess
import sys
import time


# --------------------------------------------------------------------------- discovery
def find_stdlib(python_dir):
    libdir = os.path.join(python_dir, "lib")
    for entry in sorted(os.listdir(libdir)):
        if entry.startswith("python3"):
            full = os.path.join(libdir, entry)
            if os.path.isdir(full):
                return full
    raise SystemExit("no lib/python3* found under %s" % python_dir)


# --------------------------------------------------------------------------- isolation
class Isolation:
    """How a traced subprocess is confined. Tracing runs the app's real code, so this
    decides what that code can reach: which Python it may import, what it may write,
    and whether it gets a network."""

    def __init__(self, root=None, packages=None, scripts=None, sandbox_profile=None,
                 scratch=None):
        self.root = os.path.abspath(root) if root else None
        self.packages = packages
        self.scripts = scripts
        self.sandbox_profile = sandbox_profile
        self.scratch = scratch or os.path.join(os.environ.get("TMPDIR", "/tmp"), "pytrace")

    def env(self):
        """A scrubbed environment. The inherited one is not safe to trace under: a
        PYTHONPATH left over from a shell session shadows your own modules silently, and
        the resulting closure is of the developer's machine rather than of the app.
        Proven, not assumed - with an outside PYTHONPATH set, `import lib_zip` resolves
        to the outside copy."""
        env = dict(os.environ)
        # _PYTHON_SYSCONFIGDATA_NAME belongs here too: it redirects sysconfig to a data
        # module for a DIFFERENT build, so an inherited one silently changes which
        # modules the traced code loads.
        for var in ("PYTHONPATH", "PYTHONHOME", "PYTHONSTARTUP", "PYTHONUSERBASE",
                    "_PYTHON_SYSCONFIGDATA_NAME"):
            env.pop(var, None)
        # DYLD_* too. The embedded interpreter is ad-hoc signed with no library
        # validation, so an inherited DYLD_INSERT_LIBRARIES would load code from outside
        # the bundle - and check() cannot see that, because it only inspects sys.path.
        for var in [k for k in env if k.startswith("DYLD_")]:
            env.pop(var, None)
        env["PYTHONNOUSERSITE"] = "1"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        path = [p for p in (self.packages, self.scripts) if p and os.path.isdir(p)]
        if path:
            env["PYTHONPATH"] = os.pathsep.join(path)
        env["HOME"] = self.scratch
        env["TMPDIR"] = self.scratch
        return env

    def argv(self, python_bin, args, importtime=True):
        """-s keeps user site-packages out. sandbox-exec, when a profile is given, is
        what actually stops a misbehaving entry point from touching anything real."""
        cmd = [python_bin, "-s"]
        if importtime:
            cmd += ["-X", "importtime"]
        cmd += list(args)
        if self.sandbox_profile:
            cmd = ["/usr/bin/sandbox-exec", "-f", self.sandbox_profile] + cmd
        return cmd

    def check(self, python_bin):
        """Prove the interpreter cannot import Python code from outside --root.
        Returns a list of offending sys.path entries (empty means contained)."""
        if not self.root:
            return []
        prog = ("import sys, json, os;"
                "print(json.dumps([p for p in sys.path if p and os.path.exists(p)]))")
        # Built without importtime rather than filtered afterwards: token filtering used to
        # strip `-X importtime` and leave any OTHER -X option's value as a stray argument,
        # which the interpreter then tried to run as a script path.
        cmd = self.argv(python_bin, ["-c", prog], importtime=False)
        out = subprocess.run(cmd, capture_output=True, text=True, env=self.env())
        try:
            entries = json.loads(out.stdout.strip().splitlines()[-1])
        except (ValueError, IndexError):
            return ["<could not read sys.path: %s>" % (out.stderr.strip()[-200:] or "no output")]
        return [p for p in entries if not os.path.abspath(p).startswith(self.root)]


MISSING_RE = re.compile(r"ModuleNotFoundError: No module named ['\"]([\w.]+)['\"]")
# Breakage that thinning causes but that is NOT a ModuleNotFoundError: a package whose
# submodule was removed raises "cannot import name", and deleting a dylib (or slicing an
# arch) turns an extension module into a dlopen failure. Judging on missing module names
# alone declares all of those healthy.
IMPORT_FAIL_RE = re.compile(
    r"ImportError: cannot import name|ImportError: dlopen|Library not loaded|"
    r"Fatal Python error|Symbol not found", re.IGNORECASE)
# sandbox-exec refusing a profile (65), not executable (126), not found (127). The
# process never ran, so its silence means nothing.
NO_START_CODES = (65, 126, 127)


def missing_modules(err):
    """Top-level names a ModuleNotFoundError complained about.

    An entry point run outside its normal environment fails constantly for reasons that
    have nothing to do with the interpreter: an entry point that shells out to a helper
    binary its host app normally provides raises FileNotFoundError and exits non-zero when
    run standalone. Treating any traceback or exit code as
    failure would condemn every plan - hence judging on import evidence instead. See
    import_failed() for the breakage this pattern alone would miss."""
    return {m.split(".")[0] for m in MISSING_RE.findall(err)}


def import_failed(err):
    """True when stderr shows an import breaking for a reason with no module name."""
    return bool(IMPORT_FAIL_RE.search(err))


def timed_out_marker(err):
    return "TRACE-TIMED-OUT" in err


def _parse_importtime(err, dotted=False):
    """Top-level names imported, or the fully-qualified ones when dotted=True.

    The dotted form matters for conditional-import inlining: it says `urllib.parse`
    loaded and `urllib.request` did not, so only the file that really ran gets scanned.
    Collapsing to `urllib` first would force a walk of the whole package and drag in
    every sibling's imports."""
    names = set()
    for line in err.splitlines():
        if "import time:" not in line:
            continue
        parts = line.split("|")
        if len(parts) < 3:
            continue
        name = parts[-1].strip()                     # fully-qualified, indented by depth
        if name and name != "imported package":
            names.add(name if dotted else name.split(".")[0])
    return names


# --------------------------------------------------------------------------- signals
def trace_closure(python_bin, cmd, timeout, iso=None):
    """Run `python -X importtime CMD` and return the set of top-level module names it
    imported. Works across spawned bin scripts. Killing a blocking command after
    timeout still yields a complete closure because importtime flushes per import,
    and all imports happen during startup before the watch/serve loop."""
    parts = shlex.split(cmd)
    if parts and os.path.basename(parts[0]).startswith("python"):
        print("# trace warn: --trace already runs under the embedded interpreter; drop the "
              "leading '%s' (pass the script/bin + args only)." % os.path.basename(parts[0]),
              file=sys.stderr)
    return _run_trace(python_bin, parts, timeout, iso)[0]


def _run_trace(python_bin, parts, timeout, iso=None):
    """Run one traced subprocess; return (top-level names, dotted names, stderr text)."""
    iso = iso or Isolation()
    os.makedirs(iso.scratch, exist_ok=True)
    proc = subprocess.Popen(iso.argv(python_bin, parts), stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE, env=iso.env(), cwd=iso.scratch)
    try:
        _out, err = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        _out, err = proc.communicate()
        err += b"\nTRACE-TIMED-OUT\n"   # a truncated closure must be visible, not silent
    text = err.decode("utf-8", "replace")
    return _parse_importtime(text), _parse_importtime(text, dotted=True), text


def has_python_shebang(path):
    """True for a file whose first line is a `#!` naming python.

    A command-line tool is normally shipped WITHOUT the .py, so an extension test alone
    misses exactly the files that are entry points. Read as bytes and only the first
    line: the tree being walked also holds Mach-O binaries and multi-megabyte data files,
    and neither needs decoding to answer this."""
    try:
        with open(path, "rb") as f:
            first = f.readline(256)
    except OSError:
        return False
    return first.startswith(b"#!") and b"python" in first.lower()


def is_python_source(path):
    """A .py, or an extension-less file with a python shebang. Both are Python source
    that the app runs, so both are scanned - and, under --execute-entry-points, run."""
    fn = os.path.basename(path)
    if not os.path.isfile(path):
        return False          # a directory named *.py is not a script to run
    if fn.endswith(".py"):
        return True
    return "." not in fn and has_python_shebang(path)


def canon(path):
    """Canonical absolute path. `abspath` alone does not resolve symlinks, and on macOS
    that is not academic: a caller's /tmp/... never matches a walk of /private/tmp/...,
    and a symlinked tool reports the directory of the LINK rather than of the file, which
    is not where its sibling package lives."""
    return os.path.realpath(os.path.abspath(path))


def _py_files_under(root, exclude=()):
    """Every Python source file at any depth, so a package sibling's dependencies are
    read too. `exclude` drops whole subtrees - a tool discovered high in a bundle would
    otherwise drag the installed Packages and the interpreter's own stdlib into the
    app's seed set, where they are audited and thinned by different rules."""
    exclude = tuple(canon(e) for e in exclude if e)
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        ap = canon(dirpath)
        if any(ap == e or ap.startswith(e + os.sep) for e in exclude):
            dirnames[:] = []
            continue
        dirnames[:] = [d for d in dirnames if d != "__pycache__"]
        out += [p for p in (os.path.join(dirpath, fn) for fn in filenames)
                if is_python_source(p)]
    return out


def all_imports_of_dir(scripts_dir, exclude=()):
    """Every import any script names, at any nesting depth, as full dotted names.
    `from X import Y` also yields X.Y, since Y is often a submodule; when it is only a
    function the import fails harmlessly and contributes nothing.

    Sibling modules are EXCLUDED AS SEEDS, and every sibling is SCANNED instead. Those
    two halves are one rule and neither is safe alone.

    Dropping the name is what keeps plan and verify symmetric: `from lib_zip import *`
    names a module in this same directory, not a distribution dependency, and it resolves
    at plan time only because this directory is on PYTHONPATH. Verification regenerates
    the probe without it, so a surviving sibling seed fails there and gets blamed on
    thinning.

    Scanning it is what keeps the closure honest. A sibling's own imports ARE
    distribution dependencies, so if its name is dropped without reading its contents,
    everything it needs silently leaves the closure - and verification cannot object,
    because the seed that would have failed is gone too. Measured: a package directory
    beside the scripts importing sqlite3 produced a plan that removed sqlite3, verified
    green, and left the handler raising ModuleNotFoundError.

    So the scan is recursive, and EVERY directory entry is a sibling name - a package or
    a namespace package (a plain directory is importable in Python 3 as well, which an
    __init__.py test misses and which then produces exactly the false failure above).

    Extension-less files with a python shebang are scanned as source too. A CLI helper is
    shipped without the .py, so a `.py` test skips the one file in the directory that is
    actually an entry point - and with it the imports of the package sitting beside it."""
    entries = os.listdir(scripts_dir)
    stems = {fn[:-3] for fn in entries if fn.endswith(".py")}
    stems |= {fn for fn in entries if os.path.isdir(os.path.join(scripts_dir, fn))}
    seeds = set()
    for path in sorted(_py_files_under(scripts_dir, exclude)):
        rel = os.path.relpath(path, scripts_dir)
        try:
            with open(path, encoding="utf-8") as f:
                tree = ast.parse(f.read())
        except (OSError, SyntaxError, UnicodeDecodeError, ValueError) as e:
            print("# parse warn: %s: %s" % (rel, e), file=sys.stderr)
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for al in node.names:
                    seeds.add(al.name)
            elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                seeds.add(node.module)
                for al in node.names:
                    seeds.add(node.module + "." + al.name)
    return {s for s in seeds if s.split(".")[0] not in stems}


def _imports_of_file(path):
    """Every import a single file names, at any depth, as dotted names."""
    out = set()
    try:
        tree = ast.parse(open(path, encoding="utf-8").read())
    except (OSError, SyntaxError, UnicodeDecodeError, ValueError):
        return out
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for al in node.names:
                out.add(al.name)
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            out.add(node.module)
    return out


def package_import_surface(packages_dir, limit_dists=None):
    """Every module an INSTALLED PACKAGE could import, from its whole source, not from
    the part that happened to load.

    This closes the biggest remaining hole in the closure. `inline_conditional_imports`
    hoists conditional imports out of modules that LOADED, but which FILES of a
    distribution load is itself a branch decision: `mcp/__init__.py` loading tells you
    nothing about `mcp/server/fastmcp/...`, which loads only when a server starts. A
    stdlib module imported solely by such a file is invisible to the trace, gets removed,
    and breaks at runtime on a path no verification re-runs.

    Measured on two apps before this existed: 14 and 2 top-level names were imported by
    package source and removed by the plan - including `uuid`, `configparser`, `getpass`,
    `zoneinfo`, `tomllib` and `pty`.

    So installed packages get the same treatment as the app's own scripts: every import
    named anywhere in the tree, at any nesting depth, is a dependency. The whole tree is
    scanned, not just the reached distributions, because an unreached distribution is
    still shipped and still importable - which is exactly why the audit refuses to delete
    it - so its imports have to be satisfiable too.

    The tree's OWN top-level names are excluded, for the same reason sibling scripts are:
    they are provided by this directory, not by the distribution being thinned.
    """
    provided = set()
    for e in os.listdir(packages_dir):
        if e.startswith(".") or e in ("bin", "__pycache__"):
            continue
        if e.endswith((".dist-info", ".egg-info")):
            continue
        provided.add(e[:-3] if e.endswith(".py") else e.split(".")[0])
    # When a scope is given, walk only what the reachable distributions install. An
    # unreachable distribution's imports are not kept - which is the whole point of
    # scoping - so it must be reported as unreachable rather than silently protected.
    allowed = None
    if limit_dists is not None:
        prov, _req, _auth = dist_graph(packages_dir)
        allowed = set()
        for dist in limit_dists:
            allowed |= prov.get(dist, set()) | _dist_aliases(dist)
        allowed &= provided
    seeds, files = set(), 0
    for entry in sorted(os.listdir(packages_dir)):
        if entry.startswith(".") or entry in ("__pycache__",):
            continue
        top = entry[:-3] if entry.endswith(".py") else entry.split(".")[0]
        if allowed is not None and entry != "bin" \
                and not entry.endswith((".dist-info", ".egg-info")) \
                and top not in allowed:
            continue
        path = os.path.join(packages_dir, entry)
        if os.path.isfile(path) and entry.endswith(".py"):
            files += 1
            seeds |= _imports_of_file(path)
            continue
        for dirpath, dirnames, filenames in os.walk(path):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in filenames:
                if not fn.endswith(".py"):
                    continue
                files += 1
                seeds |= _imports_of_file(os.path.join(dirpath, fn))
    seeds = {s for s in seeds if s.split(".")[0] not in provided}
    return seeds, files, len(provided)


def entry_point_modules(packages_dir):
    """Modules named in dist-info entry_points.txt. A console script or a plugin group
    is loaded by NAME out of that metadata at runtime - `importlib.metadata` reads the
    string and imports it - so no import statement anywhere names them. This is the one
    dynamic-import mechanism that can be resolved exactly, because the name is recorded
    on disk rather than computed."""
    out = set()
    if not packages_dir or not os.path.isdir(packages_dir):
        return out
    for e in os.listdir(packages_dir):
        ep = os.path.join(packages_dir, e, "entry_points.txt")
        if not e.endswith((".dist-info", ".egg-info")) or not os.path.isfile(ep):
            continue
        try:
            for line in open(ep, encoding="utf-8"):
                line = line.strip()
                if line.startswith("[") or "=" not in line:
                    continue
                target = line.split("=", 1)[1].strip()
                mod = target.split(":")[0].strip()
                if mod and all(p.isidentifier() for p in mod.split(".")):
                    out.add(mod)
        except OSError:
            continue
    return out


def pth_imports(*dirs):
    """Modules imported by .pth files. `site` executes any .pth line beginning with
    `import`, before the app's own code runs, so these are unconditional startup
    dependencies that no import statement in the app names."""
    out = set()
    for d in dirs:
        if not d or not os.path.isdir(d):
            continue
        for entry in os.listdir(d):
            if not entry.endswith(".pth"):
                continue
            try:
                with open(os.path.join(d, entry), encoding="utf-8", errors="replace") as f:
                    for line in f:
                        line = line.strip()
                        if not line.startswith(("import ", "import\t")):
                            continue
                        # `import foo; foo.install()` is one line, semicolon-separated.
                        for part in line.split(";"):
                            part = part.strip()
                            if not part.startswith("import "):
                                continue
                            for nm in part[len("import "):].split(","):
                                nm = nm.strip().split()[0] if nm.strip() else ""
                                if nm and all(p.isidentifier() for p in nm.split(".")):
                                    out.add(nm)
            except OSError:
                continue
    return out


def dash_m_in_sources(roots, known):
    """`python -m NAME` launched from INSIDE installed-package source.

    The app-code sweep cannot see these: a distribution that shells out to a helper module
    carries that string in its own .py, and the module it names must survive thinning.
    Protect-only - a hit keeps something, it never marks anything unused - so a regex that
    misunderstands a line costs nothing."""
    out = set()
    for root in roots:
        if not root or not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in filenames:
                if not fn.endswith((".py", ".sh")):
                    continue
                path = os.path.join(dirpath, fn)
                try:
                    text = open(path, encoding="utf-8", errors="replace").read()
                except OSError:
                    continue
                text = decomment(path, text)
                for m in DASH_M_RE.finditer(text):
                    name = m.group(1)
                    if name.split(".")[0] in known:
                        out.add(name)
    return out


DATA_EXTS = (".json", ".yaml", ".yml", ".toml", ".cfg", ".ini", ".plist", ".conf")
DOTTED_RE = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+)\b")


def data_file_names(roots, known, exclude=()):
    """Dotted module paths sitting in CONFIG DATA rather than in code.

    `logging.config.dictConfig` takes `"()": "pkg.mod.Class"`. Plugin registries, DI
    containers and job definitions all do the same. The string is a module path that
    nothing imports statically and no trace reaches unless that config is loaded.

    Reverse lookup only: the candidate must already be a name this distribution provides.
    That is what keeps it from being noise - it can only ever protect a name, never
    condemn one, so a false match costs a few KB and a missed one costs nothing extra."""
    hits = {}
    ex = [os.path.abspath(e) for e in exclude if e]
    for root in roots:
        if not root or not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            if any(os.path.abspath(dirpath).startswith(e) for e in ex):
                dirnames[:] = []
                continue
            for fn in filenames:
                if not fn.endswith(DATA_EXTS):
                    continue
                path = os.path.join(dirpath, fn)
                try:
                    text = open(path, encoding="utf-8", errors="replace").read()
                except OSError:
                    continue
                for m in DOTTED_RE.finditer(text):
                    top = m.group(1).split(".")[0]
                    if top in known:
                        hits.setdefault(top, set()).add(os.path.basename(path))
    return hits


DYNAMIC_IMPORT_RE = re.compile(
    r"\b(?:importlib\.import_module|__import__|importlib\.__import__)\s*\(")


def dynamic_import_sites(roots):
    """Where the analysis is PROVABLY blind: a call that imports a name built at runtime.

    Nothing static can resolve these, and a trace sees them only if it takes the branch.
    They are not fixed here - they are reported, so the one thing a reviewer cannot do is
    be unaware of them. A literal argument is skipped: `import_module("json")` is as
    visible as an import statement."""
    sites = {}
    for root in roots:
        if not root or not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in filenames:
                if not fn.endswith(".py"):
                    continue
                path = os.path.join(dirpath, fn)
                try:
                    tree = ast.parse(open(path, encoding="utf-8").read())
                except (OSError, SyntaxError, UnicodeDecodeError, ValueError):
                    continue
                for node in ast.walk(tree):
                    if not isinstance(node, ast.Call):
                        continue
                    text = ""
                    if isinstance(node.func, ast.Attribute):
                        text = node.func.attr
                    elif isinstance(node.func, ast.Name):
                        text = node.func.id
                    if text not in ("import_module", "__import__"):
                        continue
                    if node.args and isinstance(node.args[0], ast.Constant) \
                            and isinstance(node.args[0].value, str):
                        continue          # a literal name is not dynamic
                    sites.setdefault(os.path.relpath(path, root), []).append(node.lineno)
    return sites


def imports_only_closure(python_bin, scripts_dir, timeout, iso=None, exclude=()):
    """Derive the closure by importing what the scripts import, WITHOUT running them.

    An entry point's value to this analysis is its import graph, and every import is a
    syntactically visible statement - so collect them all with the AST and import them
    directly. Executing the script adds nothing except the branches it happens to take,
    and costs the risk of running a handler with none of its usual arguments.

    Measured on a real app this produces effectively the same thinning - 40.3 MB scanning
    against 40.0 MB executing, the 0.3 MB being the price of a superset - while covering
    the executed closure apart from rlcompleter/usercustomize, and it finds imports in
    branches execution never reached.

    Module-level code of the imported modules still runs, so the sandbox is still
    required - a bundled server package printed banners and closed stdout on import. What
    stops running is the handler's own body, which is the part that deletes files."""
    seeds = all_imports_of_dir(scripts_dir, exclude)
    if not seeds:
        return set(), set(), set(), set()
    iso = iso or Isolation()
    os.makedirs(iso.scratch, exist_ok=True)
    mark = _probe_mark()
    path = write_import_probe(os.path.join(iso.scratch, "_imports.py"), seeds, mark)
    names, dotted, err = _run_trace(python_bin, [path], timeout, iso)
    if timed_out_marker(err):
        print("# imports warn: the import sweep timed out; the closure is truncated. "
              "Raise --trace-timeout.", file=sys.stderr)
    elif not probe_completed(err, mark):
        print("# imports warn: the import sweep DID NOT FINISH - module-level code killed "
              "the process outright. The closure covers only a prefix of the imports.",
              file=sys.stderr)
    # Seeds that already fail on the FULL interpreter: `from urllib.parse import unquote`
    # contributes the seed urllib.parse.unquote, which is a function, not a module.
    # Baselining them keeps verification from blaming thinning for it later.
    baseline = probe_failures(err, mark)
    return names, dotted, seeds, baseline


def probe_seeds(python_bin, seeds, timeout, iso, label, probe_name="_probe.py"):
    """Import an arbitrary seed set and return what loaded. Same machinery as the app's
    import sweep, so whatever loads here also feeds the conditional-import fixpoint."""
    if not seeds:
        return set(), set(), set()
    iso = iso or Isolation()
    os.makedirs(iso.scratch, exist_ok=True)
    mark = _probe_mark()
    path = write_import_probe(os.path.join(iso.scratch, probe_name), seeds, mark)
    names, dotted, err = _run_trace(python_bin, [path], timeout, iso)
    if timed_out_marker(err):
        print("# %s warn: the import sweep timed out; the closure is truncated. "
              "Raise --trace-timeout." % label, file=sys.stderr)
    elif not probe_completed(err, mark):
        print("# %s warn: the import sweep DID NOT FINISH - module-level code killed the "
              "process outright. The closure covers only a prefix of the seeds, so the "
              "plan may remove something a later seed needs." % label, file=sys.stderr)
    return names, dotted, probe_failures(err, mark)


PROBE_HEADER = """\
# generated: every import the app's scripts name, attempted independently. A failure is
# reported rather than raised, so one bad name cannot truncate the sweep.
#
# BaseException, not Exception: module-level code that calls sys.exit() raises SystemExit,
# which Exception does not catch. Measured - a bundled package did exactly that, the sweep
# died after 183 of 308 names, and verification passed on the prefix while a removed
# module needed by a later seed went unnoticed.
#
# The DONE marker is the proof the sweep finished. os._exit() or a segfault in
# module-level code still kills the process outright, and without a completion marker a
# truncated sweep is indistinguishable from a clean one.
import sys
for _n in %r:
    try:
        __import__(_n)
    except ImportError:
        print("%s", _n, file=sys.stderr)
    except BaseException:
        pass
print("%s-DONE", file=sys.stderr)
"""
# The marker carries a per-run nonce. Module-level code runs during the sweep, so a
# module that printed a fixed marker to stderr could inject a name into the baseline -
# and a baselined name is masked in every later verification of the committed plan.
PROBE_MARK_PREFIX = "PROBE-IMPORT-FAILED"


def _probe_mark():
    return "%s-%d-%d" % (PROBE_MARK_PREFIX, os.getpid(), int(time.time() * 1000) % 1000000)


def write_import_probe(path, seeds, mark):
    with open(path, "w", encoding="utf-8") as f:
        f.write(PROBE_HEADER % (sorted(seeds), mark, mark))
    return path


def probe_completed(err, mark):
    """Did the sweep reach the end? A prefix of the seeds proves nothing about the rest."""
    return ("%s-DONE" % mark) in err


def probe_failures(err, mark):
    out = set()
    for ln in err.splitlines():
        parts = ln.split()
        if len(parts) > 1 and parts[0] == mark:
            out.add(parts[1])
    return out


def auto_trace_scripts(python_bin, scripts_dir, timeout, iso=None):
    """Trace every Python script in scripts_dir as its own entry point - *.py, and
    extension-less files with a python shebang, which is how a CLI helper is shipped.
    Returns (keep_names, per_script, baseline_missing) - the last being the modules that
    were ALREADY unimportable before any thinning, so verification can tell a
    pre-existing gap from one this plan created.

    Each script runs in its own subprocess: entry points are not import-safe, and one
    that closes stdout or exits the interpreter would otherwise take the whole scan
    with it. (Observed: importing a bundled server package printed banners and closed
    stdout.)"""
    keep = set()
    per = {}
    baseline = set()
    dotted = set()
    for fn in sorted(os.listdir(scripts_dir)):
        if not is_python_source(os.path.join(scripts_dir, fn)):
            continue
        names, dots, err = _run_trace(python_bin, [os.path.join(scripts_dir, fn)], timeout, iso)
        per[fn] = len(names)
        keep |= names
        dotted |= dots
        baseline |= missing_modules(err)
    return keep, per, baseline, dotted


def strip_shell_comments(text):
    """Drop `#` comments from shell source, leaving strings intact.

    Comments matter here because this text is searched for module names, and a commented
    -out invocation or an explanatory sentence naming a package would otherwise register
    as a live use. Strings are NOT stripped: the names being looked for usually live in
    them ("-m", "some_server_module").

    Follows the actual shell rule - `#` opens a comment only at the start of a word - so
    $# and ${#var} survive. Heredoc bodies are left alone; they are data, and a `#`
    inside one is a character, not a comment."""
    out = []
    heredoc_end = None
    for line in text.splitlines():
        if heredoc_end is not None:
            out.append(line)
            if line.strip() == heredoc_end:
                heredoc_end = None
            continue
        res = []
        sq = dq = False
        i = 0
        while i < len(line):
            c = line[i]
            if sq:
                res.append(c)
                if c == "'":
                    sq = False
            elif dq:
                res.append(c)
                if c == "\\" and i + 1 < len(line):
                    i += 1
                    res.append(line[i])
                elif c == '"':
                    dq = False
            elif c == "'":
                sq = True
                res.append(c)
            elif c == '"':
                dq = True
                res.append(c)
            elif c == "#" and (i == 0 or line[i - 1] in " \t;|&()"):
                break
            else:
                res.append(c)
            i += 1
        stripped = "".join(res)
        m = re.search(r"<<-?\s*[\"']?([A-Za-z_][\w]*)[\"']?", stripped)
        if m:
            heredoc_end = m.group(1)
        out.append(stripped)
    return "\n".join(out)


def strip_python_comments(text):
    """Drop `#` comments from Python source, leaving string literals intact - the names
    being searched for live in strings, e.g. args=["-m", "some_server_module"]."""
    try:
        import io
        import tokenize
        toks = [t for t in tokenize.generate_tokens(io.StringIO(text).readline)
                if t.type != tokenize.COMMENT]
        return tokenize.untokenize(toks)
    except Exception:  # noqa: BLE001 - tokenize is strict; fall back to the shell rule
        return strip_shell_comments(text)


def decomment(path, text):
    if path.endswith(".py"):
        return strip_python_comments(text)
    return strip_shell_comments(text)


def resolve_module_file(dotted, roots):
    """Find the source file a dotted module name was loaded from, plus its containing
    package (needed to resolve `from . import x`). C extensions have no source and
    return (None, None) - they are leaves for this purpose."""
    parts = dotted.split(".")
    for root in roots:
        base = os.path.join(root, *parts)
        init = os.path.join(base, "__init__.py")
        if os.path.isfile(init):
            return init, dotted
        if os.path.isfile(base + ".py"):
            return base + ".py", dotted.rpartition(".")[0]
    return None, None


def conditional_imports(path, pkg):
    """Imports in this file that are NOT at module level - i.e. inside a function, a
    class body, a try block or an `if`. Module-level imports are excluded because they
    already fired when the module loaded; these are the ones that fire only if some
    branch is taken.

    Relative imports are resolved against pkg so `from . import x` yields a name that
    can actually be imported."""
    try:
        with open(path, encoding="utf-8") as f:
            tree = ast.parse(f.read())
    except (OSError, SyntaxError, UnicodeDecodeError, ValueError):
        return set()
    toplevel = set()
    for node in tree.body:
        if isinstance(node, ast.Import):
            toplevel.update(id(a) for a in node.names)
        elif isinstance(node, ast.ImportFrom):
            toplevel.add(id(node))
    names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for a in node.names:
                if id(a) not in toplevel:
                    names.add(a.name)
        elif isinstance(node, ast.ImportFrom) and id(node) not in toplevel:
            if node.level == 0 and node.module:
                names.add(node.module)
            elif node.level > 0 and pkg:
                head = pkg.split(".")
                head = head[:max(0, len(head) - node.level + 1)]
                if node.module:
                    head = head + node.module.split(".")
                if head:
                    names.add(".".join(head))
    return names


def inline_conditional_imports(python_bin, dotted_loaded, roots, scratch, timeout, iso=None,
                               max_rounds=12, already=None):
    """Turn every conditional import found in the modules that actually loaded into an
    unconditional one, and trace THAT.

    Rationale: whether a conditional import fires depends on a branch, and deciding
    branches is not something a dependency scan can or should do. If a loaded module
    can import X on some path, X is a dependency. Python 3.14's argparse imports
    _colorize inside a function; a trace only sees it if the run happens to format help
    or an error, so relying on the trace to hit that branch is luck.

    Each import is attempted independently, so a platform-specific one (msvcrt, nt,
    _winapi) fails on its own line instead of aborting the file. Note that -X importtime
    logs an import ATTEMPT, so such a name still appears in the closure; it resolves to
    no file in the distribution, so it costs nothing.

    Iterated to a fixpoint, not run once. The modules pulled in by round 1 are loaded
    modules too, and the rule that justifies inlining applies to them identically - so
    stopping after one pass contradicts it. On this distribution a second pass finds
    ~40 more real modules, including ssl, tarfile, datetime, email, xml, http and
    decimal: precisely the lazily imported class the feature exists to protect."""
    os.makedirs(scratch, exist_ok=True)
    already = set() if already is None else already
    seen_dotted = set(dotted_loaded)
    scanned = set()
    names = set()
    total_found = 0
    for round_no in range(1, max_rounds + 1):
        found = set()
        for dotted in sorted(seen_dotted - scanned):
            scanned.add(dotted)
            path, pkg = resolve_module_file(dotted, roots)
            if path:
                found |= conditional_imports(path, pkg)
        fresh = found - already
        if not fresh:
            break
        already |= fresh
        total_found += len(fresh)
        inlines = os.path.join(scratch, "_inlines%d.py" % round_no)
        with open(inlines, "w", encoding="utf-8") as f:
            f.write("# generated round %d: conditional imports reachable from a loaded\n"
                    "# module, made unconditional so tracing records them as dependencies.\n"
                    % round_no)
            for name in sorted(fresh):
                f.write("try:\n    import %s\nexcept Exception:\n    pass\n" % name)
        got, dots, err = _run_trace(python_bin, [inlines], timeout, iso)
        if timed_out_marker(err):
            print("# inline warn: round %d timed out; the closure is truncated at that "
                  "point. Raise --trace-timeout." % round_no, file=sys.stderr)
        names |= got
        seen_dotted |= dots
    else:
        # Exhausting the rounds is not convergence. Returning here looks identical to a
        # fixpoint from the caller's side, so say so: the closure is a subset of the real
        # one and the plan will under-keep.
        # Exhausting the rounds proves the last one was still productive, not that the
        # next would have been - so this says "did not converge", which is what is known.
        print("# inline warn: did not converge within %d rounds - the last round was "
              "still finding new conditional imports, so the closure may be incomplete "
              "and the plan may remove a module something lazily imports."
              % max_rounds, file=sys.stderr)
    return names, total_found


def direct_imports(scripts_dir):
    """Top-level module names the source in scripts_dir DIRECTLY imports (AST scan of
    every import statement, including those inside functions). This is a coverage
    cross-check - NOT a keep set: a name here that the trace never loaded means an
    unexercised path or a dynamic import. (Transitive/closure expansion is the trace's
    job; following imports statically over-keeps almost the whole stdlib via dead
    branches, so we deliberately do not do it.)"""
    names = set()
    for f in sorted(os.listdir(scripts_dir)):
        if not is_python_source(os.path.join(scripts_dir, f)):
            continue
        try:
            tree = ast.parse(open(os.path.join(scripts_dir, f), encoding="utf-8").read())
        except Exception as e:  # noqa: BLE001
            print("# parse warn: %s: %s" % (f, e), file=sys.stderr)
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for a in node.names:
                    names.add(a.name.split(".")[0])
            elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                names.add(node.module.split(".")[0])
    return names


# `python3 -m foo.bar`, `"$PYBIN" -m foo`, `$PY -m foo`
DASH_M_RE = re.compile(r"""(?:python[0-9.]*|["']?\$\{?\w*(?:PY|PYTHON)\w*\}?["']?)
                           [\s,]+(?:["']?-\w[\w-]*["']?[\s,]+)*
                           ["']?-m["']?[\s,]+["']?([A-Za-z_][\w.]*)""", re.X)
SCAN_EXT = {".sh", ".bash", ".zsh", ".py", ".json", ".plist", ".txt", ".command", ""}


def scan_app_code(roots, known, exclude=()):
    """Find Python entry points, and uses of Packages names, in the app's OWN files -
    without running anything.

    Two separate jobs:

    1. `-m NAME` sweep. This is how out-of-process code in Packages gets launched
       (`python3 -m some_pkg.cli`), and no scan of the app's .py imports can see
       it. Found this way it needs no hand-written --trace.

    2. Reverse name lookup. Parsing shell reliably is not possible - a module name can
       sit in a variable or be built by concatenation - so do not parse it. The set of
       names that matter is finite and already known (the top level of Packages), so
       search for those instead. This can only ever PROTECT something from removal; it
       never claims a name is unused because a regex failed to understand a script.

    Scope matters more than the regexes. The Packages and Python trees must be excluded:
    distributions cite each other in their own METADATA and ship READMEs full of
    `python -m pytest`, which made every single name look mentioned (47 of 47 on
    one real tree). Binary-ish text like a bundled WebUI .js is excluded too - its JavaScript
    identifiers collide with package names (attr, click, jwt, rich) and bury the signal.
    """
    exclude = tuple(canon(e) for e in exclude if e)
    dash_m, py_files, mentions, shebangs = set(), set(), {}, []
    patterns = {n: re.compile(r"(?<![\w.])%s(?![\w])" % re.escape(n)) for n in known}
    for root_dir in roots:
        if not os.path.isdir(root_dir):
            continue
        for dirpath, dirnames, filenames in os.walk(root_dir):
            ap = canon(dirpath)
            if any(ap == e or ap.startswith(e + os.sep) for e in exclude):
                dirnames[:] = []
                continue
            dirnames[:] = [d for d in dirnames if d not in ("__pycache__", "_CodeSignature")]
            for fn in sorted(filenames):
                path = os.path.join(dirpath, fn)
                if os.path.splitext(fn)[1].lower() not in SCAN_EXT:
                    continue
                try:
                    with open(path, "rb") as f:
                        raw = f.read(4_000_000)
                except OSError:
                    continue
                if b"\0" in raw[:4096]:
                    continue
                text = raw.decode("utf-8", "replace")
                first = text.split("\n", 1)[0] if text.startswith("#!") else ""
                if not fn.endswith(".py") and "python" in first.lower():
                    shebangs.append(path)
                text = decomment(path, text)
                dash_m.update(DASH_M_RE.findall(text))
                for name, pat in patterns.items():
                    if pat.search(text):
                        mentions.setdefault(name, set()).add(
                            os.path.relpath(path, os.path.dirname(root_dir.rstrip("/"))))
    return {"dash_m": sorted(dash_m), "py_files": sorted(py_files),
            "mentions": {k: sorted(v) for k, v in mentions.items()},
            "shebang_tools": sorted(shebangs)}


def load_log(path):
    with open(path, encoding="utf-8") as f:
        return {ln.strip().split(".")[0] for ln in f if ln.strip()}


# --------------------------------------------------------------------------- dist map
def size(path):
    if os.path.islink(path):
        return 0
    if os.path.isfile(path):
        try:
            return os.path.getsize(path)
        except OSError:
            return 0
    total = 0
    for root, _dirs, files in os.walk(path):
        for fn in files:
            fp = os.path.join(root, fn)
            if not os.path.islink(fp):
                try:
                    total += os.path.getsize(fp)
                except OSError:
                    pass
    return total


def top_level_items(container, is_pkg_root=True):
    """Map top-level name -> path for a stdlib dir or a site-packages dir."""
    items = {}
    if not os.path.isdir(container):
        return items
    for entry in os.listdir(container):
        full = os.path.join(container, entry)
        if entry in ("lib-dynload", "site-packages", "__pycache__") or entry.startswith("config-"):
            continue
        if entry.endswith(".py"):
            items[entry[:-3]] = full
        elif entry.endswith(".so"):
            items.setdefault(entry.split(".")[0], full)
        elif os.path.isdir(full):
            if not is_pkg_root or os.path.isfile(os.path.join(full, "__init__.py")):
                items[entry] = full
            elif entry.endswith((".dist-info", ".egg-info")):
                items[entry] = full
    return items


# --------------------------------------------------------------------------- plan
def target_python_version(python_bin):
    """The major.minor.patch of the distribution being analyzed (not necessarily the
    interpreter running this script)."""
    try:
        out = subprocess.run([python_bin, "--version"], capture_output=True, text=True)
        text = (out.stdout or out.stderr).strip()
        return text.split()[-1] if text else ""
    except Exception:  # noqa: BLE001
        return ""


def computed_name_imports(python_bin, present=()):
    """Top-level modules the interpreter imports under a name it BUILDS AT RUNTIME.

    No analysis in this file can see these. The AST cannot, because there is no import
    statement naming them - `sysconfig` does `importlib.import_module(name)` where name
    comes from `_get_sysconfigdata_name()`. Tracing cannot either, unless the workload
    happens to execute the branch that computes it. So they are asked of the interpreter
    directly, which is the only component that actually knows.

    Measured cost of NOT doing this: every app's plan removed
    `_sysconfigdata__darwin_darwin` (58 KB), and every thinned interpreter raised
    ModuleNotFoundError from `sysconfig.get_config_var()` and `sysconfig.get_paths()`.
    Four of five verified GREEN regardless, because their workloads never reached that
    branch - only the app whose deps call sysconfig on import caught it. That is exactly
    the failure mode a trace cannot be trusted to find.

    CODECS are the other half, and keeping the `encodings` package whole does NOT cover
    them. A codec is looked up by a string assembled at runtime, and the CJK codecs plus
    IDNA reach top-level support modules outside the package: `_multibytecodec`,
    `_codecs_jp/cn/kr/tw/hk/iso2022`, `stringprep`, `unicodedata`. Measured on a thinned,
    GREEN-verified interpreter: `'abc'.encode('shift_jis')`, `b'..'.decode('cp932')` and
    `'bucher.de'.encode('idna')` all raised LookupError. The last one is not exotic -
    `http.client` encodes any non-ASCII hostname with idna. And because
    `encodings.search_function` swallows the underlying ImportError, the failure arrives
    as LookupError, which no missing-module pattern in this file would ever match.

    So the interpreter is asked to resolve every codec it knows and report which
    top-level modules that pulled in, rather than trusting a hand-written list.
    """
    names = set()
    probe = r"""
import sys, json
found = set()
try:
    import sysconfig
    found.add(sysconfig._get_sysconfigdata_name())
except Exception:
    pass
try:
    import codecs, encodings, encodings.aliases
    before = set(sys.modules)
    for alias in set(encodings.aliases.aliases.values()) | {"idna", "punycode"}:
        try:
            codecs.lookup(alias)
        except Exception:
            pass
    for mod in set(sys.modules) - before:
        top = mod.split(".")[0]
        if top not in ("encodings", "codecs"):
            found.add(top)
except Exception:
    pass
print(json.dumps(sorted(n for n in found if n)))
"""
    # The probe's own answer depends on its environment: sysconfig reads
    # _PYTHON_SYSCONFIGDATA_NAME before computing the default, so an inherited value
    # makes the probe name a module that does not exist here - and because the answer is
    # non-empty, the pattern fallback below would not fire and nothing would warn. That
    # is the original bug with an extra step. Reproduced, hence the scrub.
    env = {k: v for k, v in os.environ.items() if not k.startswith("DYLD_")}
    for var in ("PYTHONPATH", "PYTHONHOME", "PYTHONSTARTUP", "PYTHONUSERBASE",
                "_PYTHON_SYSCONFIGDATA_NAME"):
        env.pop(var, None)
    env["PYTHONNOUSERSITE"] = "1"
    # As Isolation.env() does. This probe runs the APP's interpreter over the app's
    # own stdlib, so without it CPython caches the bytecode of everything the probe
    # imports back into the distribution - after thin_with_plan.sh has just removed
    # exactly that, on a plan that asked for it.
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    try:
        out = subprocess.run([python_bin, "-s", "-c", probe], capture_output=True,
                             text=True, timeout=60, env=env)
        for line in out.stdout.splitlines():
            line = line.strip()
            if not line.startswith("["):
                continue          # startup chatter, a .pth print, a warning
            for name in json.loads(line):
                if isinstance(name, str) and name.isidentifier():
                    names.add(name)
    except Exception:  # noqa: BLE001
        pass
    # UNION, not fallback. A name the probe returns that is absent from this distribution
    # must not mask one that is present, which is what made the poisoned-environment case
    # silent rather than merely wrong.
    by_pattern = {n for n in present if n.startswith("_sysconfigdata")}
    if by_pattern - names:
        print("# keep warn: keeping %s by pattern - the interpreter did not name it."
              % ", ".join(sorted(by_pattern - names)), file=sys.stderr)
    names |= by_pattern
    if not names:
        print("# keep warn: could not ask the interpreter which modules it imports by "
              "computed name, and none matched by pattern. If this distribution has a "
              "_sysconfigdata module or CJK codecs, they may be removed.", file=sys.stderr)
    return names


def orphaned_dylibs(python_dir, keep):
    """Crypto dylibs that become dead weight once their extension modules leave the
    closure. Returned as paths relative to python_dir so the plan stays portable."""
    out = []
    if "_ssl" not in keep:
        if os.path.isfile(os.path.join(python_dir, "lib", "libssl.dylib")):
            out.append("lib/libssl.dylib")
        if "_hashlib" not in keep:
            if os.path.isfile(os.path.join(python_dir, "lib", "libcrypto.dylib")):
                out.append("lib/libcrypto.dylib")
    return out


def _norm_dist(name):
    return name.lower().replace("-", "_").replace(".", "_")


def _dist_aliases(name):
    """Plausible import names for a distribution name, for the common case where the
    two differ by a wrapper affix: python_multipart -> multipart, rpds_py -> rpds,
    markdown_it_py -> markdown_it, pyjwt -> jwt. Only a heuristic - it exists to stop a
    mismatch being reported as an orphan, never to authorize a deletion."""
    n = _norm_dist(name)
    out = {n}
    for pre in ("python_", "py_"):
        if n.startswith(pre) and len(n) > len(pre):
            out.add(n[len(pre):])
    for suf in ("_py", "_python"):
        if n.endswith(suf) and len(n) > len(suf):
            out.add(n[:-len(suf)])
    if n.startswith("py") and len(n) > 2 and not n.startswith("py_"):
        out.add(n[2:])
    return out


def dist_graph(packages_dir):
    """Parse every dist-info into (provides, requires, authoritative).

    provides:      distribution -> the top-level import names it installs
    requires:      distribution -> distributions it declares in Requires-Dist
    authoritative: whether `provides` was read from metadata rather than guessed

    Requirements behind `extra ==` markers are skipped: they are opt-in and a plain
    install did not pull them in, so they cannot vouch for anything present.
    """
    provides, requires, authoritative = {}, {}, {}
    for entry in sorted(os.listdir(packages_dir)):
        if not entry.endswith((".dist-info", ".egg-info")):
            continue
        dist = _norm_dist(entry.rsplit(".", 1)[0].rsplit("-", 1)[0])
        reqs = set()
        meta = os.path.join(packages_dir, entry, "METADATA")
        try:
            with open(meta, encoding="utf-8", errors="replace") as f:
                for line in f:
                    if not line.startswith("Requires-Dist:"):
                        continue
                    spec = line.split(":", 1)[1].strip()
                    if "extra ==" in spec:
                        continue
                    dep = re.split(r"[\s\[<>=!;(~]", spec, maxsplit=1)[0]
                    if dep:
                        reqs.add(_norm_dist(dep))
        except OSError:
            pass
        # A tree can hold two versions of the same dist-info (seen: idna 3.16 and 3.17,
        # starlette 1.1.0 and 1.2.0). Assigning would drop one side's dependency edges
        # and manufacture orphans, so union instead.
        requires.setdefault(dist, set()).update(reqs)
        # top_level.txt maps a distribution to the names it actually installs
        # (beautifulsoup4 -> bs4). RECORD is absent from these trees and top_level.txt
        # survives in only a minority, so where neither exists the mapping is a GUESS
        # and the entry must not be called an orphan on the strength of it.
        tl = os.path.join(packages_dir, entry, "top_level.txt")
        names = set()
        if os.path.isfile(tl):
            try:
                with open(tl, encoding="utf-8") as f:
                    names = {ln.strip() for ln in f if ln.strip()}
            except OSError:
                names = set()
        has_record = os.path.isfile(os.path.join(packages_dir, entry, "RECORD"))
        authoritative[dist] = bool(names) or has_record
        provides.setdefault(dist, set()).update(names or _dist_aliases(dist))
    return provides, requires, authoritative


def reachable_dists(packages_dir, app_names):
    """Distributions reachable from the APP's own code, following Requires-Dist edges.

    A flat scan of the packages tree treats every distribution as used, which is the
    opposite of useful: over years of development a dependency stops being imported and
    stays installed forever, and calling it used guarantees it is never noticed. Rooting
    the walk in what app code actually names, then following only the declared dependency
    edges beneath those roots, is what makes "unreachable" mean something.

    Returns (reachable_dists, roots, unreachable_dists). Aliases are honored on both
    sides, since app code names an IMPORT name and Requires-Dist names a DISTRIBUTION.
    """
    provides, requires, _auth = dist_graph(packages_dir)
    by_import = {}
    for dist, names in provides.items():
        for n in names:
            by_import.setdefault(n, set()).add(dist)
        for a in _dist_aliases(dist):
            by_import.setdefault(a, set()).add(dist)

    roots = set()
    for name in app_names:
        top = name.split(".")[0]
        roots |= by_import.get(top, set())
        if _norm_dist(top) in requires:
            roots.add(_norm_dist(top))

    seen, queue = set(roots), list(roots)
    while queue:
        dist = queue.pop()
        for dep in requires.get(dist, ()):
            for cand in {dep} | {d for a in _dist_aliases(dep) for d in by_import.get(a, ())}:
                if cand in requires and cand not in seen:
                    seen.add(cand)
                    queue.append(cand)
            if dep not in seen and dep in requires:
                seen.add(dep)
                queue.append(dep)
    return seen, roots, set(requires) - seen


def packages_report(packages_dir, reached, mentions=None, unreachable=None):
    """Audit the Packages tree into reviewable entries. Never a removal list.

    Two independent signals per entry:
      imported     - a traced entry point actually loaded it.
      required_by  - some OTHER installed distribution declares it in Requires-Dist.

    Only the ABSENCE OF BOTH is meaningful. `imported: false` alone is routine and
    proves nothing: certifi, pyjwt and tzdata are all unimported at trace time and all
    load later on TLS, auth and timezone paths a build-time trace never reaches.
    Deleting on trace-miss alone would take every one of them.

    Requirements guarded behind `extra ==` markers are skipped: those are opt-in extras
    that a plain install did not pull in, so they cannot vouch for anything present."""
    if not packages_dir or not os.path.isdir(packages_dir):
        return None

    provides, requires, authoritative = {}, {}, {}
    for entry in sorted(os.listdir(packages_dir)):
        if not entry.endswith((".dist-info", ".egg-info")):
            continue
        dist = _norm_dist(entry.rsplit(".", 1)[0].rsplit("-", 1)[0])
        reqs = set()
        meta = os.path.join(packages_dir, entry, "METADATA")
        try:
            with open(meta, encoding="utf-8", errors="replace") as f:
                for line in f:
                    if not line.startswith("Requires-Dist:"):
                        continue
                    spec = line.split(":", 1)[1].strip()
                    if "extra ==" in spec:
                        continue
                    dep = re.split(r"[\s\[<>=!;(~]", spec, maxsplit=1)[0]
                    if dep:
                        reqs.add(_norm_dist(dep))
        except OSError:
            pass
        # A tree can hold two versions of the same dist-info (seen: idna 3.16 and 3.17,
        # starlette 1.1.0 and 1.2.0). Assigning would drop one side's dependency edges
        # and manufacture orphans, so union instead.
        requires.setdefault(dist, set()).update(reqs)
        # top_level.txt maps a distribution to the names it actually installs
        # (beautifulsoup4 -> bs4). RECORD is absent from these trees and top_level.txt
        # survives in only a minority, so where neither exists the mapping is a GUESS
        # and the entry must not be called an orphan on the strength of it.
        tl = os.path.join(packages_dir, entry, "top_level.txt")
        names = set()
        if os.path.isfile(tl):
            try:
                with open(tl, encoding="utf-8") as f:
                    names = {ln.strip() for ln in f if ln.strip()}
            except OSError:
                names = set()
        has_record = os.path.isfile(os.path.join(packages_dir, entry, "RECORD"))
        authoritative[dist] = bool(names) or has_record
        provides.setdefault(dist, set()).update(names or _dist_aliases(dist))

    required_by = {}
    for dist, reqs in requires.items():
        for dep in reqs:
            if dep != dist:
                required_by.setdefault(dep, set()).add(dist)
                # A requirement names a DISTRIBUTION; the tree is keyed by import name.
                # Credit the aliases too, so `Requires-Dist: rpds-py` also vouches for
                # the `rpds` directory sitting next to it.
                for alias in _dist_aliases(dep):
                    required_by.setdefault(alias, set()).add(dist)

    # Importable things actually sitting in the tree, by top-level name.
    present = {}
    for entry in sorted(os.listdir(packages_dir)):
        if entry.startswith(".") or entry in ("bin", "__pycache__"):
            continue
        if entry.endswith((".dist-info", ".egg-info")):
            continue
        full = os.path.join(packages_dir, entry)
        name = entry[:-3] if entry.endswith(".py") else entry.split(".")[0]
        present[name] = full

    name_to_dist = {}
    for dist, names in provides.items():
        for n in names:
            name_to_dist.setdefault(n, dist)

    scripts = set()
    bindir = os.path.join(packages_dir, "bin")
    if os.path.isdir(bindir):
        for b in os.listdir(bindir):
            scripts.add(_norm_dist(b))

    # A distribution can install several top-level names (a package plus its private C
    # extension). Judging each name on its own makes the
    # companion look like an orphan, because nothing declares a dependency on it by that
    # name - so let every name inherit the standing of its distribution.
    dist_reached = set()
    for name in present:
        d = name_to_dist.get(name, _norm_dist(name))
        if name in reached:
            dist_reached.add(d)

    entries, orphan_bytes = [], 0
    for name in sorted(present):
        dist = name_to_dist.get(name, _norm_dist(name))
        imported = name in reached or dist in dist_reached
        rb = sorted(required_by.get(dist, set()) | required_by.get(_norm_dist(name), set()))
        if imported:
            verdict = "imported"
        elif rb:
            verdict = "required-by-installed-dist"
        elif name in (mentions or {}):
            # The app's own shell/python/config text names it - a launch line, a
            # generated config, a path. Not proof it runs, but far better evidence
            # of intent than a trace that never touched it.
            verdict = "mentioned-in-app-code"
        elif _norm_dist(name) in scripts:
            # A console script in Packages/bin is an entry point someone runs.
            verdict = "has-console-script"
        elif not (authoritative.get(dist, False) or _norm_dist(name) in requires):
            # The name was matched to a distribution by guesswork: no RECORD, no
            # top_level.txt, and the directory name is not itself a distribution here
            # (attrs installs `attr`, beautifulsoup4 installs `bs4`). Calling that an
            # orphan invites deleting something needed, and a Packages deletion has no
            # safety net - verification only re-runs the app's own entry points, which
            # by definition never import an orphan candidate. An EXACT name match, on
            # the other hand, involved no guess and stays reportable.
            verdict = "unknown-provenance"
        else:
            verdict = "orphan-candidate"
        nbytes = size(present[name])
        if verdict == "orphan-candidate":
            orphan_bytes += nbytes
        entry = {"name": name, "dist": dist, "size_bytes": nbytes,
                 "imported": imported, "required_by": rb, "verdict": verdict}
        if mentions and name in mentions:
            entry["mentioned_in"] = mentions[name][:5]
        entries.append(entry)

    orphans = [e["name"] for e in entries if e["verdict"] == "orphan-candidate"]
    out = {
        # Absolute, always. A plan is applied later, from somewhere else, by a tool
        # that backs this directory up and deletes out of it - "./deps" recorded
        # verbatim would resolve against whatever directory that run happens to
        # start in.
        "dir": os.path.abspath(packages_dir) if packages_dir else packages_dir,
        "policy": "report-only",
        "note": ("`remove` is intentionally empty. An entry is only a candidate when it is "
                 "BOTH unimported by every traced entry point AND undeclared by every "
                 "installed distribution. Move a name into `remove` by hand after "
                 "confirming it, and re-run apply."),
        "summary": {
            "entries": len(entries),
            "total_bytes": sum(e["size_bytes"] for e in entries),
            "imported": sum(1 for e in entries if e["verdict"] == "imported"),
            "required_by_installed_dist": sum(
                1 for e in entries if e["verdict"] == "required-by-installed-dist"),
            "has_console_script": sum(
                1 for e in entries if e["verdict"] == "has-console-script"),
            "mentioned_in_app_code": sum(
                1 for e in entries if e["verdict"] == "mentioned-in-app-code"),
            "unknown_provenance": sum(
                1 for e in entries if e["verdict"] == "unknown-provenance"),
            "orphan_candidates": len(orphans),
            "orphan_candidate_bytes": orphan_bytes,
        },
        "orphan_candidates": orphans,
        "entries": entries,
        "remove": [],
    }
    if unreachable is not None:
        # A second, independent signal, recorded alongside rather than folded into the
        # verdict. "Nothing the app names leads here through declared dependencies" is the
        # question a human asks when deciding whether a distribution is still earning its
        # place - and it is the one signal that survives a package falling out of use, which
        # neither import-at-trace-time nor required-by-some-other-dist can detect.
        out["unreachable_from_app_code"] = sorted(unreachable)
        out["unreachable_note"] = (
            "Not reachable from any distribution the app's own code names, following "
            "declared Requires-Dist edges. Suggestive, NOT proof: an `extra ==` dependency "
            "is deliberately not followed, which is exactly how cryptography (11.3 MB, "
            "conditionally imported by jwt/algorithms.py) appears here while being genuinely "
            "used. Review before removing anything.")
    return out


def verify_plan(python_bin, plan, iso=None, root=None):
    """Re-run each trace recorded in the plan under python_bin (the just-thinned
    interpreter) and report whether the workload still runs. A removed-but-needed module
    surfaces as an ImportError/Traceback, or as a non-zero exit on a workload that runs
    to completion. Blocking workloads (watchers) are killed after the timeout and treated
    as success unless they already raised an import error during startup.

    Recorded entry points are root-relative and re-resolved against `root`, which
    should be a staged copy of the just-thinned tree: verification re-executes real entry
    points, so it needs the same confinement the planning traces had.

    Uses subprocess timeouts, so it does NOT depend on a `timeout` binary (which macOS
    lacks). Run this WITH a full interpreter - the thinned one may have had json/argparse
    removed and so cannot run this script; only the spawned traces use python_bin."""
    iso = iso or Isolation()
    tr = plan.get("trace", {})
    timeout = tr.get("timeout") or 6
    baseline = set(tr.get("baseline_missing", []) or [])
    # (command, strict) - strict means a non-zero exit or any traceback is a failure.
    # Only hand-written workloads get that: they are written to run to completion. An
    # auto-traced entry point is judged solely on whether thinning made a module
    # disappear, because it exits non-zero as a matter of course when the app is not
    # around it.
    traces = [(c, True) for c in (tr.get("commands", []) or [])]

    # When nothing was executed at plan time, the import sweep IS the workload, so
    # re-attempt exactly those imports against the thinned interpreter. Without this a
    # plan built in imports-only mode would have nothing to verify.
    seeds = tr.get("import_seeds", []) or []
    probe_mark = _probe_mark()
    probe_index = None
    if seeds:
        os.makedirs(iso.scratch, exist_ok=True)
        probe = write_import_probe(os.path.join(iso.scratch, "_verify_imports.py"),
                                   seeds, probe_mark)
        traces.append((shlex.quote(probe), False))
        probe_index = len(traces)      # 1-based, matching the enumerate below

    recorded = tr.get("entry_points", []) or []
    skipped = 0
    for rel in recorded:
        full = os.path.join(root, rel) if root else None
        if full and os.path.isfile(full):
            traces.append((shlex.quote(full), False))
        else:
            skipped += 1
    if skipped:
        # Silently skipping these and returning success is verification that verified
        # nothing - the same vacuous pass as a process that never launched.
        print("  %d of %d recorded entry point(s) could not be resolved%s."
              % (skipped, len(recorded),
                 " (no --root given)" if not root else " under %s" % root),
              file=sys.stderr)
        if not traces:
            print("  nothing could be verified; treating as FAILURE.", file=sys.stderr)
            return False
    if tr.get("sandboxed") and not iso.sandbox_profile:
        print("  verify warn: this plan was traced under a sandbox profile but verification "
              "is running without one.", file=sys.stderr)
    if not traces:
        # Same vacuous pass as a process that never launched: the caller reads True as
        # "the thinned interpreter was exercised and survived", deletes the backup, and
        # prints Success. A plan that can verify nothing has not earned that.
        print("  no commands, no import seeds and no entry points in this plan - there "
              "is nothing to verify; treating as FAILURE.", file=sys.stderr)
        return False
    err_pat = re.compile(r"Traceback|ImportError|ModuleNotFoundError", re.IGNORECASE)
    ok = True
    regressions = set()
    os.makedirs(iso.scratch, exist_ok=True)
    for i, (cmd, strict) in enumerate(traces, 1):
        parts = shlex.split(cmd)
        # Keep -X importtime: the count of modules imported is the POSITIVE evidence
        # that this process actually ran. Without it, anything that fails to launch -
        # an unloadable sandbox profile, a broken interpreter, a segfault - produces
        # empty stderr, matches no error pattern, and is reported as verified.
        proc = subprocess.Popen(iso.argv(python_bin, parts), stdout=subprocess.DEVNULL,
                                stderr=subprocess.PIPE, env=iso.env(), cwd=iso.scratch)
        timed_out = False
        try:
            _o, err = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            proc.kill()
            _o, err = proc.communicate()
            timed_out = True
        errs = err.decode("utf-8", "replace")
        # The probe reports failures instead of raising, so collect both forms: a name it
        # could not import, and any ModuleNotFoundError that escaped normally.
        #
        # Baseline is subtracted IN THE SAME REPRESENTATION it was recorded in. It holds
        # dotted seeds - `from subprocess import run` baselines `subprocess.run`, because
        # run is a function and the probe cannot import it - and collapsing those to
        # top-level whitelists the whole package for the life of the committed plan.
        # Measured: with `urllib.parse.unquote` baselined, deleting all of urllib passed
        # verification and shipped an interpreter where `import urllib.parse` raises.
        base_top = {n for n in baseline if "." not in n}
        gone = ((missing_modules(errs) - base_top)
                | {n.split(".")[0] for n in (probe_failures(errs, probe_mark) - baseline)})
        imported = _parse_importtime(errs)
        started = bool(imported)
        # The probe must also FINISH. It runs module-level code of everything it imports,
        # and a package that calls sys.exit() (or segfaults) kills the sweep partway -
        # after which the seeds never attempted look exactly like seeds that passed.
        # Measured: the sweep died after 183 of 308 names, `uuid` was never attempted, and
        # a plan that deleted uuid was reported Success with the backup removed.
        if started and i == probe_index and not probe_completed(errs, probe_mark):
            ok = False
            print("  [%d] INCOMPLETE: the import sweep ran (%d imports) but did not reach "
                  "the end, so most seeds were never attempted. Not a passing result."
                  % (i, len(imported)), file=sys.stderr)
            for line in errs.splitlines()[-4:]:
                print("      " + line, file=sys.stderr)
            continue
        if not started:
            ok = False
            print("  [%d] DID NOT RUN (exit %s): %s" % (i, proc.returncode, cmd[:60]),
                  file=sys.stderr)
            if proc.returncode in NO_START_CODES:
                print("      the process never launched - unloadable sandbox profile, or "
                      "the interpreter is not executable. This is NOT a passing result.",
                      file=sys.stderr)
            for line in errs.splitlines()[:4]:
                print("      " + line, file=sys.stderr)
            continue
        if strict:
            bad = bool(err_pat.search(errs)) or (not timed_out and proc.returncode not in (0, None))
        else:
            bad = bool(gone) or import_failed(errs)
        if bad:
            ok = False
            regressions |= gone
            print("  [%d] FAILED: %s" % (i, cmd[:70]), file=sys.stderr)
            shown = 0
            for line in errs.splitlines():
                if err_pat.search(line) or "Error:" in line or "SyntaxError" in line:
                    print("      " + line, file=sys.stderr)
                    shown += 1
                    if shown >= 6:
                        break
            if not shown:
                print("      (exit code %s, no import-error text in stderr)" % proc.returncode,
                      file=sys.stderr)
        else:
            if timed_out:
                note = "timed out; watcher started"
            elif not strict and proc.returncode not in (0, None):
                # Expected: the app is not around it, so it bailed. It DID run - the
                # module count proves that - and nothing it imported went missing.
                note = "ran (%d imports), exited %s, no import failures" % (
                    len(imported), proc.returncode)
            else:
                note = "completed cleanly (%d imports)" % len(imported)
            print("  [%d] ok (%s): %s" % (i, note, cmd[:55]), file=sys.stderr)
    if regressions:
        # Separate cause from consequence. One removed module makes every importer of it
        # fail too, so the raw set mixes the module to put back with a list of its
        # dependents - and calling all of them "removed by the plan" is simply false for
        # most of them. Only the intersection with remove.modules is actionable.
        planned = set(plan.get("remove", {}).get("modules", []))
        caused = sorted(regressions & planned)
        fallout = sorted(regressions - planned)
        if caused:
            print("  modules the plan removed but a path still needs: %s"
                  % " ".join(caused), file=sys.stderr)
        if fallout:
            print("  also failed to import%s: %s"
                  % (" (fallout from the above)" if caused else
                     " - not removed by this plan, so this is a pre-existing or "
                     "environmental failure", " ".join(fallout)), file=sys.stderr)
    return ok


def build_plan(python_dir, python_bin, keep, removable_names, args, packages=None,
               entry_points=None, baseline_missing=None, import_seeds=None):
    """Assemble the JSON thinning plan. `remove.modules` are top-level names (resolved
    to paths against the live dist at apply time, so a reinstall re-thins correctly);
    `keep` and `trace` are recorded for review/provenance and for verification.

    `entry_points` are recorded BUNDLE-RELATIVE. Auto-tracing runs against a throwaway
    clone, so absolute paths in a committed plan would name a directory that no longer
    exists; relative ones re-resolve against whatever root is being verified."""
    builtins = set(sys.builtin_module_names)
    plan = {
        "schema": "python-embedding/thinning-plan@2",
        "created": datetime.datetime.now().isoformat(timespec="seconds"),
        "python": {"version": target_python_version(python_bin)},
        "trace": {
            "commands": list(args.trace),
            "entry_points": sorted(entry_points or []),
            "timeout": args.trace_timeout,
            "sandboxed": bool(args.sandbox_profile),
            # Modules already unimportable BEFORE thinning. Verification subtracts these
            # so a pre-existing gap is never mistaken for damage this plan did.
            "baseline_missing": sorted(baseline_missing or []),
            # The imports the app's scripts name. Verification re-attempts exactly these
            # against the thinned interpreter - that IS the workload when nothing is
            # executed, and without it there would be nothing to verify at all.
            "import_seeds": sorted(import_seeds or []),
        },
        "remove": {
            "modules": sorted(removable_names),
            "dylibs": orphaned_dylibs(python_dir, keep),
            "include_headers": (not args.no_extras),
            "bytecode": (not args.no_extras),
        },
        "arch": (args.arch or None),
        "keep": sorted(n for n in keep if n not in builtins),
    }
    if packages is not None:
        plan["packages"] = packages
    return plan


# --------------------------------------------------------------------------- main
def main(argv):
    p = argparse.ArgumentParser(description="Compute the module closure of an embedded Python.")
    p.add_argument("--python", default=None, help="embedded Python dir (default: running interpreter)")
    p.add_argument("--trace", action="append", default=[], help="command to run under -X importtime")
    p.add_argument("--auto-trace-scripts", action="append", default=[],
                   help="dir of app scripts to derive the closure from (imports-only by default)")
    p.add_argument("--execute-entry-points", action="store_true",
                   help="run each script instead of importing what it imports; adds only the "
                        "branches that happen to run, at the cost of executing handler bodies")
    p.add_argument("--scan-app-code", action="append", default=[],
                   help="dir of app-authored files to scan (not run) for `-m` entry points and "
                        "uses of Packages names; comments are stripped first")
    p.add_argument("--trace-timeout", type=float, default=6.0, help="seconds before killing a blocking trace")
    p.add_argument("--static", action="append", default=[], help="dir of *.py to AST-scan (coverage check)")
    p.add_argument("--packages", default=None,
                   help="app Packages dir: put on PYTHONPATH for traces and audited into the plan")
    p.add_argument("--sandbox-profile", default=None,
                   help="sandbox-exec profile confining every traced subprocess")
    p.add_argument("--root", default=None,
                   help="root dir the distribution lives under; traces are scrubbed so no Python outside it is importable")
    p.add_argument("--scratch", default=None,
                   help="writable dir for traced processes (HOME/TMPDIR/cwd); must be inside "
                        "whatever the sandbox profile permits")
    p.add_argument("--check-isolation", action="store_true",
                   help="fail if any sys.path entry resolves outside --root")
    p.add_argument("--keep-file", action="append", default=[],
                   help="file of extra top-level names to force-keep, one per line. For "
                        "plugins loaded by a name no analysis can see")
    p.add_argument("--packages-scope", action="store_true", default=True,
                   help="scope the --packages scan to distributions reachable from app "
                        "code via Requires-Dist (default), so a dependency nothing imports "
                        "any more is reported instead of protected")
    p.add_argument("--no-packages-scope", dest="packages_scope", action="store_false",
                   help="scan every installed distribution, reachable or not")
    p.add_argument("--packages-surface", action="store_true", default=True,
                   help="treat every import named anywhere in --packages source as a "
                        "dependency (default; which files of a distribution load is "
                        "branch-dependent, so the trace alone under-keeps)")
    p.add_argument("--no-packages-surface", dest="packages_surface", action="store_false",
                   help="only keep what --packages code imported during the trace "
                        "(smaller, and can remove what an unexercised package path needs)")
    p.add_argument("--inline-conditional", action="store_true", default=True,
                   help="treat conditional imports in loaded modules as unconditional (default)")
    p.add_argument("--no-inline-conditional", dest="inline_conditional", action="store_false",
                   help="only keep what the trace literally imported (may miss lazy branches)")
    p.add_argument("--runtime-log", action="append", default=[], help="file of module names from your own run")
    p.add_argument("--keep", default="",
                   help="comma-separated extra top-level names to force-keep. Each is "
                        "IMPORTED, so its own dependencies are kept too; one that this "
                        "distribution provides also becomes a verification seed, and one "
                        "that cannot be imported at all is recorded as already-missing "
                        "and never checked again")
    p.add_argument("--plan", default=None,
                   help="resolve removals from this thinning plan instead of tracing (apply mode)")
    p.add_argument("--arch", default="", help="target arch (arm64|x86_64) to record in --print plan")
    p.add_argument("--no-extras", action="store_true",
                   help="record 'do not remove include/ + bytecode' in --print plan")
    p.add_argument("--verify", action="store_true",
                   help="with --plan: re-run the plan's traces under --python; exit non-zero on failure")
    p.add_argument("--print", dest="emit",
                   choices=["report", "removable-names", "removable-paths", "keep-names", "plan",
                            "packages-remove-paths"],
                   default="report")
    args = p.parse_args(argv)

    python_dir = args.python or os.path.dirname(os.path.dirname(os.path.dirname(os.__file__)))
    stdlib = find_stdlib(python_dir)
    dynload = os.path.join(stdlib, "lib-dynload")
    site = os.path.join(stdlib, "site-packages")
    python_bin = os.path.join(python_dir, "bin", "python3")

    items = {}
    items.update(top_level_items(stdlib))
    items.update(top_level_items(dynload, is_pkg_root=False))
    site_items = top_level_items(site, is_pkg_root=False)
    all_items = {}
    all_items.update(items)
    all_items.update(site_items)

    # ----- APPLY: resolve removals (or verify) from an existing plan -----
    if args.plan:
        if args.emit == "plan":
            raise SystemExit("--plan applies a plan; it cannot also emit one")
        with open(args.plan, encoding="utf-8") as f:
            plan = json.load(f)
        if args.verify:
            iso = Isolation(root=args.root, packages=args.packages,
                            sandbox_profile=args.sandbox_profile, scratch=args.scratch)
            # Same gate the plan verb has. Without it a verification run could import
            # from outside the bundle and pronounce a broken thinning healthy.
            if args.root:
                leaks = iso.check(python_bin)
                if leaks:
                    print("# ISOLATION FAILURE during verification: %s"
                          % " ".join(leaks[:4]), file=sys.stderr)
                    return 2
            return 0 if verify_plan(python_bin, plan, iso, args.root) else 1
        if args.emit == "packages-remove-paths":
            # Only what a human moved into packages.remove. An empty list here is the
            # normal, correct state - the audit reports, it does not decide.
            pkgs = plan.get("packages") or {}
            pkgdir = args.packages or pkgs.get("dir")
            names = pkgs.get("remove", [])
            if names and not pkgdir:
                raise SystemExit("plan has packages.remove but no --packages dir to resolve against")
            # Match how the entry actually sits in the tree: a package dir, a module
            # .py, or an extension module whose filename carries the ABI tag
            # (_cffi_backend.cpython-314-darwin.so). Matching only n and n.py reported
            # a plainly present .so as "already removed", which reads as a completed
            # deletion that never happened. The dist-info goes too, so the next audit's
            # dependency graph is not fed by metadata for something no longer there.
            # pkgdir is None for an applet with no Packages directory at all: the
            # plan then carries no "packages" key and nothing passes --packages.
            # os.path.isdir(None) raises, which used to surface as a traceback the
            # caller discarded along with the exit status.
            existing = os.listdir(pkgdir) if pkgdir and os.path.isdir(pkgdir) else []
            out = []
            for n in names:
                hits = []
                for entry in existing:
                    stem = entry[:-3] if entry.endswith(".py") else entry.split(".")[0]
                    if stem == n:
                        hits.append(os.path.join(pkgdir, entry))
                    elif entry.endswith((".dist-info", ".egg-info")):
                        dist = entry.rsplit(".", 1)[0].rsplit("-", 1)[0]
                        nd = _norm_dist(dist)
                        if (nd in _dist_aliases(n) | {_norm_dist(n)}
                                or _norm_dist(n) in _dist_aliases(nd)):
                            hits.append(os.path.join(pkgdir, entry))
                if hits:
                    out.extend(hits)
                else:
                    print("# packages warn: %s is not present; already removed?" % n,
                          file=sys.stderr)
            print("\n".join(sorted(set(out))))
            return 0
        remove_set = set(plan.get("remove", {}).get("modules", []))
        if args.emit == "removable-paths":
            print("\n".join(sorted(all_items[n] for n in remove_set if n in all_items)))
        else:  # removable-names / keep-names / report -> the names that exist here
            print("\n".join(sorted(n for n in remove_set if n in all_items)))
        return 0

    # ----- PLAN: compute the closure from traces / logs -----
    scripts_dir = args.auto_trace_scripts[0] if args.auto_trace_scripts else None
    iso = Isolation(root=args.root, packages=args.packages, scripts=scripts_dir,
                    sandbox_profile=args.sandbox_profile, scratch=args.scratch)
    def warn_unsandboxed():
        print("# isolation warn: analyzing scripts runs module-level code of everything "
              "they import%s; pass --sandbox-profile so a misbehaving module cannot write "
              "or reach the network."
              % (" AND executes each entry point" if args.execute_entry_points else ""),
              file=sys.stderr)
    if args.auto_trace_scripts and not args.sandbox_profile:
        warn_unsandboxed()
    if args.check_isolation:
        if not args.root:
            raise SystemExit("--check-isolation requires --root")
        leaks = iso.check(python_bin)
        if leaks:
            print("# ISOLATION FAILURE: the interpreter can import Python from outside "
                  "%s:" % args.root, file=sys.stderr)
            for p in leaks:
                print("#   %s" % p, file=sys.stderr)
            return 2

    keep_trace, keep_log, direct = set(), set(), set()
    entry_points, per_script, baseline_missing, dotted = [], {}, set(), set()
    import_seeds = set()
    # .pth files run before any app code, so whatever they import is unconditional.
    pth = pth_imports(site, args.packages)
    if pth:
        import_seeds |= pth
        print("# .pth startup imports: %s" % " ".join(sorted(pth)), file=sys.stderr)

    # Entry points into Packages that only a shell script or a generated config names.
    # Discovered, not declared: this is what lets an app whose real workload is
    # `python3 -m some_pkg.cli` need no --trace at all. The same sweep finds the app's
    # shebang tools, so it has to run BEFORE the scripts are analyzed rather than after.
    discovered = []
    scan = None
    if args.scan_app_code:
        known = set()
        if args.packages and os.path.isdir(args.packages):
            known = {e[:-3] if e.endswith(".py") else e.split(".")[0]
                     for e in os.listdir(args.packages)
                     if not e.startswith(".") and e not in ("bin", "__pycache__")
                     and not e.endswith((".dist-info", ".egg-info"))}
        scan = scan_app_code(args.scan_app_code, known,
                             exclude=[args.packages, python_dir])
        for mod in scan["dash_m"]:
            if mod.split(".")[0] in known or mod.split(".")[0] in all_items:
                discovered.append("-m " + mod)
        if discovered:
            print("# discovered %d out-of-process entry point(s) in app code: %s"
                  % (len(discovered), ", ".join(discovered)), file=sys.stderr)

    # An extension-less file with a python shebang is an entry point that nothing can
    # declare: it is launched by path from a handler or a shell script, so no `-m` sweep
    # and no import statement anywhere names it, and a *.py test walks straight past it.
    # Its DIRECTORY is adopted rather than the file alone, because the sibling rule that
    # keeps a scripts dir honest applies here identically - the package sitting beside
    # the tool is where its real dependencies are written, and seeding the tool's import
    # of that package instead of reading it would drop the lot.
    script_dirs = [canon(d) for d in args.auto_trace_scripts]
    given = set(script_dirs)
    adopted = {}
    for tool in (scan or {}).get("shebang_tools", ()):
        # canon, not abspath: a symlinked tool's SIBLINGS are next to the real file, and
        # adopting the link's directory instead seeds the package it should have read.
        d = os.path.dirname(canon(tool))
        if not any(d == s or d.startswith(s + os.sep) for s in script_dirs):
            script_dirs.append(d)
        if d not in given:
            adopted.setdefault(d, []).append(os.path.basename(tool))
    if adopted:
        print("# adopted %d shebang entry point(s) that no import statement names: %s"
              % (sum(len(v) for v in adopted.values()),
                 ", ".join("%s (%s)" % (os.path.basename(d) or d, " ".join(sorted(v)))
                           for d, v in sorted(adopted.items()))), file=sys.stderr)
        if not args.auto_trace_scripts and not args.sandbox_profile:
            warn_unsandboxed()

    # Packages and the interpreter's own tree are audited and thinned by different rules,
    # so a scripts dir must never pull them into the app's seed set - which a tool
    # discovered high in a bundle otherwise would.
    #
    # An adopted directory that CONTAINS another script dir is excluded from it as well.
    # The sibling rule is computed at the top of the directory being scanned, so walking
    # Resources/ after adopting a tool there would re-read Resources/Scripts/*.py with
    # `Scripts` as the only stem - turning lib_icedit, lib_material and lib_debounce into
    # seeds. They resolve at plan time, because the scripts dir is on PYTHONPATH then,
    # and fail at verify time, when it is not: apply then fails permanently. Nothing is
    # lost by excluding them, since each such directory is scanned in its own right.
    base_exclude = [args.packages, python_dir]
    for d in script_dirs:
        scan_exclude = base_exclude + [s for s in script_dirs
                                       if s != d and s.startswith(d + os.sep)]
        if args.execute_entry_points:
            names, per, base_missing, dots = auto_trace_scripts(
                python_bin, d, args.trace_timeout, iso)
            per_script.update(per)
            baseline_missing |= base_missing
            root = os.path.abspath(args.root) if args.root else None
            for fn in sorted(per):
                full = os.path.join(os.path.abspath(d), fn)
                entry_points.append(os.path.relpath(full, root) if root else full)
            dead = sorted(fn for fn, n in per.items() if n == 0)
            if dead:
                print("# trace warn: these entry points imported nothing (did not start): %s"
                      % " ".join(dead), file=sys.stderr)
        else:
            names, dots, seeds, base_missing = imports_only_closure(
                python_bin, d, args.trace_timeout, iso, scan_exclude)
            import_seeds |= seeds
            baseline_missing |= base_missing
            print("# imports-only: %d import statement(s) across the scripts, %d module(s) "
                  "loaded (no entry point was executed)" % (len(seeds), len(names)),
                  file=sys.stderr)
        keep_trace |= names
        dotted |= dots

    # Installed packages: the same rule as the app's own scripts. Every import named
    # anywhere in their source is a dependency, because which FILES of a distribution
    # load is as much a branch decision as which imports inside a file fire - and the
    # trace can only tell us about the files it happened to load.

    pkg_scope = None
    if args.packages and os.path.isdir(args.packages) and args.packages_surface:
        # Scope the scan to distributions the APP can actually reach: the ones its own
        # code names, plus the transitive Requires-Dist closure beneath them. A flat scan
        # treats every installed distribution as used, which is how a dependency that
        # stopped being imported years ago stays protected forever.
        # Roots are everything the app REACHES a distribution by, not just what it
        # imports. Measured why that matters: one app's handler scripts import nothing but
        # stdlib, yet its 42 installed distributions are all launched out-of-process from
        # shell. Seeding from imports alone found zero roots and scoped the scan to nothing.
        app_names = set()
        for d in script_dirs:
            app_names |= {s.split(".")[0] for s in all_imports_of_dir(d, scan_exclude)}
        app_names |= {c.split()[-1].split(".")[0] for c in args.trace if " -m " in c}
        app_names |= {m.split(".")[0] for m in (scan or {}).get("dash_m", ())}
        app_names |= set((scan or {}).get("mentions", {}))
        app_names |= {m.split(".")[0] for m in entry_point_modules(args.packages)}
        reach, roots, unreach = reachable_dists(args.packages, app_names)
        pkg_scope = (reach, roots, unreach)
        # PROTECTION is deliberately NOT scoped. Reachability decides what to REPORT, not
        # what to keep: an unreachable distribution is still shipped and still importable
        # (which is why the audit refuses to delete it), so a stdlib module only it imports
        # must still survive. Scoping the scan would have removed exactly that - and the one
        # distribution it excluded on both MCP apps was `cryptography`, already established
        # as reachable through a conditional import that Requires-Dist records only as an
        # extra. Judgment and protection answer different questions.
        surface, nfiles, nprov = package_import_surface(args.packages)
        eps = entry_point_modules(args.packages)
        extra = (surface | eps) - import_seeds
        before = set(keep_trace)
        names, dots, base_missing = probe_seeds(
            python_bin, extra, args.trace_timeout, iso, "packages", "_pkgimports.py")
        keep_trace |= names
        dotted |= dots
        import_seeds |= extra
        baseline_missing |= base_missing
        gained = sorted(names - before)
        print("# packages surface: %d file(s) across %d distribution(s) name %d import(s) "
              "outside the tree%s; %d module(s) kept that the app's own imports missed%s"
              % (nfiles, nprov, len(surface),
                 " (+%d from entry_points.txt)" % len(eps) if eps else "",
                 len(gained), (": " + " ".join(gained)) if gained else ""),
              file=sys.stderr)
        if args.packages_scope:
            print("# packages reachability: %d of %d distribution(s) reachable from the %d "
                  "the app names; NOT reachable: %s"
                  % (len(reach), nprov, len(roots),
                     " ".join(sorted(unreach)) if unreach else "(none)"),
                  file=sys.stderr)
        # `python -m NAME` inside package source, and dotted names sitting in config data.
        known_pkg = {e[:-3] if e.endswith(".py") else e.split(".")[0]
                     for e in os.listdir(args.packages)
                     if not e.startswith(".") and e not in ("bin", "__pycache__")
                     and not e.endswith((".dist-info", ".egg-info"))}
        pkg_dash_m = dash_m_in_sources([args.packages], known_pkg | set(all_items))
        if pkg_dash_m:
            print("# `-m` launches inside package source: %s"
                  % " ".join(sorted(pkg_dash_m)), file=sys.stderr)
            nm, dts, bm = probe_seeds(python_bin, pkg_dash_m, args.trace_timeout, iso,
                                      "pkg -m", "_pkgdashm.py")
            keep_trace |= nm
            dotted |= dts
            import_seeds |= pkg_dash_m
            baseline_missing |= bm

    for cmd in list(args.trace) + discovered:
        names, dots, _err = _run_trace(python_bin, shlex.split(cmd), args.trace_timeout, iso)
        keep_trace |= names
        dotted |= dots

    extra = {n.strip() for n in args.keep.split(",") if n.strip()}
    for kf in args.keep_file:
        try:
            with open(kf, encoding="utf-8") as f:
                extra |= {ln.split("#")[0].strip() for ln in f if ln.split("#")[0].strip()}
        except OSError as e:
            raise SystemExit("--keep-file %s: %s" % (kf, e))
    # Dotted module paths that live in config data rather than code - a logging config's
    # `"()": "pkg.mod.Class"`, a plugin registry, a job definition. Reverse lookup against
    # names this distribution provides, so it can only ever protect.
    if args.scan_app_code:
        dfn = data_file_names(args.scan_app_code, set(all_items),
                              exclude=[args.packages, python_dir])
        if dfn:
            extra |= set(dfn)
            print("# data-file module names: %s"
                  % " ".join("%s(%s)" % (n, ",".join(sorted(f)[:2]))
                             for n, f in sorted(dfn.items())), file=sys.stderr)

    # A force-keep is a NAME, and a name without its dependencies is a module that still
    # cannot be imported. Measured: `--keep compileall` kept compileall and removed
    # filecmp, which compileall imports at module level - the keep was honored and the
    # module raised anyway. So forced names are IMPORTED like any other seed. Their
    # closure joins the keep set, the conditional-import fixpoint below sees them, and
    # they enter import_seeds so verification re-checks them after the deletions instead
    # of taking the keep on trust.
    #
    # data_file_names() feeds this set too, and it matches by reverse lookup, so a data
    # file naming `calendar` for reasons of its own (one app's icon map does) forces a
    # module nothing imports. That is the intended direction - the lookup can only ever
    # protect - but note the consequence: such a name is now recorded in import_seeds, so
    # verification will refuse a later plan that drops it. Move it out of the data files,
    # not out of here, if it ever costs something worth reclaiming.
    forced = {n for n in extra if n not in keep_trace}
    if forced:
        fnames, fdots, fbase = probe_seeds(python_bin, forced, args.trace_timeout, iso,
                                           "force-keep", "_keepimports.py")
        print("# force-keep: %d name(s) forced, %d module(s) kept with them%s"
              % (len(forced), len(fnames - keep_trace),
                 "; %s did not import" % " ".join(sorted(fbase)) if fbase else ""),
              file=sys.stderr)
        keep_trace |= fnames
        dotted |= fdots
        baseline_missing |= fbase
        # Seed only what THIS distribution provides. Verification exists to prove the
        # plan did not delete something needed, and it can only delete from here; a
        # forced name that lives elsewhere is out of its scope. The distinction is not
        # theoretical - plan-time traces put the app's scripts dir on PYTHONPATH and
        # verification does not, so `--keep-file` naming a handler-local module (the
        # documented remedy for a closure blind spot) imported at plan time, failed at
        # verify time, and made apply fail permanently while reporting the failure as
        # "not removed by this plan". Protection is unaffected: fnames and extra are
        # still kept, only the verification seed is withheld.
        import_seeds |= {n for n in forced if n.split(".")[0] in all_items}

    # Conditional imports inside the modules that loaded are dependencies too. Whether
    # they fire is a branch decision, and this tool does not decide branches.
    # Rewriting the modules IN PLACE to hoist these was built, measured and removed. Two
    # findings killed it. Hoisting every conditional import in place is strictly worse than
    # this fixpoint - 146 names kept against 195, missing 49 and gaining none - because a
    # hoisted import is inert in any module loaded from frozen bytecode (site.py alone
    # accounts for sysconfig, readline, rlcompleter and usercustomize) and only fires for
    # files that actually load. And hoisting just the COMPUTED imports, which is the one
    # thing this fixpoint structurally cannot reproduce, gained nothing on any app: all 66
    # call sites found take their module name from a function PARAMETER or a local
    # (`import_module(modname)`, `import_module(gd['pkg'])`), which is caller data, not
    # file data, so at module level every one is a NameError. Even sysconfig's own case
    # reads a local. Computed imports are covered by interrogating the interpreter instead
    # (see computed_name_imports) and, where that cannot reach, by reporting the call sites.
    inlined = 0
    if args.inline_conditional and dotted:
        keep_inline, inlined = inline_conditional_imports(
            python_bin, dotted, [stdlib, site, dynload] + ([args.packages] if args.packages else []),
            os.path.join(iso.scratch, "inline"), args.trace_timeout, iso)
        new = keep_inline - keep_trace
        keep_trace |= keep_inline
        print("# inlined %d conditional import(s) from %d loaded module(s); %d module(s) "
              "the trace alone would have missed: %s"
              % (inlined, len(dotted), len(new), " ".join(sorted(new)) or "(none)"),
              file=sys.stderr)

    for d in args.static:
        direct |= direct_imports(d)
    for f in args.runtime_log:
        keep_log |= load_log(f)
    computed = computed_name_imports(python_bin, all_items)
    keep = keep_trace | keep_log | extra | computed | set(sys.builtin_module_names)
    # Coverage cross-check: source names these top-level modules but the trace never
    # loaded them -> an unexercised path or a dynamic import. They WILL be removed
    # unless you trace that path or --keep them.
    uncovered = sorted(n for n in direct if n not in keep)

    if args.emit == "removable-names":
        print("\n".join(sorted(n for n in all_items if n not in keep)))
        return 0
    if args.emit == "removable-paths":
        print("\n".join(sorted(all_items[n] for n in all_items if n not in keep)))
        return 0
    if args.emit == "keep-names":
        print("\n".join(sorted(keep)))
        return 0
    if args.emit == "plan":
        if not args.trace and not args.runtime_log and not script_dirs:
            print("# plan warn: no --trace/--auto-trace-scripts/--runtime-log given; the "
                  "closure is only builtins, so this plan would remove almost everything. "
                  "Provide a real workload.", file=sys.stderr)
        elif not (args.trace or import_seeds or entry_points):
            # A workload flag was passed but produced nothing to run - e.g. a scripts dir
            # holding no .py at all. The plan still lists near-everything as removable and
            # would be committed as if reviewed. Verification refuses such a plan at apply
            # time, but the warning belongs HERE, where it is written.
            print("# plan warn: the workload is EMPTY - no commands, no import seeds, no "
                  "entry points - yet this plan removes %d of %d modules. Nothing will be "
                  "verifiable at apply time and the plan will be refused. Check that the "
                  "path given to --auto-trace-scripts actually holds .py files."
                  % (len([n for n in all_items if n not in keep]), len(all_items)),
                  file=sys.stderr)
        removable_names = sorted(n for n in all_items if n not in keep)
        # Where the analysis is provably blind. Reported, never silently tolerated: a
        # reviewer can judge a dynamic import site, but only if told it exists.
        blind = dynamic_import_sites([args.packages] if args.packages else [])
        if blind:
            worst = sorted(blind.items(), key=lambda kv: -len(kv[1]))[:5]
            print("# blind spots: %d file(s) in --packages import a name computed at "
                  "runtime; no static or trace analysis can see those. Most: %s"
                  % (len(blind), ", ".join("%s(%d)" % (f, len(l)) for f, l in worst)),
                  file=sys.stderr)
        pkgs = packages_report(args.packages, keep_trace | keep_log,
                               (scan or {}).get("mentions"),
                               unreachable=pkg_scope[2] if pkg_scope else None)
        plan = build_plan(python_dir, python_bin, keep, removable_names, args,
                          packages=pkgs, entry_points=entry_points,
                          baseline_missing=baseline_missing, import_seeds=import_seeds)
        if pkgs and pkgs["orphan_candidates"]:
            print("# packages: %d orphan candidate(s) (%.1f MB) - imported by nothing and "
                  "required by nothing installed: %s"
                  % (len(pkgs["orphan_candidates"]),
                     pkgs["summary"]["orphan_candidate_bytes"] / 1048576,
                     " ".join(pkgs["orphan_candidates"])), file=sys.stderr)
            print("# packages: reported only - packages.remove is empty; move names into it "
                  "by hand after confirming.", file=sys.stderr)
        if uncovered:
            print("# coverage warning: source imports these but the trace never loaded them "
                  "(they will be removed): %s" % " ".join(uncovered), file=sys.stderr)
        print(json.dumps(plan, indent=2))
        return 0

    mb = lambda b: "%.2f MB" % (b / 1048576)
    print("python dist : %s" % python_dir)
    print("stdlib      : %s" % stdlib)
    print("KEEP        : %d names (trace=%d, log=%d, forced=%d, computed-name=%d)"
          % (len(keep - set(sys.builtin_module_names)), len(keep_trace), len(keep_log),
             len(extra), len(computed)))

    def section(title, mapping):
        rem = sorted((n for n in mapping if n not in keep), key=lambda n: -size(mapping[n]))
        tot = sum(size(mapping[n]) for n in rem)
        print("\n=== REMOVABLE %s: %s across %d ===" % (title, mb(tot), len(rem)))
        for n in rem:
            sz = size(mapping[n])
            if sz >= 8192:
                print("  %-26s %10s" % (n, mb(sz)))
        return tot

    t1 = section("stdlib", items)
    t2 = section("site-packages", site_items)
    kept_site = sorted(n for n in site_items if n in keep)
    print("\nKEPT site-packages (needed): %s" % (", ".join(kept_site) or "(none)"))
    print("TOTAL removable (modules only): %s" % mb(t1 + t2))

    pkgs = packages_report(args.packages, keep_trace | keep_log,
                           (scan or {}).get("mentions"),
                           unreachable=pkg_scope[2] if pkg_scope else None)
    if pkgs:
        s = pkgs["summary"]
        print("\n=== PACKAGES AUDIT (report only - nothing here is removed) ===")
        print("  %d entries, %s total: %d imported, %d required by an installed dist, "
              "%d orphan candidate(s)"
              % (s["entries"], mb(s["total_bytes"]), s["imported"],
                 s["required_by_installed_dist"], s["orphan_candidates"]))
        for e in sorted(pkgs["entries"], key=lambda e: -e["size_bytes"]):
            if e["verdict"] == "orphan-candidate":
                print("    ORPHAN?  %-24s %10s  (imported by nothing, required by nothing)"
                      % (e["name"], mb(e["size_bytes"])))
        if s["orphan_candidates"]:
            print("  Orphan candidates total %s. Confirm each by hand before moving it into"
                  % mb(s["orphan_candidate_bytes"]))
            print("  packages.remove - an unimported dep is usually a lazy TLS/auth/tz path,")
            print("  not dead weight.")

    if uncovered:
        print("\n=== COVERAGE WARNING: source imports these, but the trace never loaded them ===")
        print("    Exercise the path that uses each (add a --trace), or --keep it; otherwise it is removed:")
        print("    " + " ".join(uncovered))
    elif args.static:
        print("\nCoverage check: every module the source imports was loaded by the trace. Good.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
