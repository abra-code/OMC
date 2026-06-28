---
id: core
level: 1
flavors: [claude, capable, lite]
---

## What is OMC

OMC (OnMyCommand) is a macOS low-code app builder engine. OMC **applets** are GUI `.app` bundles, with optional macOS Services menu items. Each applet combines a declarative command manifest (`Command.plist`) with shell scripts, Python scripts, or AppleScript files that implement the actions.

The OMC engine (`Abracode.framework`) handles app runtime, input routing, UI presentation, and script execution. A developer writes only the application-specific logic.

**User should start a new applet using AppletBuilder** (`Distribution/AppletBuilder.app`) — it creates the correct bundle structure, installs the framework, and generates the initial `Command.plist` and starter scripts.

## OMC App Bundle Structure

```
MyApp.app/
├── Contents/
│   ├── Frameworks/
│   │   └── Abracode.framework       ← OMC engine (copied from AppletBuilder template)
│   ├── MacOS/
│   │   └── MyApp                    ← executable (renamed copy of OMC binary)
│   ├── Resources/
│   │   ├── Base.lproj/
│   │   │   ├── MainMenu.nib         ← app menu (from template; do not remove)
│   │   │   └── MyDialog.json        ← optional ActionUI JSON dialog
│   │   ├── Scripts/
│   │   │   ├── lib.myapp.sh         ← shared library: tool paths + control IDs
│   │   │   └── MyApp.*.sh / *.py    ← action handler scripts
│   │   └── Command.plist            ← command definitions
│   └── Info.plist
```

## Command.plist

The command manifest lives at `Contents/Resources/Command.plist` (XML/binary plist) **or** `Contents/Resources/Command.json` (JSON). OMC reads either, preferring `Command.json` when both are present; AppletBuilder creates new applets with `Command.json`. The two formats are structurally identical — the same keys, value types, and `VERSION == 2` rule apply (a JSON number `2` for `VERSION`, JSON `true`/`false` for booleans). This guide shows plist XML, but every example maps directly to JSON.

**Root structure (plist):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>COMMAND_LIST</key>
    <array>
        <!-- one <dict> per command -->
    </array>
    <key>VERSION</key>
    <integer>2</integer>
</dict>
</plist>
```

**Root structure (JSON equivalent):**
```json
{
  "COMMAND_LIST": [
    {  }
  ],
  "VERSION": 2
}
```

### Command Identity Keys

| Key | Type | Notes |
|-----|------|-------|
| `NAME` | string | Human-readable label. Required. Shared across a command group. |
| `COMMAND_ID` | string | Dot-notation ID (e.g. `MyApp.results.selected`). Required for subcommands. On the **main command** either omit it or set it explicitly to `<NAME>.main` (or bare `main`) — both are equivalent. The main command is also addressable for chaining by `<NAME>.main`, `main`, or the legacy internal `top!`. Its script filename follows the convention `<NAME>.main.<ext>`. |
| `EXECUTION_MODE` | string | How the command runs. Default: `exe_script_file` or `exe_shell_script` if `COMMAND` is set. |
| `ACTIVATION_MODE` | string | What context information the command expects. Default: `act_always`. |

### Minimal command

```xml
<dict>
    <key>NAME</key>
    <string>MyApp</string>
    <key>EXECUTION_MODE</key>
    <string>exe_script_file</string>
    <key>ACTIVATION_MODE</key>
    <string>act_file_or_folder</string>
</dict>
```

## Script Naming Convention

Script files live in `Contents/Resources/Scripts/`. The filename maps directly to a `COMMAND_ID`:

| Script file | Handles COMMAND_ID |
|-------------|--------------------|
| `MyApp.main.sh` | the main command (no `COMMAND_ID`, or `COMMAND_ID` = `MyApp.main`) — `MyApp` is the `NAME` |
| `MyApp.results.selected.py` | `MyApp.results.selected` |
| `MyApp.settings.save.sh` | `MyApp.settings.save` |
| `lib.myapp.sh` | *(shared library — sourced by other scripts, not a command handler)* |

OMC resolves the interpreter from the extension: `.sh` / `.bash` / `.zsh` → corresponding shell, `.py` → Python, `.applescript` → AppleScript, `.js` → JSC.

**No shebang line is needed.** OMC supplies the interpreter path automatically.

For Python applets, the embedded Python at `Contents/Library/Python/bin/python3` is used when present — no system Python dependency. When a bundle has embedded Python, OMC exports — for every handler, shell or Python — `PATH` (prepended with the interpreter's `bin/`), `PYTHONPYCACHEPREFIX=/tmp/Pyc`, and `PYTHONPATH` (prepended with `Contents/Library/Packages/` when it exists). Install third-party modules into `Contents/Library/Packages/` (e.g. `python3 -m pip install --target .../Contents/Library/Packages pkg`) rather than the runtime's own `site-packages`: the `Packages/` dir survives a Python runtime upgrade/rebuild, whereas `Contents/Library/Python/` is replaced wholesale. See `docs/omc_python_scripting_guide.md`.
