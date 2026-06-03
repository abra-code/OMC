"""
Shared execution-mode model. Single source of truth for how a command's
EXECUTION_MODE maps to behavior classes, used by both the conditional-rule engine
(plist_validator) and the bundle cross-referencer (bundle_resolver).
"""
from __future__ import annotations

# Deprecated aliases canonicalize to the mode the engine actually uses.
MODE_ALIASES = {
    "exe_popen": "exe_shell_script",
    "exe_silent_popen": "exe_shell_script",
    "exe_silent": "exe_shell_script",
    "exe_silent_system": "exe_system",
    "exe_popen_with_output_window": "exe_shell_script_with_output_window",
}

MODE_CLASSES = {
    "output_window": {"exe_shell_script_with_output_window", "exe_script_file_with_output_window", "exe_applescript_with_output_window"},
    "popen": {"exe_shell_script", "exe_script_file", "exe_shell_script_with_output_window", "exe_script_file_with_output_window"},
    "terminal": {"exe_terminal", "exe_iterm"},
    "iterm": {"exe_iterm"},
    "async": {"exe_shell_script", "exe_script_file", "exe_terminal", "exe_iterm", "exe_shell_script_with_output_window", "exe_script_file_with_output_window"},
    "sync": {"exe_system", "exe_applescript", "exe_applescript_with_output_window"},
}

MODE_CLASS_LABEL = {
    "output_window": "EXECUTION_MODE is an output-window mode",
    "popen": "EXECUTION_MODE is a shell/script (popen) mode",
    "terminal": "EXECUTION_MODE is exe_terminal or exe_iterm",
    "iterm": "EXECUTION_MODE is exe_iterm",
    "async": "the command runs asynchronously",
    "sync": "the command runs synchronously",
}

# Modes that resolve their executable from a script file named after the COMMAND_ID.
SCRIPT_FILE_MODES = {"exe_script_file", "exe_script_file_with_output_window"}
# Modes that run an inline COMMAND array.
INLINE_COMMAND_MODES = {
    "exe_shell_script", "exe_shell_script_with_output_window",
    "exe_system", "exe_applescript", "exe_applescript_with_output_window",
    "exe_terminal", "exe_iterm",
}


def effective_execution_mode(cmd: dict) -> str:
    """
    Resolve the mode the engine will actually use: honor deprecated aliases and the
    COMMAND-presence default (exe_shell_script if COMMAND present, else exe_script_file).
    """
    m = cmd.get("EXECUTION_MODE")
    if isinstance(m, str) and m:
        return MODE_ALIASES.get(m, m)
    return "exe_shell_script" if "COMMAND" in cmd else "exe_script_file"
