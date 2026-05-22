"""
Type checking utilities for ActionUI JSON schema validation.


JSON-to-Python type mapping (from json.load):
  string  → str
  number  → int or float   (both match schema type "number"; only int matches "integer")
  boolean → bool           (bool is subclass of int — must check bool before int)
  array   → list
  object  → dict
  null    → None
"""


def json_type_of(value) -> str:
    """Return the JSON type name for a Python value."""
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    if value is None:
        return "null"
    return "unknown"


def matches_types(value, types: list) -> bool:
    """
    Check whether a value satisfies any type in a list.
    "number" matches both int and float; "integer" matches only int (not float).
    """
    vt = json_type_of(value)
    for t in types:
        if t == "number" and vt in ("integer", "number"):
            return True
        if t == vt:
            return True
    return False


def matches_spec(value, spec: dict) -> bool:
    """
    Check whether a value matches a single type spec dict (not a oneOf list).
    Checks 'types', 'const', and 'enum'.
    """
    if "types" in spec:
        if not matches_types(value, spec["types"]):
            return False
    if "const" in spec:
        if value != spec["const"]:
            return False
    if "enum" in spec and isinstance(value, str):
        if value not in spec["enum"]:
            return False
    return True


def check_one_of(value, alternatives: list) -> bool:
    """Return True if value matches at least one alternative in a oneOf list."""
    return any(matches_spec(value, alt) for alt in alternatives)
