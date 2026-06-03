"""
Type checking utilities for Command.plist validation.

plistlib-to-Python type mapping (from plistlib.load):
  <string>           → str
  <integer>          → int
  <real>             → float
  <true/> / <false/> → bool          (bool is a subclass of int — check bool first)
  <array>            → list
  <dict>             → dict
  <data>             → bytes
  <date>             → datetime.datetime

Schema type names accepted in "types":
  "string","integer","real","number","boolean","array","dict","data","date"
  "number" matches both integer and real; "integer" matches only int (not float).
"""
from __future__ import annotations

import datetime


def plist_type_of(value) -> str:
    """Return the plist type name for a Python value decoded by plistlib."""
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "real"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "dict"
    if isinstance(value, (bytes, bytearray)):
        return "data"
    if isinstance(value, datetime.datetime):
        return "date"
    if value is None:
        return "null"
    return "unknown"


def matches_types(value, types: list) -> bool:
    """
    Check whether a value satisfies any type in a list.
    "number" matches both integer and real; "integer" matches only int (not float).
    """
    vt = plist_type_of(value)
    for t in types:
        if t == "number" and vt in ("integer", "real"):
            return True
        if t == vt:
            return True
    return False


def matches_spec(value, spec: dict) -> bool:
    """
    Check whether a value matches a single type-spec dict (not a oneOf list).
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
