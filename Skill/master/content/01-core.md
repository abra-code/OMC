---
id: core
level: 1
flavors: [claude, capable, lite]
---

## What is Command Workshop

Command Workshop (formerly OMC) is a macOS low-code app builder engine. Command Workshop **applets** are GUI `.app` bundles, with optional macOS Services menu items. Each applet combines a declarative command manifest (`Command.json`) with shell scripts, Python scripts, or AppleScript files that implement the actions.

The Command Engine (`Command.framework`) handles app runtime, input routing, UI presentation, and script execution. A developer writes only the application-specific logic.

**User should start a new applet using AppletBuilder** (`Distribution/AppletBuilder.app`) — it creates the correct bundle structure, installs the framework, and generates the initial `Command.json` and starter scripts.

## Command Workshop App Bundle Structure

```
MyApp.app/
├── Contents/
│   ├── Frameworks/
│   │   └── Command.framework       ← OMC engine (copied from AppletBuilder template)
│   ├── MacOS/
│   │   └── MyApp                    ← executable (renamed copy of OMC binary)
│   ├── Resources/
│   │   ├── Base.lproj/
│   │   │   ├── MainMenu.json        ← optional menu bar additions (the standard bar is built in code)
│   │   │   └── MyDialog.json        ← optional ActionUI JSON dialog
│   │   ├── Scripts/
│   │   │   ├── lib.myapp.sh         ← shared library: tool paths + control IDs
│   │   │   └── MyApp.*.sh / *.py    ← action handler scripts
│   │   ├── Credits.md               ← expected: Markdown the About window shows (no Credits.rtf)
│   │   └── Command.json             ← command definitions (legacy applets: Command.plist)
│   └── Info.plist
```

## Command.json

The command manifest is `Contents/Resources/Command.json`. AppletBuilder creates new applets with it; write every new command file as `Command.json`, and this guide shows JSON throughout.

Applets made before 6.0 may have a legacy `Command.plist` (XML or binary plist) instead, with the same keys and value types (`<integer>2</integer>` for `VERSION`, `<true/>`/`<false/>` for booleans). The Command Engine still reads it, but prefers `Command.json` when both exist, so never leave both: edits to the `Command.plist` would be silently ignored. To move a legacy applet to JSON (on macOS): `plutil -convert json -r -o Command.json Command.plist` (`-r` writes it indented), validate the result, then delete `Command.plist`. Without converting, edit the `Command.plist` in its own format.

**Root structure:**
```json
{
  "COMMAND_LIST": [
    {  }
  ],
  "VERSION": 2
}
```

`VERSION` must be the number `2`; booleans are JSON `true`/`false`.

### Command Identity Keys

| Key | Type | Notes |
|-----|------|-------|
| `NAME` | string | Human-readable label. Required. Shared across a command group. |
| `COMMAND_ID` | string | Dot-notation ID (e.g. `MyApp.results.selected`). Required for subcommands. On the **main command** either omit it or set it explicitly to `<NAME>.main` (or bare `main`) — both are equivalent. The main command is also addressable for chaining by `<NAME>.main`, `main`, or the legacy internal `top!`. Its script filename follows the convention `<NAME>.main.<ext>`. |
| `EXECUTION_MODE` | string | How the command runs. Default: `exe_script_file` or `exe_shell_script` if `COMMAND` is set. |
| `ACTIVATION_MODE` | string | What context information the command expects. Default: `act_always`. |

### Minimal command

```json
{
  "NAME": "MyApp",
  "EXECUTION_MODE": "exe_script_file",
  "ACTIVATION_MODE": "act_file_or_folder"
}
```

## Script Naming Convention

Script files live in `Contents/Resources/Scripts/`. The filename maps directly to a `COMMAND_ID`:

| Script file | Handles COMMAND_ID |
|-------------|--------------------|
| `MyApp.main.sh` | the main command (no `COMMAND_ID`, or `COMMAND_ID` = `MyApp.main`) — `MyApp` is the `NAME` |
| `MyApp.results.selected.py` | `MyApp.results.selected` |
| `MyApp.settings.save.sh` | `MyApp.settings.save` |
| `lib.myapp.sh` | *(shared library — sourced by other scripts, not a command handler)* |

The Command Engine resolves the interpreter from the extension: `.sh` / `.bash` / `.zsh` → corresponding shell, `.py` → Python, `.applescript` → AppleScript, `.js` → JSC.

**No shebang line is needed.** The Command Engine supplies the interpreter path automatically.

For Python applets, the embedded Python at `Contents/Library/Python/bin/python3` is used when present — no system Python dependency. When a bundle has embedded Python, the Command Engine exports — for every handler, shell or Python — `PATH` (prepended with the interpreter's `bin/`), `PYTHONPYCACHEPREFIX` (the per-user `/var/folders/.../T/Pyc`, not `$TMPDIR`), and `PYTHONPATH` (prepended with `Contents/Library/Packages/` when it exists). Install third-party modules into `Contents/Library/Packages/` (e.g. `python3 -m pip install --target .../Contents/Library/Packages pkg`) rather than the runtime's own `site-packages`: the `Packages/` dir survives a Python runtime upgrade/rebuild, whereas `Contents/Library/Python/` is replaced wholesale. See `docs/omc_python_scripting_guide.md`.
