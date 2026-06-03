#!/usr/bin/env python3
"""
Command.plist Verifier

Usage:
    validate_command_plist.py <Command.plist>        validate a single file (Layer 1)
    validate_command_plist.py <App.app>              validate an applet bundle (Layer 1 + 2)
    validate_command_plist.py <directory/>           validate every Command.plist found under dir
    validate_command_plist.py --bundle <path> <f>    force Layer 2 against an explicit bundle
    validate_command_plist.py --strict <path>        treat warnings as errors

Exit codes:
    0  no issues
    1  one or more errors found
    2  warnings only (elevated to 1 with --strict)
"""

from __future__ import annotations

import re
import sys
import plistlib
from pathlib import Path

_SCRIPT_DIR = Path(__file__).parent
_SCHEMAS_DIR = _SCRIPT_DIR / "schemas"

# Bundle wrappers OMC ships as (all have Contents/Resources/Command.plist).
_BUNDLE_SUFFIXES = {".app", ".omc", ".applet", ".droplet"}

sys.path.insert(0, str(_SCRIPT_DIR))
from verifier import SchemaLoader, PlistValidator  # noqa: E402

try:
    from verifier.bundle_resolver import BundleResolver  # Layer 2 (Phase 4)
except Exception:  # pragma: no cover - Layer 2 not present yet
    BundleResolver = None


def _load_plist(path: Path):
    """Load an XML or binary plist the way OMC does (leniently).

    Python's expat XML parser is stricter than Apple's CoreFoundation parser —
    which is what `plutil` and OMC itself use. Most notably, CF accepts a plist
    DOCTYPE that omits the SYSTEM identifier, e.g.

        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN">

    which is technically invalid XML (a PUBLIC external id requires a system
    literal) and makes expat raise. Such files load fine in OMC, so if the strict
    parse fails we retry with the DOCTYPE stripped before treating the file as
    broken. A genuinely malformed plist still fails (we re-raise).
    """
    raw = path.read_bytes()
    try:
        return plistlib.loads(raw)
    except Exception:
        repaired = re.sub(rb"<!DOCTYPE[^>]*>", b"", raw, count=1)
        if repaired != raw:
            return plistlib.loads(repaired)  # propagates if still broken
        raise


def _find_command_plist(target: Path) -> Path | None:
    """Resolve an applet bundle to its Command.plist, if any."""
    if target.is_dir() and target.suffix in _BUNDLE_SUFFIXES:
        candidate = target / "Contents" / "Resources" / "Command.plist"
        return candidate if candidate.is_file() else None
    return None


def validate_command_plist(plist_path: Path, bundle_path: Path | None, strict: bool) -> tuple[int, int]:
    """Validate one Command.plist. Returns (error_count, warning_count)."""
    try:
        data = _load_plist(plist_path)
    except OSError as e:
        print(f"[ERROR] {plist_path}: cannot read file — {e}", file=sys.stderr)
        return 1, 0
    except Exception as e:
        # plistlib raises InvalidFileException, but the underlying XML/binary
        # parsers raise their own errors (ExpatError, ValueError, …). Treat any
        # parse failure as a single clean error rather than crashing.
        print(f"[ERROR] {plist_path}: not a valid plist ({e.__class__.__name__}) — run `plutil -lint` for details", file=sys.stderr)
        return 1, 0

    loader = SchemaLoader(_SCHEMAS_DIR)
    validator = PlistValidator(loader)
    issues = validator.validate(data, str(plist_path))

    # Layer 2 — bundle-aware cross-references (when a bundle is known and available).
    if bundle_path is not None and BundleResolver is not None and isinstance(data, dict):
        resolver = BundleResolver(bundle_path)
        issues += resolver.cross_reference(data, str(plist_path))

    errors = [i for i in issues if i.severity == "error"]
    warnings = [i for i in issues if i.severity == "warning"]

    for issue in sorted(issues, key=lambda i: (i.path, i.severity)):
        stream = sys.stderr if issue.severity == "error" else sys.stdout
        print(str(issue), file=stream)

    if not issues:
        print(f"[OK] {plist_path}")

    return len(errors), len(warnings)


def validate_target(target: Path, forced_bundle: Path | None, strict: bool) -> tuple[int, int]:
    # Applet bundle → Command.plist inside it, with Layer 2 against the bundle.
    if target.is_dir() and target.suffix in _BUNDLE_SUFFIXES:
        plist = _find_command_plist(target)
        if plist is None:
            print(f"[ERROR] {target}: no Contents/Resources/Command.plist in bundle", file=sys.stderr)
            return 1, 0
        return validate_command_plist(plist, forced_bundle or target, strict)

    # Plain directory → every Command.plist under it.
    if target.is_dir():
        plists = sorted(target.rglob("Command.plist"))
        if not plists:
            print(f"No Command.plist found under {target}", file=sys.stderr)
            return 0, 0
        te = tw = 0
        for p in plists:
            bundle = _bundle_for(p)
            e, w = validate_command_plist(p, forced_bundle or bundle, strict)
            te += e
            tw += w
        return te, tw

    # A single file.
    if target.is_file():
        bundle = forced_bundle or _bundle_for(target)
        return validate_command_plist(target, bundle, strict)

    print(f"[ERROR] Path not found: {target}", file=sys.stderr)
    return 1, 0


def _bundle_for(plist: Path) -> Path | None:
    """If the plist sits at <Bundle>/Contents/Resources/Command.plist, return the bundle."""
    p = plist.resolve()
    if p.parent.name == "Resources" and p.parent.parent.name == "Contents":
        bundle = p.parent.parent.parent
        if bundle.suffix in _BUNDLE_SUFFIXES:
            return bundle
    return None


def main():
    args = sys.argv[1:]
    strict = False
    forced_bundle: Path | None = None

    if "--strict" in args:
        strict = True
        args = [a for a in args if a != "--strict"]

    if "--bundle" in args:
        i = args.index("--bundle")
        try:
            forced_bundle = Path(args[i + 1])
        except IndexError:
            print("[ERROR] --bundle requires a path argument", file=sys.stderr)
            sys.exit(2)
        del args[i:i + 2]

    if not args:
        print(__doc__, file=sys.stderr)
        sys.exit(2)

    if not _SCHEMAS_DIR.exists():
        print(f"[ERROR] Schemas directory not found: {_SCHEMAS_DIR}", file=sys.stderr)
        sys.exit(1)

    total_errors = total_warnings = 0
    for arg in args:
        e, w = validate_target(Path(arg), forced_bundle, strict)
        total_errors += e
        total_warnings += w

    if total_errors > 0:
        print(f"\n{total_errors} error(s), {total_warnings} warning(s).", file=sys.stderr)
        sys.exit(1)
    elif total_warnings > 0 and strict:
        print(f"\n0 errors, {total_warnings} warning(s) — failing due to --strict.", file=sys.stderr)
        sys.exit(1)
    elif total_warnings > 0:
        print(f"\n0 errors, {total_warnings} warning(s).")
        sys.exit(2)
    else:
        print("\nAll files valid.")
        sys.exit(0)


if __name__ == "__main__":
    main()
