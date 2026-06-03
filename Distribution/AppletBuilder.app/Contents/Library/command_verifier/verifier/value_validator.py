"""
Validates an individual value against its schema prop-spec.

A prop-spec is a JSON object describing one key's allowed value(s). Recognized fields:
  types            list of type names ("string","integer","real","number","boolean",
                   "array","dict","data","date")
  required         bool (checked by the caller, not here)
  enum             allowed string values; a non-matching string is a WARNING
                   (forward-compat with engine values we may not know yet)
  enumDeprecated   { value: {"replacement": str, "removed": bool, "since": str} }
                   recognized-but-discouraged enum values → WARNING (or "removed")
  const            fixed required value
  oneOf            list of alternative specs (e.g. string OR array<string>)
  properties       for dict values: sub-key → prop-spec (inline object)
  itemTypes        for array values: allowed element type names
  itemEnum         for array values: allowed element string values (WARNING on miss)
  itemSpec         for array values: a full prop-spec applied to each element
                   (used for arrays of dicts such as PROGRESS STEPS)
  mutuallyExclusiveGroups  for dict values: pairs of key-groups that can't co-occur

Sub-dictionary dispatch ("subschema"), required-key checks at the command level,
deprecation of whole keys, and conditional rules live in plist_validator, not here.
"""
from __future__ import annotations

import re

from .errors import ValidationIssue
from .type_checker import plist_type_of, matches_types, matches_spec, check_one_of

_HEX_COLOR_RE = re.compile(r"^#?[0-9A-Fa-f]{6}$")

# Keys intentionally used as inline comments inside any object; silently skipped.
_ANNOTATION_KEYS = {"NOTES", "note", "comment", "description", "info"}


def validate_value(key: str, value, spec: dict, path: str) -> list[ValidationIssue]:
    """Validate a single value against its prop-spec. Returns a list of issues."""
    issues: list[ValidationIssue] = []
    vpath = f"{path}.{key}"

    # ── oneOf ───────────────────────────────────────────────────────────────
    if "oneOf" in spec:
        if not check_one_of(value, spec["oneOf"]):
            issues.append(ValidationIssue(
                "error", vpath,
                f"value type '{plist_type_of(value)}' ({_repr(value)}) does not match any allowed form"
            ))
        else:
            for alt in spec["oneOf"]:
                if matches_spec(value, alt):
                    if "dict" in alt.get("types", []) and isinstance(value, dict):
                        issues += _validate_object(value, alt, vpath)
                    elif "array" in alt.get("types", []) and isinstance(value, list):
                        issues += _validate_array(value, alt, vpath)
                    break
        return issues

    # ── simple type check ───────────────────────────────────────────────────
    if "types" in spec and not matches_types(value, spec["types"]):
        expected = " or ".join(spec["types"])
        issues.append(ValidationIssue(
            "error", vpath, f"expected {expected}, got {plist_type_of(value)}"
        ))
        return issues  # type wrong — enum/object checks would be noise

    # ── const ───────────────────────────────────────────────────────────────
    if "const" in spec and value != spec["const"]:
        issues.append(ValidationIssue(
            "error", vpath, f"must be {spec['const']!r}, got {_repr(value)}"
        ))

    # ── enum / deprecated enum value ────────────────────────────────────────
    if isinstance(value, str):
        enum = spec.get("enum")
        deprecated = spec.get("enumDeprecated", {})
        if value in deprecated:
            issues.append(_deprecation_issue(vpath, value, deprecated[value]))
        elif enum is not None and value not in enum:
            issues.append(ValidationIssue(
                "warning", vpath,
                f"'{value}' is not a known value; expected one of: {enum}"
            ))

    # ── numeric range ───────────────────────────────────────────────────────
    if "range" in spec and matches_types(value, ["number"]):
        lo = spec["range"].get("min")
        hi = spec["range"].get("max")
        if (lo is not None and value < lo) or (hi is not None and value > hi):
            bounds = f"{lo if lo is not None else '-∞'}..{hi if hi is not None else '∞'}"
            issues.append(ValidationIssue("warning", vpath, f"value {value} is outside the expected range {bounds}"))

    # ── hex color ───────────────────────────────────────────────────────────
    if spec.get("hexColor") and isinstance(value, str):
        if not _HEX_COLOR_RE.match(value):
            issues.append(ValidationIssue("warning", vpath, f"'{value}' is not a 6-digit hex color (RRGGBB)"))

    # ── inline object ───────────────────────────────────────────────────────
    if "dict" in spec.get("types", []) and isinstance(value, dict):
        issues += _validate_object(value, spec, vpath)

    # ── array ───────────────────────────────────────────────────────────────
    if "array" in spec.get("types", []) and isinstance(value, list):
        issues += _validate_array(value, spec, vpath)

    return issues


def _validate_array(value: list, spec: dict, vpath: str) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []
    item_types = spec.get("itemTypes")
    item_enum = spec.get("itemEnum")
    item_spec = spec.get("itemSpec")

    for i, item in enumerate(value):
        ipath = f"{vpath}[{i}]"
        if item_types and not matches_types(item, item_types):
            issues.append(ValidationIssue(
                "error", ipath,
                f"expected {' or '.join(item_types)}, got {plist_type_of(item)}"
            ))
            continue
        if item_enum and isinstance(item, str) and item not in item_enum:
            issues.append(ValidationIssue(
                "warning", ipath,
                f"'{item}' is not a known value; expected one of: {item_enum}"
            ))
        if item_spec:
            # Apply a full prop-spec to each element (e.g. arrays of dicts).
            issues += _validate_item(item, item_spec, ipath)
    return issues


def _validate_item(item, item_spec: dict, ipath: str) -> list[ValidationIssue]:
    """Validate one array element against a prop-spec, stamping its index path."""
    issues: list[ValidationIssue] = []
    if "types" in item_spec and not matches_types(item, item_spec["types"]):
        issues.append(ValidationIssue(
            "error", ipath,
            f"expected {' or '.join(item_spec['types'])}, got {plist_type_of(item)}"
        ))
        return issues
    if "dict" in item_spec.get("types", []) and isinstance(item, dict):
        issues += _validate_object(item, item_spec, ipath)
    return issues


def _validate_object(obj: dict, spec: dict, path: str) -> list[ValidationIssue]:
    """Validate sub-keys of an inline dict value against spec['properties']."""
    issues: list[ValidationIssue] = []
    sub_specs = spec.get("properties")

    if sub_specs is not None:
        # required sub-keys
        for sub_key, sub_spec in sub_specs.items():
            if sub_spec.get("required") and sub_key not in obj:
                issues.append(ValidationIssue(
                    "error", f"{path}.{sub_key}", f"required key '{sub_key}' is missing"
                ))
        # present sub-keys
        for sub_key, sub_value in obj.items():
            if sub_key in _ANNOTATION_KEYS:
                continue
            if sub_key in sub_specs:
                issues += validate_value(sub_key, sub_value, sub_specs[sub_key], path)
            else:
                issues.append(ValidationIssue(
                    "warning", f"{path}.{sub_key}", f"unexpected key '{sub_key}' inside object"
                ))

    issues += check_mutual_exclusion(obj, spec.get("mutuallyExclusiveGroups", []), path)
    return issues


def check_mutual_exclusion(obj: dict, groups: list, path: str) -> list[ValidationIssue]:
    """
    Groups is a list of key-lists. If keys from two different groups are both
    present, that's an error. Used for fixed-vs-flexible style exclusivity and
    for ACTIVATE_ONLY_IN vs NEVER_ACTIVATE_IN.
    """
    issues: list[ValidationIssue] = []
    present_groups = [(g, [k for k in g if k in obj]) for g in groups]
    nonempty = [(g, present) for g, present in present_groups if present]
    if len(nonempty) >= 2:
        collisions = ", ".join(
            "{" + ", ".join(present) + "}" for _, present in nonempty
        )
        issues.append(ValidationIssue(
            "error", path, f"mutually exclusive keys present together: {collisions}"
        ))
    return issues


def _deprecation_issue(vpath: str, value: str, info: dict) -> ValidationIssue:
    replacement = info.get("replacement")
    if info.get("removed"):
        msg = f"'{value}' is removed and ignored by the engine"
        if replacement:
            msg += f"; use '{replacement}'"
    else:
        msg = f"'{value}' is deprecated"
        if replacement:
            msg += f"; use '{replacement}'"
        since = info.get("since")
        if since:
            msg += f" (since {since})"
    return ValidationIssue("warning", vpath, msg)


def _repr(value) -> str:
    s = repr(value)
    return s if len(s) <= 40 else s[:37] + "..."
