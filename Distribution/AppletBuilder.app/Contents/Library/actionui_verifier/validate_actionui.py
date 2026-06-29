#!/usr/bin/env python3
"""
ActionUI JSON Verifier

Usage:
    validate_actionui.py <file.json>            validate a single file
    validate_actionui.py <directory/>           validate all *.json files in directory
    validate_actionui.py -r <directory/>        recurse into subdirectories
    validate_actionui.py --strict <path>        treat warnings as errors
    validate_actionui.py --platform <p> <path>  validate as deployed to platform <p>
    validate_actionui.py --schema-dir <dir> ... add an add-on schema directory (repeatable)

Without --platform, files are validated as cross-platform authoring documents:
platform-specific keys must carry a `:<platform>` suffix. With --platform, the
document is validated as if deployed to that one platform (other-platform
variants are dropped, just as they are at runtime).

--schema-dir extends the built-in element set with schemas shipped by optional
add-on libraries (e.g. ActionUIQuickLook/Schemas), so documents using an add-on's
element type validate without that type being baked into the core schemas. The
built-in schemas take precedence on a name collision. The option is repeatable.

Add-on schemas are also auto-discovered (no --schema-dir needed) from:
  - schemas/add-ons/<AddOn>/   next to this script (populated when the verifier is
                               packaged into a Skill dist or AppletBuilder.app), and
  - ../../Add-ons/<AddOn>/Schemas/   when running in-place inside the ActionUI repo.
Explicit --schema-dir directories take precedence over auto-discovered ones.

Exit codes:
    0  no issues
    1  one or more errors found
    2  warnings only (elevated to 1 with --strict)
"""

from __future__ import annotations

import sys
import json
import re
from pathlib import Path


def _strip_jsonc(text: str) -> str:
    """Strip trailing commas before } or ] — matches Foundation JSON parser leniency."""
    return re.sub(r',(\s*[}\]])', r'\1', text)

# Resolve schemas directory relative to this script
_SCRIPT_DIR = Path(__file__).parent
_SCHEMAS_DIR = _SCRIPT_DIR / "schemas"

sys.path.insert(0, str(_SCRIPT_DIR))
from verifier import SchemaLoader, ElementValidator, ValidationIssue, ALL_PLATFORMS


def discover_addon_schema_dirs(script_dir: Path) -> list[Path]:
    """Auto-discover add-on element-schema directories so an add-on's element types
    (e.g. ActionUIQuickLook's "QuickLook") validate without an explicit --schema-dir.

    Two optional sources, covering the verifier's two homes:
      1. <script_dir>/schemas/add-ons/<AddOn>/  - the reserved directory next to the
         core schemas, populated when the verifier is copied into a Skill dist or
         AppletBuilder.app (the copy is otherwise self-contained, with no repo around it).
      2. <repo>/Add-ons/<AddOn>/Schemas/        - the add-on sources, for running the
         verifier in-place inside the ActionUI repo (script at <repo>/Tools/verifier).

    Core schemas still win on a name collision because SchemaLoader keeps its primary
    directory first; these are appended after any explicit --schema-dir directories.
    """
    dirs: list[Path] = []

    reserved = script_dir / "schemas" / "add-ons"
    if reserved.is_dir():
        dirs += [sub for sub in sorted(reserved.iterdir()) if sub.is_dir()]
        dirs.append(reserved)  # also allow schemas placed directly in add-ons/

    addons_root = script_dir.parent.parent / "Add-ons"
    if addons_root.is_dir():
        for sub in sorted(addons_root.iterdir()):
            schema_dir = sub / "Schemas"
            if schema_dir.is_dir():
                dirs.append(schema_dir)

    return dirs


# Top-level element types allowed in a menu-bar document (MainMenu.json).
_MENUBAR_TYPES = ("CommandMenu", "CommandGroup")


def validate_menubar(data: list, path: str, validator: ElementValidator) -> list:
    """Validate a menu-bar document (MainMenu.json): a top-level JSON array of
    CommandMenu / CommandGroup elements.  Deletion is expressed as a CommandGroup
    with placement "replacing" and no children (matching SwiftUI's
    CommandGroup(replacing:))."""
    issues: list = []
    seen_ids: set = set()
    for index, element in enumerate(data):
        epath = f"{path}[{index}]"
        if not isinstance(element, dict):
            issues.append(ValidationIssue("error", epath, "menu-bar element must be a JSON object"))
            continue
        etype = element.get("type")
        if etype in ("CommandMenu", "CommandGroup"):
            issues += validator.validate(element, epath, seen_ids)
        elif etype is None:
            issues.append(ValidationIssue("error", epath, "menu-bar element missing 'type'"))
        else:
            issues.append(ValidationIssue("error", epath,
                f"'{etype}' is not valid at the top level of a menu-bar document; "
                f"expected one of: {', '.join(_MENUBAR_TYPES)}"))
    return issues


def _report_issues(path: Path, issues: list) -> tuple[int, int]:
    errors = [i for i in issues if i.severity == "error"]
    warnings = [i for i in issues if i.severity == "warning"]

    for issue in sorted(issues, key=lambda i: (i.path, i.severity)):
        stream = sys.stderr if issue.severity == "error" else sys.stdout
        print(str(issue), file=stream)

    if not issues:
        print(f"[OK] {path}")

    return len(errors), len(warnings)


def validate_file(path: Path, validator: ElementValidator, strict: bool) -> tuple[int, int]:
    """Returns (error_count, warning_count)."""
    try:
        with open(path, encoding="utf-8") as f:
            data = json.loads(_strip_jsonc(f.read()))
    except json.JSONDecodeError as e:
        print(f"[ERROR] {path}: invalid JSON — {e}", file=sys.stderr)
        return 1, 0
    except OSError as e:
        print(f"[ERROR] {path}: cannot read file — {e}", file=sys.stderr)
        return 1, 0

    # A top-level JSON array is a menu-bar document (MainMenu.json) — an array of
    # CommandMenu / CommandGroup elements.  A view document has an object root.
    if isinstance(data, list):
        return _report_issues(path, validate_menubar(data, str(path), validator))

    if not isinstance(data, dict):
        print(f"[ERROR] {path}: root must be a JSON object (a view) or array (a menu bar)",
              file=sys.stderr)
        return 1, 0

    seen_ids: set = set()
    return _report_issues(path, validator.validate(data, str(path), seen_ids))


def validate_path(
    target: Path, validator: ElementValidator, strict: bool, recursive: bool = False
) -> tuple[int, int]:
    total_errors, total_warnings = 0, 0

    if target.is_dir():
        json_files = sorted(target.rglob("*.json") if recursive else target.glob("*.json"))
        if not json_files:
            print(f"No *.json files found in {target}", file=sys.stderr)
            return 0, 0
        for f in json_files:
            e, w = validate_file(f, validator, strict)
            total_errors += e
            total_warnings += w
    elif target.is_file():
        total_errors, total_warnings = validate_file(target, validator, strict)
    else:
        print(f"[ERROR] Path not found: {target}", file=sys.stderr)
        total_errors = 1

    return total_errors, total_warnings


def main():
    strict = False
    recursive = False
    target_platform = None
    extra_schema_dirs: list[str] = []
    paths = []

    raw = sys.argv[1:]
    i = 0
    while i < len(raw):
        arg = raw[i]
        if arg == "--strict":
            strict = True
        elif arg in ("--recursive", "-r"):
            recursive = True
        elif arg == "--platform":
            i += 1
            if i >= len(raw):
                print("[ERROR] --platform requires a value", file=sys.stderr)
                sys.exit(2)
            target_platform = raw[i]
        elif arg.startswith("--platform="):
            target_platform = arg.split("=", 1)[1]
        elif arg == "--schema-dir":
            i += 1
            if i >= len(raw):
                print("[ERROR] --schema-dir requires a value", file=sys.stderr)
                sys.exit(2)
            extra_schema_dirs.append(raw[i])
        elif arg.startswith("--schema-dir="):
            extra_schema_dirs.append(arg.split("=", 1)[1])
        elif arg.startswith("-") and arg != "-":
            print(f"[ERROR] unknown option: {arg}", file=sys.stderr)
            print(__doc__, file=sys.stderr)
            sys.exit(2)
        else:
            paths.append(arg)
        i += 1

    if not paths:
        print(__doc__, file=sys.stderr)
        sys.exit(2)

    if target_platform is not None and target_platform not in ALL_PLATFORMS:
        print(
            f"[ERROR] unknown platform '{target_platform}'. "
            f"Known platforms: {', '.join(sorted(ALL_PLATFORMS))}",
            file=sys.stderr,
        )
        sys.exit(2)

    if not _SCHEMAS_DIR.exists():
        print(
            f"[ERROR] Schemas directory not found: {_SCHEMAS_DIR}\n"
            "Ensure 'schemas/' is present next to this script.",
            file=sys.stderr,
        )
        sys.exit(1)

    resolved_extra_dirs: list[Path] = []
    for d in extra_schema_dirs:
        dir_path = Path(d)
        if not dir_path.is_dir():
            print(f"[ERROR] --schema-dir not found or not a directory: {d}", file=sys.stderr)
            sys.exit(2)
        resolved_extra_dirs.append(dir_path)

    # Append auto-discovered add-on schema dirs (explicit --schema-dir wins; dedupe by real path).
    seen = {p.resolve() for p in resolved_extra_dirs}
    for p in discover_addon_schema_dirs(_SCRIPT_DIR):
        if p.resolve() not in seen:
            resolved_extra_dirs.append(p)
            seen.add(p.resolve())

    loader = SchemaLoader(_SCHEMAS_DIR, resolved_extra_dirs)
    validator = ElementValidator(loader, target_platform=target_platform)

    total_errors, total_warnings = 0, 0
    for arg in paths:
        e, w = validate_path(Path(arg), validator, strict, recursive)
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
