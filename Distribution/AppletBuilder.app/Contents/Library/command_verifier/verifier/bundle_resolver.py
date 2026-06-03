"""
Layer 2 — bundle-aware cross-referencing.

Given an applet bundle, builds three indices and checks that what Command.plist
references actually exists / resolves:

  * script map      — Contents/Resources/Scripts/* keyed by lowercase name-sans-ext
                      (the engine resolves exe_script_file by lowercase COMMAND_ID).
  * resource index  — *.json and *.nib basenames (for JSON_NAME / NIB_NAME), plus all
                      resource file basenames (for CUSTOM_WINDOW_PNG_IMAGE).
  * command graph   — declared COMMAND_IDs (+ group) ∪ synthesizable script IDs.
                      Subcommand-ID references must resolve into this set.

Synthesizable IDs mirror the engine's CreateAugmentedCommandArray filter
(OnMyCommand.cp): scripts whose lowercase name is not lib_/lib.-prefixed, not
top!/main, not *.main, and not already declared become commands automatically.
"""
from __future__ import annotations

from pathlib import Path

from .errors import ValidationIssue
from .exec_modes import effective_execution_mode, SCRIPT_FILE_MODES, INLINE_COMMAND_MODES

# Subcommand-ID reference keys inside NIB_DIALOG / ACTIONUI_WINDOW.
_SUBCOMMAND_REF_KEYS = (
    "INIT_SUBCOMMAND_ID", "END_OK_SUBCOMMAND_ID", "END_CANCEL_SUBCOMMAND_ID",
    "WINDOW_DID_ACTIVATE_SUBCOMMAND_ID", "WINDOW_DID_DEACTIVATE_SUBCOMMAND_ID",
)
_TOP_ID = "top!"

# Keys that give a command a purpose even with no executable body of its own.
# A command normally runs either an inline COMMAND array or a script file named
# after its COMMAND_ID. When it has neither it still does useful work if it
# presents a dialog / prompt (whose init/OK subcommands do the work) or chains to
# another command via NEXT_COMMAND_ID. Any of these makes a missing body a
# deliberate, common pattern rather than a no-op.
_NO_BODY_OK_KEYS = (
    "NIB_DIALOG", "ACTIONUI_WINDOW",
    "INPUT_DIALOG", "SAVE_AS_DIALOG",
    "CHOOSE_FILE_DIALOG", "CHOOSE_FOLDER_DIALOG",
    "CHOOSE_OBJECT_DIALOG", "OPEN_OBJECT_DIALOG",
    "NEXT_COMMAND_ID",
)


class BundleResolver:
    def __init__(self, bundle_path: str | Path):
        self.bundle = Path(bundle_path)
        self.resources = self.bundle / "Contents" / "Resources"
        self._scripts_lc: set[str] | None = None
        self._json_lc: set[str] | None = None
        self._nib_lc: set[str] | None = None
        self._resource_files_lc: set[str] | None = None

    # ── index builders (lazy) ─────────────────────────────────────────────────
    def _scripts(self) -> set[str]:
        if self._scripts_lc is None:
            s: set[str] = set()
            sdir = self.resources / "Scripts"
            if sdir.is_dir():
                for p in sdir.iterdir():
                    if p.is_file():
                        s.add(p.stem.lower())
            self._scripts_lc = s
        return self._scripts_lc

    def _synthesizable(self) -> set[str]:
        """Script IDs the engine would auto-promote to commands."""
        out = set()
        for name in self._scripts():
            if name.startswith("lib_") or name.startswith("lib."):
                continue
            if name in (_TOP_ID, "main"):
                continue
            if name.endswith(".main"):
                continue
            out.add(name)
        return out

    def _json_names(self) -> set[str]:
        if self._json_lc is None:
            self._json_lc = {p.stem.lower() for p in self.resources.rglob("*.json")} if self.resources.is_dir() else set()
        return self._json_lc

    def _nib_names(self) -> set[str]:
        if self._nib_lc is None:
            # .nib can be a directory or a file; rglob matches both as path entries.
            self._nib_lc = {p.stem.lower() for p in self.resources.rglob("*.nib")} if self.resources.is_dir() else set()
        return self._nib_lc

    def _resource_basenames(self) -> set[str]:
        if self._resource_files_lc is None:
            s: set[str] = set()
            if self.resources.is_dir():
                for p in self.resources.rglob("*"):
                    if p.is_file():
                        s.add(p.name.lower())
            self._resource_files_lc = s
        return self._resource_files_lc

    # ── entry point ───────────────────────────────────────────────────────────
    def cross_reference(self, data: dict, plist_path: str) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        commands = data.get("COMMAND_LIST")
        if not isinstance(commands, list):
            return issues

        declared_lc, group_pairs = self._declared(commands)
        resolvable = declared_lc | self._synthesizable()

        # duplicate (group, COMMAND_ID) detection
        issues += self._check_duplicates(group_pairs, commands)

        for i, cmd in enumerate(commands):
            if not isinstance(cmd, dict):
                continue
            path = self._cmd_path(cmd, i)
            issues += self._check_executable(cmd, path)
            issues += self._check_dialog_resources(cmd, path)
            issues += self._check_subcommand_refs(cmd, path, resolvable)
            issues += self._check_image(cmd, path)
        return issues

    # ── individual checks ─────────────────────────────────────────────────────
    def _check_executable(self, cmd: dict, path: str) -> list[ValidationIssue]:
        """Note a command that has no executable body of its own.

        A command runs either an inline COMMAND array (shell/applescript modes) or
        a script file named after its COMMAND_ID (exe_script_file modes). Having
        neither is a legitimate, common pattern when the command instead presents a
        dialog/prompt — its init/OK subcommands do the work — or chains via
        NEXT_COMMAND_ID. So we suppress entirely in those cases, and otherwise emit
        an advisory `info` note (never an error/warning) that the command appears to
        be a no-op. For script-file modes that note also surfaces a likely typo in
        COMMAND_ID.
        """
        if any(k in cmd for k in _NO_BODY_OK_KEYS):
            return []

        mode = effective_execution_mode(cmd)
        cid = cmd.get("COMMAND_ID")
        has_explicit_id = isinstance(cid, str) and cid and cid != _TOP_ID

        if mode in SCRIPT_FILE_MODES:
            # Only check when the command has an explicit COMMAND_ID — the main
            # (top!) command resolves its script differently and must not false-flag.
            if has_explicit_id and cid.lower() not in self._scripts():
                return [ValidationIssue(
                    "info", f"{path}.COMMAND_ID",
                    f"EXECUTION_MODE resolves to a script file but no script named "
                    f"'{cid}.*' exists in Contents/Resources/Scripts/ — the command "
                    f"has no executable body. That is fine if it presents a dialog or "
                    f"chains via NEXT_COMMAND_ID; otherwise it does nothing (check for "
                    f"a typo in COMMAND_ID)."
                )]
        elif mode in INLINE_COMMAND_MODES:
            if "COMMAND" not in cmd:
                return [ValidationIssue(
                    "info", f"{path}.COMMAND",
                    f"EXECUTION_MODE '{cmd.get('EXECUTION_MODE', mode)}' runs an inline "
                    f"COMMAND but none is present — the command has no executable body. "
                    f"That is fine if it presents a dialog or chains via NEXT_COMMAND_ID; "
                    f"otherwise it does nothing."
                )]
        return []

    def _check_dialog_resources(self, cmd: dict, path: str) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []
        aui = cmd.get("ACTIONUI_WINDOW")
        if isinstance(aui, dict):
            name = aui.get("JSON_NAME")
            if isinstance(name, str) and name and name.lower() not in self._json_names():
                issues.append(ValidationIssue(
                    "error", f"{path}.ACTIONUI_WINDOW.JSON_NAME",
                    f"no JSON resource named '{name}.json' found in the bundle"
                ))
        nib = cmd.get("NIB_DIALOG")
        if isinstance(nib, dict):
            name = nib.get("NIB_NAME")
            if isinstance(name, str) and name and name.lower() not in self._nib_names():
                issues.append(ValidationIssue(
                    "error", f"{path}.NIB_DIALOG.NIB_NAME",
                    f"no nib named '{name}.nib' found in the bundle"
                ))
        return issues

    def _check_subcommand_refs(self, cmd: dict, path: str, resolvable: set[str]) -> list[ValidationIssue]:
        issues: list[ValidationIssue] = []

        def check(ref, where):
            if isinstance(ref, str) and ref and ref.lower() not in resolvable:
                issues.append(ValidationIssue(
                    "error", where,
                    f"subcommand '{ref}' does not resolve to any command or script in the bundle"
                ))

        check(cmd.get("NEXT_COMMAND_ID"), f"{path}.NEXT_COMMAND_ID")
        for container_key in ("NIB_DIALOG", "ACTIONUI_WINDOW"):
            sub = cmd.get(container_key)
            if isinstance(sub, dict):
                for k in _SUBCOMMAND_REF_KEYS:
                    check(sub.get(k), f"{path}.{container_key}.{k}")
        return issues

    def _check_image(self, cmd: dict, path: str) -> list[ValidationIssue]:
        ows = cmd.get("OUTPUT_WINDOW_SETTINGS")
        if not isinstance(ows, dict):
            return []
        img = ows.get("CUSTOM_WINDOW_PNG_IMAGE")
        if isinstance(img, str) and img:
            base = Path(img).name.lower()
            if base not in self._resource_basenames():
                return [ValidationIssue(
                    "warning", f"{path}.OUTPUT_WINDOW_SETTINGS.CUSTOM_WINDOW_PNG_IMAGE",
                    f"image '{img}' not found in the bundle's Resources"
                )]
        return []

    def _check_duplicates(self, group_pairs: list[tuple], commands: list) -> list[ValidationIssue]:
        """Same (group NAME, COMMAND_ID) twice is an ambiguous dispatch target."""
        issues: list[ValidationIssue] = []
        seen: dict[tuple, int] = {}
        top_per_group: dict[str, int] = {}
        for (group, cid_lc, idx) in group_pairs:
            if cid_lc == _TOP_ID:
                top_per_group[group] = top_per_group.get(group, 0) + 1
                continue
            key = (group, cid_lc)
            if key in seen:
                path = self._cmd_path(commands[idx], idx)
                issues.append(ValidationIssue(
                    "error", path,
                    f"duplicate COMMAND_ID within command group '{group or '(unnamed)'}' — "
                    f"COMMAND_IDs must be unique per group"
                ))
            else:
                seen[key] = idx
        for group, count in top_per_group.items():
            if count > 1:
                issues.append(ValidationIssue(
                    "warning", f"COMMAND_LIST (group '{group or '(unnamed)'}')",
                    f"{count} commands lack a COMMAND_ID in this group; all default to 'top!' "
                    f"and only the first is reachable"
                ))
        return issues

    # ── helpers ───────────────────────────────────────────────────────────────
    def _declared(self, commands: list) -> tuple[set[str], list[tuple]]:
        declared_lc: set[str] = set()
        group_pairs: list[tuple] = []
        for idx, cmd in enumerate(commands):
            if not isinstance(cmd, dict):
                continue
            cid = cmd.get("COMMAND_ID")
            cid_lc = cid.lower() if isinstance(cid, str) and cid else _TOP_ID
            declared_lc.add(cid_lc)
            group_pairs.append((self._group_key(cmd), cid_lc, idx))
        return declared_lc, group_pairs

    @staticmethod
    def _group_key(cmd: dict) -> str:
        name = cmd.get("NAME")
        if isinstance(name, str):
            return name
        if isinstance(name, list):
            return "".join(str(x) for x in name)
        return ""

    @staticmethod
    def _cmd_path(cmd, index: int) -> str:
        if isinstance(cmd, dict):
            cid = cmd.get("COMMAND_ID")
            if isinstance(cid, str) and cid:
                return f"COMMAND_LIST[{index}] (COMMAND_ID={cid})"
        return f"COMMAND_LIST[{index}]"
