"""
Top-level driver for Command.plist validation.

Unlike the ActionUI verifier (a recursive element-tree walk), Command.plist has a
fixed shallow structure, so this driver runs a fixed set of passes:

  Pass A — Root:    COMMAND_LIST (array, required) + VERSION (==2, required-value)
  Pass B — Command: each dict in COMMAND_LIST against Command.json
  Pass C — Sub-dict: each present sub-dict key against its own <NAME>.json schema
                     (recursed one more level for SORT_OPTIONS, STEPS[], …)

Per-value type/enum/oneOf/array checks are delegated to value_validator.
Conditional rules (requires/conflictsWith/appliesWhen) are applied here and are
expanded in Phase 3; Layer 2 bundle cross-references are applied by the caller
via bundle_resolver.
"""
from __future__ import annotations

import re

from .errors import ValidationIssue
from .schema_loader import SchemaLoader
from .value_validator import validate_value, check_mutual_exclusion
from .exec_modes import MODE_CLASSES as _MODE_CLASSES, MODE_CLASS_LABEL as _MODE_CLASS_LABEL, effective_execution_mode as _effective_execution_mode

# Command keys accepted as comments / human metadata; the engine reads none of them.
_COMMAND_ANNOTATION_KEYS = {"VERSION", "NOTES", "CATEGORIES"}

_COND_IN_RE = re.compile(r"^(\w+)\s+in\s+\[(.*)\]$")


def _eval_condition(cond: str, obj: dict, dialog_name: str | None) -> bool:
    cond = cond.strip()
    if cond.startswith("mode:"):
        return _effective_execution_mode(obj) in _MODE_CLASSES.get(cond[5:], set())
    if cond.startswith("dialog="):
        return dialog_name == cond[len("dialog="):]
    m = _COND_IN_RE.match(cond)
    if m:
        opts = [o.strip() for o in m.group(2).split(",")]
        return obj.get(m.group(1)) in opts
    if "=" in cond:
        key, val = cond.split("=", 1)
        return obj.get(key.strip()) == val.strip()
    return cond in obj


def _humanize_condition(cond: str) -> str:
    cond = cond.strip()
    if cond.startswith("mode:"):
        return _MODE_CLASS_LABEL.get(cond[5:], cond)
    if cond.startswith("dialog="):
        return f"the dialog is {cond[len('dialog='):]}"
    m = _COND_IN_RE.match(cond)
    if m:
        return f"{m.group(1)} is one of [{m.group(2)}]"
    if "=" in cond:
        key, val = cond.split("=", 1)
        return f"{key.strip()} is '{val.strip()}'"
    return f"{cond} is set"


class PlistValidator:
    def __init__(self, loader: SchemaLoader):
        self._loader = loader

    # ── entry point ─────────────────────────────────────────────────────────
    def validate(self, root, path: str) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []

        if not isinstance(root, dict):
            return [ValidationIssue("error", path, "root of Command.plist must be a dictionary")]

        issues += self._validate_root(root, path)

        command_list = root.get("COMMAND_LIST")
        if isinstance(command_list, list):
            for i, cmd in enumerate(command_list):
                cpath = self._command_path(cmd, i)
                if isinstance(cmd, dict):
                    issues += self._validate_command(cmd, cpath)
                else:
                    issues.append(ValidationIssue("error", cpath, "command must be a dictionary"))
        return issues

    # ── Pass A — root ─────────────────────────────────────────────────────────
    def _validate_root(self, root: dict, path: str) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        schema = self._loader.root_schema() or {}
        props = schema.get("properties", {})

        # VERSION — absent defaults to 2 (fine); present must equal 2 or the engine
        # loads nothing (OnMyCommand.cp: `if(verNum != 2) return;`).
        if "VERSION" in root:
            v = root["VERSION"]
            if isinstance(v, bool) or not isinstance(v, int):
                issues.append(ValidationIssue("error", f"{path}.VERSION", "VERSION must be the integer 2"))
            elif v != 2:
                issues.append(ValidationIssue(
                    "error", f"{path}.VERSION",
                    f"VERSION is {v}; the engine loads nothing unless VERSION is 2"
                ))

        # COMMAND_LIST — required; absent or non-array means the engine loads nothing.
        cl = root.get("COMMAND_LIST")
        if cl is None:
            issues.append(ValidationIssue("error", f"{path}.COMMAND_LIST", "COMMAND_LIST is required"))
        elif not isinstance(cl, list):
            issues.append(ValidationIssue("error", f"{path}.COMMAND_LIST", "COMMAND_LIST must be an array"))
        elif len(cl) == 0:
            issues.append(ValidationIssue("warning", f"{path}.COMMAND_LIST", "COMMAND_LIST is empty — applet has no commands"))

        # unknown root keys
        allowed = set(props) | {"COMMAND_LIST", "VERSION"}
        for key in root:
            if key not in allowed:
                issues.append(ValidationIssue("warning", f"{path}.{key}", f"unexpected root key '{key}'"))
        return issues

    # ── Pass B — one command ──────────────────────────────────────────────────
    def _validate_command(self, cmd: dict, path: str) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        schema = self._loader.command_schema()
        if schema is None:
            return [ValidationIssue("error", path, "Command.json schema not found")]

        props = schema.get("properties", {})
        removed = schema.get("removedKeys", {})
        annotation_keys = set(schema.get("annotationKeys", _COMMAND_ANNOTATION_KEYS))

        # key recognition
        for key, value in cmd.items():
            if key in props:
                spec = props[key]
                if spec.get("deprecated"):
                    issues.append(self._key_deprecation(path, key, spec["deprecated"]))
                if "subschema" in spec:
                    issues += self._validate_value_then_subdict(key, value, spec, path)
                else:
                    issues += validate_value(key, value, spec, path)
            elif key in removed:
                issues.append(self._key_deprecation(path, key, {"removed": True, **removed[key]}))
            elif key in annotation_keys:
                pass  # human metadata; engine ignores
            else:
                issues.append(ValidationIssue("warning", f"{path}.{key}", f"unknown command key '{key}' — possible typo"))

        # required keys
        for key, spec in props.items():
            if spec.get("required") and key not in cmd:
                issues.append(ValidationIssue("error", f"{path}.{key}", f"required key '{key}' is missing"))

        # recommended keys (advisory only — never affects exit code)
        for key in schema.get("recommendedKeys", []):
            if key not in cmd:
                issues.append(ValidationIssue("info", f"{path}.{key}",
                                              f"recommended key '{key}' is missing"))

        # mutual exclusion at the command level
        issues += check_mutual_exclusion(cmd, schema.get("mutuallyExclusiveGroups", []), path)
        # conditional coherence rules (appliesWhen / requiredWhen)
        issues += self._check_conditionals(cmd, schema, path, dialog_name=None)
        return issues

    # ── Pass C — sub-dict dispatch ────────────────────────────────────────────
    def _validate_value_then_subdict(self, key: str, value, spec: dict, path: str) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        # First confirm it's the right shape (dict / oneOf etc.).
        issues += validate_value(key, value, spec, path)
        if not isinstance(value, dict):
            return issues
        sub = self._loader.subdict_schema(spec["subschema"])
        if sub is None:
            return issues  # schema not authored yet → treat as open dict
        issues += self._validate_subdict(value, sub, f"{path}.{key}")
        return issues

    def _validate_subdict(self, obj: dict, schema: dict, path: str) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        props = schema.get("properties", {})
        removed = schema.get("removedKeys", {})
        annotation_keys = set(schema.get("annotationKeys", []))

        for key, value in obj.items():
            if key in props:
                spec = props[key]
                if spec.get("deprecated"):
                    issues.append(self._key_deprecation(path, key, spec["deprecated"]))
                if "subschema" in spec:
                    issues += self._validate_value_then_subdict(key, value, spec, path)
                else:
                    issues += validate_value(key, value, spec, path)
            elif key in removed:
                issues.append(self._key_deprecation(path, key, {"removed": True, **removed[key]}))
            elif key in annotation_keys:
                pass
            elif schema.get("open"):
                pass  # open dict (e.g. ENVIRONMENT_VARIABLES): arbitrary keys allowed
            else:
                issues.append(ValidationIssue("warning", f"{path}.{key}", f"unknown key '{key}' in {schema.get('name', 'object')}"))

        for key, spec in props.items():
            if spec.get("required") and key not in obj:
                issues.append(ValidationIssue("error", f"{path}.{key}", f"required key '{key}' is missing"))

        issues += check_mutual_exclusion(obj, schema.get("mutuallyExclusiveGroups", []), path)
        issues += self._check_conditionals(obj, schema, path, dialog_name=schema.get("name"))
        return issues

    # ── conditional rules ───────────────────────────────────────────────────────
    def _check_conditionals(self, obj: dict, schema: dict, path: str, dialog_name: str | None) -> list[ValidationIssue]:
        """
        appliesWhen:  if the key is present but its condition is false → the key has
                      no effect at runtime (warning, or info for minor cases).
        requiredWhen: if the condition is true but the key is absent → it should be set.
        """
        issues: list[ValidationIssue] = []
        for key, spec in schema.get("properties", {}).items():
            if not isinstance(spec, dict):
                continue
            aw = spec.get("appliesWhen")
            if aw and key in obj and not _eval_condition(aw, obj, dialog_name):
                sev = spec.get("appliesWhenSeverity", "warning")
                issues.append(ValidationIssue(sev, f"{path}.{key}",
                                              f"'{key}' has no effect unless {_humanize_condition(aw)}"))
            rw = spec.get("requiredWhen")
            if rw and key not in obj and _eval_condition(rw, obj, dialog_name):
                sev = spec.get("requiredWhenSeverity", "warning")
                issues.append(ValidationIssue(sev, f"{path}.{key}",
                                              f"'{key}' should be set when {_humanize_condition(rw)}"))
        return issues

    # ── helpers ───────────────────────────────────────────────────────────────
    def _key_deprecation(self, path: str, key: str, info: dict) -> ValidationIssue:
        replacement = info.get("replacement")
        note = info.get("note")
        if info.get("removed"):
            msg = f"'{key}' is removed and ignored by the engine"
        else:
            msg = f"'{key}' is deprecated"
        if replacement:
            msg += f"; use '{replacement}'"
        if note:
            msg += f" ({note})"
        return ValidationIssue("warning", f"{path}.{key}", msg)

    def _command_path(self, cmd, index: int) -> str:
        if isinstance(cmd, dict):
            cid = cmd.get("COMMAND_ID")
            if isinstance(cid, str) and cid:
                return f"COMMAND_LIST[{index}] (COMMAND_ID={cid})"
        return f"COMMAND_LIST[{index}]"
