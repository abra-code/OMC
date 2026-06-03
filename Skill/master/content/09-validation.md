---
id: validation
level: 1
flavors: [claude, capable, lite]
---

## Validating Command.plist

After creating or editing a `Command.plist`, validate it before building:

```bash
python3 Skill/scripts/validate_command_plist.py <App.app | Command.plist>
```

Pass the **applet bundle** (`.app` / `.omc`) rather than the bare plist to also run bundle cross-checks (Layer 2): every `exe_script_file` command has a matching `Scripts/<COMMAND_ID>.*`, the `ACTIONUI_WINDOW` JSON / `NIB_DIALOG` nib resources exist, and subcommand IDs (`INIT_SUBCOMMAND_ID`, `END_OK_SUBCOMMAND_ID`, `NEXT_COMMAND_ID`, …) resolve.

Exit codes: `0` clean · `2` warnings only · `1` errors (`[INFO]` lines are advisory and never affect the exit code). Fix every `[ERROR]` before building; investigate each `[WARNING]` (usually a typo, a wrong value type, or a key with no effect in its context); `[INFO]` lines are just FYI.

Common findings:
- **Unknown key** — typo or hallucinated key; check the schema for that dictionary.
- **Wrong value type** — e.g. `DEFAULT_LOCATION` / `DEFAULT_FILE_NAME` must be an *array*; a bare string is silently ignored by the engine.
- **Deprecated `EXECUTION_MODE` alias** — use the modern name (`exe_popen` → `exe_shell_script`).
- **`VERSION` not `2`** — the engine loads nothing unless the root `VERSION` is `2`.
- **"has no effect unless …"** — the key is ignored in this context (e.g. `CUSTOM_*` without `WINDOW_TYPE=custom`; `OUTPUT_WINDOW_SETTINGS` / `PROGRESS` without a popen / `*_with_output_window` mode; `INPUT_MENU` without a popup/combo `INPUT_TYPE`).
- **Dangling subcommand ID / missing dialog resource** — a referenced `COMMAND_ID` (`INIT_SUBCOMMAND_ID`, `NEXT_COMMAND_ID`, …) or a `JSON_NAME` / `NIB_NAME` resource doesn't exist in the bundle. These are errors.
- **"no executable body" (info)** — a command has no inline `COMMAND` and no matching script file. This is a *valid, common* pattern when the command presents a dialog (its subcommands do the work) or chains via `NEXT_COMMAND_ID`, so it is only flagged at `[INFO]` level — and not at all when a dialog/chain is present. If the command was meant to run a script, the info note also catches a typo'd `COMMAND_ID`.

The verifier's key knowledge lives in `Skill/scripts/schemas/` (`Command.json` plus one file per sub-dictionary). Read the relevant schema when unsure about a key name, type, or allowed values. This is the same verifier AppletBuilder runs on **Build** and on the Commands tab **Validate** button.
