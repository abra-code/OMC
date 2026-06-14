#!/usr/bin/env python3
"""
ActionUI JSON Verifier

Usage:
    validate_actionui.py <file.json>            validate a single file
    validate_actionui.py <directory/>           validate all *.json files in directory
    validate_actionui.py -r <directory/>        recurse into subdirectories
    validate_actionui.py --strict <path>        treat warnings as errors
    validate_actionui.py --platform <p> <path>  validate as deployed to platform <p>

Without --platform, files are validated as cross-platform authoring documents:
platform-specific keys must carry a `:<platform>` suffix. With --platform, the
document is validated as if deployed to that one platform (other-platform
variants are dropped, just as they are at runtime).

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


# Top-level element types allowed in a menu-bar document (MainMenu.json).
_MENUBAR_TYPES = ("CommandMenu", "CommandGroup", "RemoveMenu", "RemoveItem")


def _validate_remove_menu(element: dict, path: str) -> list:
    props = element.get("properties")
    if not isinstance(props, dict):
        return [ValidationIssue("error", path, "RemoveMenu requires a 'properties' object")]
    name = props.get("name")
    if not isinstance(name, str) or not name:
        return [ValidationIssue("error", path,
            "RemoveMenu 'properties.name' must be a non-empty string "
            "(the title of the top-level menu to remove, e.g. \"Format\")")]
    return []


def _validate_remove_item(element: dict, path: str) -> list:
    props = element.get("properties")
    if not isinstance(props, dict):
        return [ValidationIssue("error", path, "RemoveItem requires a 'properties' object")]
    issues = []
    title = props.get("title")
    if not isinstance(title, str) or not title:
        issues.append(ValidationIssue("error", path,
            "RemoveItem 'properties.title' must be a non-empty string "
            "(the title of the item to remove, e.g. \"New\")"))
    menu = props.get("menu")
    if menu is not None and (not isinstance(menu, str) or not menu):
        issues.append(ValidationIssue("error", path,
            "RemoveItem 'properties.menu', when present, must be a non-empty string "
            "(the top-level menu to scope the search to, e.g. \"File\")"))
    return issues


def validate_menubar(data: list, path: str, validator: ElementValidator) -> list:
    """Validate a menu-bar document (MainMenu.json): a top-level JSON array of
    CommandMenu / CommandGroup / RemoveMenu / RemoveItem elements."""
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
        elif etype == "RemoveMenu":
            issues += _validate_remove_menu(element, epath)
        elif etype == "RemoveItem":
            issues += _validate_remove_item(element, epath)
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
    # CommandMenu / CommandGroup / RemoveMenu / RemoveItem elements.  A view
    # document has an object root.
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

    loader = SchemaLoader(_SCHEMAS_DIR)
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
