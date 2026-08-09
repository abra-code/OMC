"""
Layer 2 — bundle-aware cross-referencing.

Given an applet bundle, builds three indices and checks that what Command.plist
references actually exists / resolves:

  * script map      — Contents/Resources/Scripts/* keyed by lowercase name-sans-ext
                      (the engine resolves exe_script_file by lowercase COMMAND_ID).
  * resource index  — *.json and *.nib basenames (for JSON_NAME / NIB_NAME), plus all
                      resource file basenames (for CUSTOM_WINDOW_PNG_IMAGE).
  * command graph   — declared COMMAND_IDs (+ group) ∪ synthesizable script IDs.
                      The no-COMMAND_ID main command also contributes its implicit
                      '<NAME>.main' / 'main' / 'top!' ids so references resolve.
                      Subcommand-ID references must resolve into this set, and so
                      must every *ActionID in the bundle's JSON UI documents.

Synthesizable IDs mirror the engine's CreateAugmentedCommandArray filter
(OnMyCommand.cp): scripts whose lowercase name is not lib_/lib.-prefixed, not
top!/main, not *.main, and not already declared become commands automatically.
"""
from __future__ import annotations

import json
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

# ActionUI documents wire controls to commands through keys whose names end in
# "ActionID": actionID, onDropActionID, valueChangeActionID, viewDidLoadActionID,
# doubleClickActionID, sheetOnDismissActionID, ... (25+ across the ActionUI schemas,
# all declared "types": ["string"]). Every one of them names a command the engine
# dispatches verbatim: ActionUI's default action handler calls
# OMCWindowController's dispatchCommand:, which resolves the string through
# FindCommandIndex the same way NEXT_COMMAND_ID is resolved. A typo there is a
# control that silently does nothing, so cross-check them like subcommand refs.
# Match on the suffix rather than a fixed key list so ActionUI can add handler
# keys without this check going blind. The suffix is case-SENSITIVE: every one of
# the 25 shipped keys is either exactly "actionID" or ends in "ActionID" with that
# capital A, while data keys like "transactionID" / "interactionID" end in a
# lowercase-a "actionID" and would otherwise be swept in.
_ACTION_ID_SUFFIX = "ActionID"

# Ids the engine answers without a COMMAND_LIST entry. These are the five dotted
# members of OMCDialog::IsPredefinedDialogCommandID's set (OMCDialog.mm), which
# also holds the Carbon-legacy 4-char ids "ok  " / "cncl" / "ini!" / "end!" /
# "cnc!" - deliberately NOT whitelisted, since those run only when declared as a
# same-NAME subcommand (FindSubcommandIndex is strict), so an undeclared one is
# genuinely dead wiring. Of the five below, only omc.dialog.ok / .cancel are
# answered natively (OMCWindowController's isOkeyed / isCanceled close path); the
# other three likewise need a declaration to do anything, and are whitelisted only
# because flagging a conventional id is more noise than help.
_RESERVED_ACTION_IDS = frozenset({
    "omc.dialog.ok",
    "omc.dialog.cancel",
    "omc.dialog.initialize",
    "omc.dialog.terminate.ok",
    "omc.dialog.terminate.cancel",
})

# The bundle's own command description: a JSON sibling of the UI documents but not
# one of them, and already validated in full by Layer 1.
_COMMAND_FILE_NAMES_LC = frozenset({"command.json", "command.plist"})


def _strip_trailing_commas(text: str) -> str:
    """Remove `,` that sits directly before a `}` or `]`.

    Foundation's JSONSerialization - which is what the engine and ActionUI parse
    with - accepts trailing commas, so a document carrying them loads and renders
    fine while Python's strict json rejects it. Skipping such a file would leave
    its wiring unchecked, so we retry through this. Unlike a bare regex, the scan
    tracks string state, so a `, }` inside a title or help string is left alone.
    """
    out: list[str] = []
    in_string = False
    escaped = False
    pending_comma = -1  # index in `out` of a comma still looking for its closer
    for ch in text:
        if in_string:
            out.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
            pending_comma = -1
        elif ch == ",":
            pending_comma = len(out)
        elif ch in "}]":
            if pending_comma >= 0:
                out[pending_comma] = ""
            pending_comma = -1
        elif not ch.isspace():
            pending_comma = -1
        out.append(ch)
    return "".join(out)


def _collect_action_ids(root) -> dict[tuple[str, str], int]:
    """Map every (key, value) pair whose key name ends in 'ActionID' to its number
    of occurrences, walking the whole document.

    The root may be a list (every applet's MainMenu.json is a JSON array) and the
    keys sit at arbitrary depth inside nested children/properties, so the walk
    handles both. It is iterative on purpose: a deeply nested document would
    otherwise raise RecursionError, which the caller cannot usefully distinguish
    from a real failure and which would abort the whole verifier run. Insertion
    order is document order, which keeps findings stable.
    """
    found: dict[tuple[str, str], int] = {}
    stack = [root]
    while stack:
        node = stack.pop()
        if isinstance(node, dict):
            children = []
            for k, v in node.items():
                if isinstance(v, str):
                    if v and (k == "actionID" or k.endswith(_ACTION_ID_SUFFIX)):
                        found[(k, v)] = found.get((k, v), 0) + 1
                elif isinstance(v, (dict, list)):
                    children.append(v)
            stack.extend(reversed(children))
        elif isinstance(node, list):
            stack.extend(reversed([v for v in node if isinstance(v, (dict, list))]))
    return found


class BundleResolver:
    def __init__(self, bundle_path: str | Path):
        self.bundle = Path(bundle_path)
        self.resources = self.bundle / "Contents" / "Resources"
        self._scripts_lc: set[str] | None = None
        self._scripts_orig: set[str] | None = None
        self._json_lc: set[str] | None = None
        self._nib_lc: set[str] | None = None
        self._resource_files_lc: set[str] | None = None

    # ── index builders (lazy) ─────────────────────────────────────────────────
    def _scan_scripts(self) -> None:
        """Index Scripts/ once, keeping both spellings of every stem: lowercase for
        the engine's script-file lookup, original case because a synthesized
        COMMAND_ID keeps the filesystem case on purpose (OnMyCommand.cp recovers the
        original name so the id 'is usable as a case-sensitive lookup key in
        FindCommandIndex')."""
        if self._scripts_lc is not None:
            return
        lc: set[str] = set()
        orig: set[str] = set()
        sdir = self.resources / "Scripts"
        if sdir.is_dir():
            for p in sdir.iterdir():
                if p.is_file():
                    lc.add(p.stem.lower())
                    orig.add(p.stem)
        self._scripts_lc, self._scripts_orig = lc, orig

    def _scripts(self) -> set[str]:
        self._scan_scripts()
        return self._scripts_lc

    def _scripts_original(self) -> set[str]:
        self._scan_scripts()
        return self._scripts_orig

    @staticmethod
    def _is_synthesizable(name_lc: str) -> bool:
        """The engine's CreateAugmentedCommandArray filter, which runs on the
        lowercase name whatever case the file itself carries."""
        if name_lc.startswith("lib_") or name_lc.startswith("lib."):
            return False
        if name_lc in (_TOP_ID, "main"):
            return False
        if name_lc.endswith(".main"):
            return False
        return True

    def _synthesizable(self) -> set[str]:
        """Script IDs the engine would auto-promote to commands, lowercased."""
        return {n for n in self._scripts() if self._is_synthesizable(n)}

    def _synthesizable_exact(self) -> set[str]:
        """The same IDs in the case the engine actually registers them under.

        On a case-sensitive volume two stems can differ only in case, and the engine's
        script cache keeps just the first (CFDictionaryAddValue on the lowercase key),
        so only one of them becomes a command. Registering both can at worst suppress
        a case-only warning; it cannot invent one, and the two files cannot coexist on
        a default APFS volume anyway.
        """
        return {n for n in self._scripts_original() if self._is_synthesizable(n.lower())}

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

        # actionID cross-check - document-driven, so once per bundle, not per command
        issues += self._check_actionui_action_ids(self._exact_spellings(commands))

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

    def _ui_documents(self) -> list[Path]:
        """The JSON documents the engine can load as UI for THIS bundle.

        That is Resources/*.json plus Resources/*.lproj/*.json - exactly where
        NSBundle's resource lookup finds a JSON_NAME (both spellings occur in
        practice: window documents live in Base.lproj, while Interpreter.app keeps a
        fragment template at the Resources root). Deeper subtrees are deliberately
        out of scope, and not only for speed: AppletBuilder itself ships ActionUI
        example documents under Resources/Documentation/Elements/ and whole nested
        applets under Resources/Templates/, whose ids belong to other command lists
        (or to no command list at all) and produced 43 false warnings when the scan
        was a plain rglob. The command file is skipped by name: it is a JSON sibling
        of the UI documents, not one of them, and Layer 1 validates it in full.
        """
        if not self.resources.is_dir():
            return []
        docs = [p for p in self.resources.glob("*.json") if p.is_file()]
        for lproj in self.resources.glob("*.lproj"):
            if lproj.is_dir():
                docs += [p for p in lproj.glob("*.json") if p.is_file()]
        return sorted(p for p in docs if p.name.lower() not in _COMMAND_FILE_NAMES_LC)

    def _check_actionui_action_ids(self, exact_spellings: dict[str, set[str]]) -> list[ValidationIssue]:
        """Cross-check every *ActionID in the bundle's JSON UI documents.

        Discovery is document-driven, not command-driven (see _ui_documents), because
        MainMenu.json is loaded by the app lifecycle with no command referencing it at
        all, yet carries real menu wiring. Nothing here complains that a document is
        unreferenced: for MainMenu.json being unreferenced is the normal state.

        Two kinds of dead wiring are reported. An id nothing provides is the obvious
        one. An id that differs only in case is the quieter one: every engine lookup
        on this path is case-sensitive (CFEqual in both FindCommandIndex variants,
        CFStringCompare with no flags in FindMainCommandByImplicitID), and synthesized
        COMMAND_IDs keep the script's filesystem case precisely so they can be matched
        that way, so 'MyApp.Save' against a declared 'myapp.save' is a button that
        does nothing at runtime while looking correct in review.

        Resolution is judged against _exact_spellings alone rather than against the
        lowercase `resolvable` set the subcommand check uses. The two agree except
        where the engine's exact main-command normalization does (see
        _is_main_command), and there the exact map is the faithful one.

        Documents that do not parse even after trailing-comma repair are skipped
        silently - fragment templates carrying substitution placeholders
        (Interpreter.app's model.card.template.json has bare `__ID__` tokens where
        JSON wants values) are not JSON until the handler expands them, and a real UI
        document's syntax is the ActionUI verifier's job, not this one's.

        Known limitation: menu items dispatched while no OMC window is key go through
        the one-argument FindCommandIndex, which also matches a command group NAME. A
        MainMenu.json Button whose actionID is a NAME rather than an id is therefore
        warned about here even though it can work - but only in that one window state,
        which is why the warning is arguably the more useful answer.

        Severity is warning, not error: the check is new, existing applets must keep
        building, and --strict promotes it for anyone who wants the hard line.
        """
        issues: list[ValidationIssue] = []
        for doc in self._ui_documents():
            try:
                raw = doc.read_bytes()
            except OSError:
                continue
            try:
                data = json.loads(raw)
            except Exception:
                try:
                    data = json.loads(_strip_trailing_commas(raw.decode("utf-8", "replace")))
                except Exception:
                    continue
            rel = doc.relative_to(self.resources).as_posix()
            for (key, value), count in _collect_action_ids(data).items():
                times = f" ({count} occurrences)" if count > 1 else ""
                spellings = exact_spellings.get(value.lower())
                if spellings and value in spellings:
                    continue
                if spellings:
                    actual = "' or '".join(sorted(spellings))
                    issues.append(ValidationIssue(
                        "warning", rel,
                        f"{key} '{value}' matches '{actual}' only case-insensitively; "
                        f"the engine dispatches case-sensitively, so this control does "
                        f"nothing{times}"
                    ))
                else:
                    issues.append(ValidationIssue(
                        "warning", rel,
                        f"{key} '{value}' does not resolve to any command or script "
                        f"in the bundle{times}"
                    ))
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
            aliases = self._main_command_aliases(cmd)  # {'top!', 'main', '<name>.main'}
            if cid_lc in aliases:
                # The main command, identified either the legacy way (no COMMAND_ID ->
                # 'top!') or the explicit way (COMMAND_ID = '<NAME>.main' / 'main'). Both
                # are equivalent — register every alias so references via any of them
                # resolve, and normalize the group key to 'top!' for duplicate detection.
                # Mirrors the engine, which normalizes an explicit '<NAME>.main' / 'main'
                # COMMAND_ID to the 'top!' sentinel.
                declared_lc |= aliases
                cid_lc = _TOP_ID
            else:
                declared_lc.add(cid_lc)
            group_pairs.append((self._group_key(cmd), cid_lc, idx))
        return declared_lc, group_pairs

    def _exact_spellings(self, commands: list) -> dict[str, set[str]]:
        """Every dispatchable id in the case(s) the engine registers it under, keyed
        by lowercase form. Lets the actionID check tell "no such command" apart from
        "right command, wrong case" - the latter is dead wiring too, because every
        lookup on that path is case-sensitive.

        Same membership as `resolvable`, with the engine's own precedence: a script
        is synthesized into a command only when its lowercase stem is not already a
        declared COMMAND_ID (CreateAugmentedCommandArray's declaredIDs check), so a
        declared 'otool.arch.changed' beside an OTool.arch.changed.sh registers the
        declared spelling alone. A main command is reachable as 'top!', 'main', or
        '<NAME>.main' built from the NAME as written, never through the literal
        COMMAND_ID spelling the engine normalized away - and a COMMAND_ID that only
        looks like one of those (see _is_main_command) was never normalized, so it
        registers under itself and nothing else. The reserved omc.dialog.* ids are
        lowercase literals.
        """
        exact: dict[str, set[str]] = {}

        def put(value: str) -> None:
            exact.setdefault(value.lower(), set()).add(value)

        declared_lc: set[str] = set()
        for cmd in commands:
            if not isinstance(cmd, dict):
                continue
            cid = cmd.get("COMMAND_ID")
            has_id = isinstance(cid, str) and bool(cid)
            if has_id:
                declared_lc.add(cid.lower())
            if self._is_main_command(cmd):
                put(_TOP_ID)
                put("main")
                name = self._group_key(cmd)
                if name:
                    put(f"{name}.main")
            elif has_id:
                put(cid)
        for name in self._synthesizable_exact():
            if name.lower() not in declared_lc:
                put(name)
        for reserved in _RESERVED_ACTION_IDS:
            put(reserved)
        return exact

    @staticmethod
    def _is_main_command(cmd: dict) -> bool:
        """Whether the engine turns this command into THE main command.

        It normalizes an explicit COMMAND_ID to the 'top!' sentinel only on an exact
        match - CFStringCompare(id, "main", 0) with no flags, or CFEqual against
        "<NAME as written>.main" (CommandDescription.cp, GetOneCommandParams). A
        near-miss like COMMAND_ID='myapp.main' under NAME='MyApp' is therefore NOT
        the main command: it keeps its literal id, is dispatched by that id, and
        answers to none of 'top!' / 'main' / 'MyApp.main'. Matching case-insensitively
        here would call a working control dead and let three dead ones pass.

        The engine's guard is `outDesc.name != NULL`, and a string NAME is wrapped
        into a one-element array before combining, so a NAME that is present but
        EMPTY still forms an implicit id - '.main' - while a missing NAME forms none.
        Degenerate, but the distinction is free to honor and this helper claims to
        mirror the engine exactly.
        """
        cid = cmd.get("COMMAND_ID")
        if not (isinstance(cid, str) and cid):
            return True  # no COMMAND_ID: the legacy main command
        if cid in (_TOP_ID, "main"):
            return True
        name = cmd.get("NAME")
        if isinstance(name, list):
            name = "".join(str(p) for p in name)
        if not isinstance(name, str):
            return False  # no NAME at all: no implicit '<NAME>.main' id exists
        return cid == f"{name}.main"

    @staticmethod
    def _main_command_aliases(cmd: dict) -> set[str]:
        """Implicit ids that resolve to a no-COMMAND_ID main command: its
        '<NAME>.main' id, the bare 'main' fallback, and the legacy 'top!'."""
        aliases = {_TOP_ID, "main"}
        name = cmd.get("NAME")
        if isinstance(name, list):
            name = "".join(str(p) for p in name)
        if isinstance(name, str) and name:
            aliases.add(f"{name}.main".lower())
        return aliases

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
