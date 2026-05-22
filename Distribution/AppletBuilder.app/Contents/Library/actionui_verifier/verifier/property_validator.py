"""
Validates individual property values against their schema spec.
"""
from __future__ import annotations

from .errors import ValidationIssue
from .type_checker import json_type_of, matches_types, matches_spec, check_one_of

# Keys intentionally used as JSON comments inside any object; silently skipped.
_ANNOTATION_KEYS = {"description", "note", "comment", "info"}


def validate_property(key: str, value, prop_spec: dict, path: str) -> list[ValidationIssue]:
    """
    Validate a single property value against its schema spec.
    Returns a list of ValidationIssues (empty = valid).
    """
    issues = []
    prop_path = f"{path}.{key}"

    if "oneOf" in prop_spec:
        if not check_one_of(value, prop_spec["oneOf"]):
            vt = json_type_of(value)
            issues.append(ValidationIssue(
                "error", prop_path,
                f"value type '{vt}' (value: {_repr(value)}) does not match any allowed form"
            ))
        else:
            # Find the matching alternative and do deeper validation if it's an object
            for alt in prop_spec["oneOf"]:
                if matches_spec(value, alt):
                    if "object" in alt.get("types", []) and isinstance(value, dict):
                        issues += _validate_object_props(value, alt, prop_path)
                    break
        return issues

    # Simple types check
    if "types" in prop_spec:
        if not matches_types(value, prop_spec["types"]):
            expected = " or ".join(prop_spec["types"])
            actual = json_type_of(value)
            issues.append(ValidationIssue(
                "error", prop_path,
                f"expected {expected}, got {actual}"
            ))
            return issues  # no point checking enum/object if type is wrong

    # Enum check (warn, not error — allows forward-compat with new platform values)
    if "enum" in prop_spec and isinstance(value, str):
        if value not in prop_spec["enum"]:
            issues.append(ValidationIssue(
                "warning", prop_path,
                f"'{value}' is not a known value; expected one of: {prop_spec['enum']}"
            ))

    # Object property validation
    if "object" in prop_spec.get("types", []) and isinstance(value, dict):
        issues += _validate_object_props(value, prop_spec, prop_path)

    # Array item type check
    if "array" in prop_spec.get("types", []) and isinstance(value, list):
        item_types = prop_spec.get("itemTypes")
        item_enum = prop_spec.get("itemEnum")
        if item_types:
            for i, item in enumerate(value):
                if not matches_types(item, item_types):
                    issues.append(ValidationIssue(
                        "error", f"{prop_path}[{i}]",
                        f"expected {' or '.join(item_types)}, got {json_type_of(item)}"
                    ))
                elif item_enum and isinstance(item, str) and item not in item_enum:
                    issues.append(ValidationIssue(
                        "warning", f"{prop_path}[{i}]",
                        f"'{item}' is not a known value; expected one of: {item_enum}"
                    ))

        # Discriminated-union items: each dict item is validated against the sub-schema
        # selected by a discriminator key (default "type").
        discriminated = prop_spec.get("discriminatedItems")
        if discriminated and isinstance(discriminated, dict):
            disc_key = discriminated.get("discriminator", "type")
            schemas = discriminated.get("schemas", {})
            for i, item in enumerate(value):
                item_path = f"{prop_path}[{i}]"
                if not isinstance(item, dict):
                    issues.append(ValidationIssue("error", item_path, "expected object"))
                    continue
                item_type = item.get(disc_key)
                if item_type is None:
                    issues.append(ValidationIssue(
                        "warning", f"{item_path}.{disc_key}",
                        f"missing required '{disc_key}' field"
                    ))
                    continue
                if item_type not in schemas:
                    known = sorted(schemas.keys())
                    issues.append(ValidationIssue(
                        "warning", f"{item_path}.{disc_key}",
                        f"'{item_type}' is not a known type; known: {known}"
                    ))
                    continue
                item_schema = {"properties": schemas[item_type]}
                issues += _validate_object_props(item, item_schema, item_path)

    return issues


def _validate_object_props(obj: dict, spec: dict, path: str) -> list[ValidationIssue]:
    """Validate sub-properties of an object against its spec's 'properties' dict."""
    issues = []
    sub_specs = spec.get("properties")

    # No explicit properties schema → open object; skip key-level validation
    if sub_specs is None:
        return issues

    # Check required sub-properties
    for sub_key, sub_spec in sub_specs.items():
        if sub_spec.get("required") and sub_key not in obj:
            issues.append(ValidationIssue(
                "error", f"{path}.{sub_key}",
                f"required key '{sub_key}' is missing"
            ))

    # Validate present sub-properties
    for sub_key, sub_value in obj.items():
        if sub_key in _ANNOTATION_KEYS:
            pass  # intentional JSON comment; silently accepted anywhere
        elif sub_key in sub_specs:
            issues += validate_property(sub_key, sub_value, sub_specs[sub_key], path)
        else:
            # Unknown key inside a known object: warn (may be a new platform key)
            issues.append(ValidationIssue(
                "warning", f"{path}.{sub_key}",
                f"unexpected key '{sub_key}' inside object"
            ))

    # Check mutual exclusivity (frame fixed vs flexible form)
    for group in spec.get("mutuallyExclusiveGroups", []):
        present = [k for k in group if k in obj]
        if present and len(present) != len([k for k in group if k in obj]):
            pass  # groups that partially overlap are checked together
    # Full mutual exclusivity: if keys from group 0 AND group 1 are both present, error
    groups = spec.get("mutuallyExclusiveGroups", [])
    if len(groups) == 2:
        g0_present = any(k in obj for k in groups[0])
        g1_present = any(k in obj for k in groups[1])
        if g0_present and g1_present:
            issues.append(ValidationIssue(
                "error", path,
                f"mixes mutually exclusive keys: {groups[0]} cannot be combined with {groups[1]}"
            ))

    return issues


def _repr(value) -> str:
    s = repr(value)
    return s if len(s) <= 40 else s[:37] + "..."
