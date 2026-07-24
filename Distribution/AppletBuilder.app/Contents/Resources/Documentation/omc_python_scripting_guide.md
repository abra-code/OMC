# OMC Python Scripting Guide

Python scripts are a natural alternative to shell scripts for implementing action handlers in OMC applets. Python applets come with an embedded relocatable Python distribution, so your scripts run without requiring any system-wide Python installation.

## Python Environment

When an applet bundles its own Python at `Contents/Library/Python/`, OMC sets up the environment automatically for **every** command it runs — including `.sh` handlers that shell out to `python3`:

- **PATH** is prepended with the embedded interpreter's `bin/` directory (`YourApp.app/Contents/Library/Python/bin/`), so `python3` and any console scripts installed next to it resolve without full paths.
- **PYTHONPATH** is prepended with `Contents/Library/Packages/` whenever that directory exists, so third-party modules installed there are importable. This is the recommended home for dependencies — see [Installing Python Packages](#installing-python-packages).
- **PYTHONPYCACHEPREFIX** is set to `/tmp/Pyc`, so `.pyc` files are written to a temp location instead of polluting (or being blocked from) the app bundle.
- No shebang line is needed — OMC determines the interpreter from the file extension.

These variables are exported regardless of the handler's language, so a shell handler that invokes the embedded `python3` gets the same module resolution as a `.py` handler.

## Typical Script Structure

A typical Python handler looks something like this:

```python
import os
import subprocess

# Tool paths
omc_support = os.environ.get("OMC_OMC_SUPPORT_PATH", "")
dialog_tool = os.path.join(omc_support, "omc_dialog_control")
next_cmd = os.path.join(omc_support, "omc_next_command")
alert_tool = os.path.join(omc_support, "alert")

# Window context
dlg_guid = os.environ.get("OMC_NIB_DLG_GUID", "")
cmd_guid = os.environ.get("OMC_CURRENT_COMMAND_GUID", "")

# Read inputs
# Do work
# Update UI
# Chain to next command or exit
```

## Shared Setup

If you have multiple Python scripts, you may want to create a shared module (e.g. `lib_myapp.py`) in the Scripts directory. Import it at the top of your handler scripts:

```python
import os
import sys
import subprocess

# Ensure Scripts directory is importable
scripts_dir = os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""), "Contents/Resources/Scripts")
if scripts_dir not in sys.path:
    sys.path.insert(0, scripts_dir)

import lib_myapp
```

This is useful for defining tool paths, control IDs, and reusable helper functions in one place — avoiding repetition across scripts.

## Reading Control Values

OMC exports control values as environment variables. The same patterns from the [Shell Scripting Guide](omc_scripting_guide.md) apply — `os.environ.get()` is the Python equivalent:

```python
# Nib text field (tag 4)
watch_pattern = os.environ.get("OMC_NIB_DIALOG_CONTROL_4_VALUE", "")

# Nib checkbox (tag 2) — "1" for on, "0" for off
recursive = os.environ.get("OMC_NIB_DIALOG_CONTROL_2_VALUE", "0") == "1"

# ActionUI text field (id 101)
name = os.environ.get("OMC_ACTIONUI_VIEW_101_VALUE", "")

# Table column value (selected row)
selected_path = os.environ.get("OMC_NIB_TABLE_1_COLUMN_4_VALUE", "")

# File/folder chooser result
chosen = os.environ.get("OMC_DLG_CHOOSE_OBJECT_PATH", "")

# Input object path
obj_path = os.environ.get("OMC_OBJ_PATH", "")
```

## Updating UI Controls

Use `subprocess.run()` to invoke `omc_dialog_control`. Wrapping common operations in functions can keep your scripts readable:

```python
def set_value(control_id, value):
    subprocess.run([dialog_tool, dlg_guid, str(control_id), value])

def set_enabled(control_id, enabled):
    cmd = "omc_enable" if enabled else "omc_disable"
    subprocess.run([dialog_tool, dlg_guid, str(control_id), cmd])

def set_visible(control_id, visible):
    cmd = "omc_show" if visible else "omc_hide"
    subprocess.run([dialog_tool, dlg_guid, str(control_id), cmd])
```

Then in your scripts:

```python
set_value(STATUS_TEXT_ID, "Processing complete")
set_enabled(SAVE_BTN_ID, False)
set_visible(DETAIL_ROW_ID, True)
```

## Working with Tables

Tables expect tab-separated rows. Building the data in Python and piping it via stdin works well:

```python
# Set up table columns and widths
subprocess.run([dialog_tool, dlg_guid, "1", "omc_table_set_columns",
                "Time", "Type", "Event", "Path"])
subprocess.run([dialog_tool, dlg_guid, "1", "omc_table_set_column_widths",
                "120", "20", "20", "580"])

# Clear existing rows
subprocess.run([dialog_tool, dlg_guid, "1", "omc_table_remove_all_rows"])

# Add rows from data
rows = "\n".join(f"{name}\t{path}" for name, path in items)
subprocess.run([dialog_tool, dlg_guid, "1", "omc_table_add_rows_from_stdin"],
               input=rows, encoding="utf-8")
```

## Handling Table Selection

A common pattern is enabling or disabling action buttons based on whether a row is selected:

```python
has_selection = os.environ.get("OMC_NIB_TABLE_1_COLUMN_1_VALUE", "") != ""
enable_cmd = "omc_enable" if has_selection else "omc_disable"

for button_id in [REVEAL_BTN, INFO_BTN, COPY_BTN]:
    subprocess.run([dialog_tool, dlg_guid, str(button_id), enable_cmd])
```

## Working with Selected Rows

Column 0 is special — it returns all columns combined as a tab-separated string. For multi-row selections, values are newline-separated:

```python
# All columns for selected row(s)
selected_text = os.environ.get("OMC_NIB_TABLE_1_COLUMN_0_VALUE", "")

# A specific column for selected row(s)
file_paths = os.environ.get("OMC_NIB_TABLE_1_COLUMN_4_VALUE", "")

# Iterate over selected rows
for path in file_paths.strip().split('\n'):
    path = path.strip()
    if not path:
        continue
    # process each selected path
```

## Clipboard Operations

```python
text = os.environ.get("OMC_NIB_TABLE_1_COLUMN_0_VALUE", "")
env = os.environ.copy()
env["LANG"] = "en_US.UTF-8"
subprocess.run(["/usr/bin/pbcopy", "-pboard", "general"],
               input=text, encoding="utf-8", env=env)
```

Setting `LANG` to `en_US.UTF-8` helps ensure proper handling of special characters.

## Alert Dialogs

```python
alert_tool = os.path.join(omc_support, "alert")

# Simple alert
subprocess.run([alert_tool, "--level", "caution",
                "--title", "MyApp", "Something went wrong."])

# Alert with custom buttons
subprocess.run([alert_tool, "--level", "critical",
                "--title", "MyApp", "--ok", "OK",
                "File does not exist."])
```

## Chaining Commands

`omc_next_command` schedules another command to run after the current script finishes:

```python
next_cmd = os.path.join(omc_support, "omc_next_command")
cmd_guid = os.environ.get("OMC_CURRENT_COMMAND_GUID", "")

subprocess.run([next_cmd, cmd_guid, "MyApp.next.action"])
```

## Background Processes

For long-running tasks (like file monitoring), use `subprocess.Popen()` instead of `subprocess.run()` so the script can finish while the process continues:

```python
process = subprocess.Popen(args)
print(f"Started background process with PID: {process.pid}")
```

Keep in mind that background processes need explicit cleanup. A handler for `app.will.terminate` can take care of this:

```python
# app.will.terminate.py
import os
import subprocess

python_bin = os.path.join(
    os.environ.get("OMC_APP_BUNDLE_PATH", ""),
    "Contents", "Library", "Python", "bin", ""
)
subprocess.run(["/usr/bin/pkill", "-U", os.environ.get("USER", ""),
                "-f", f"{python_bin}.*"])
```

## File Operations

Python's standard library is well-suited for file operations that would otherwise require multiple shell tools:

```python
import os

# Check existence
if os.path.exists(path):
    ...

# Reveal in Finder
subprocess.run(["/usr/bin/open", "-R", path])

# Get file info
result = subprocess.run(["/usr/bin/stat", "-x", path],
                        capture_output=True, text=True)
print(result.stdout)

# Write to file
with open(save_path, "w", encoding="utf-8") as f:
    f.write(content)
```

## Installing Python Packages

Third-party packages can live in one of two places. **Prefer `Contents/Library/Packages/`**: it is on `PYTHONPATH`, it is kept separate from the standard library, and — unlike the runtime itself — AppletBuilder never overwrites it when it refreshes or upgrades the embedded Python. Modules installed *inside* `Contents/Library/Python/` are wiped whenever that runtime is replaced.

### Recommended: install into Contents/Library/Packages

Install with `pip --target`, pointing at the applet's `Packages/` directory:

```bash
APP="YourApp.app"
PY="$APP/Contents/Library/Python/bin/python3"
export PYTHONPYCACHEPREFIX=/tmp/Pyc
"$PY" -m pip install --target "$APP/Contents/Library/Packages" package_name
```

On an Apple Silicon Mac, build universal wheels so the applet also runs on Intel:

```bash
export ARCHFLAGS="-arch x86_64 -arch arm64"
arch -x86_64 "$PY" -m pip install --target "$APP/Contents/Library/Packages" \
    --force-reinstall --no-binary :all: package_name
```

`import package_name` then works directly, because OMC puts `Packages/` on `PYTHONPATH`. A package that ships a command-line entry point (e.g. `watchmedo` from `watchdog`) installs its launcher into `Packages/bin/`, but you can also invoke it as a module — `"$PY" -m watchdog.watchmedo …` — which avoids depending on the launcher's location.

### Legacy: install into the embedded Python

The embedded distribution includes `pip`, so you *can* install straight into its `site-packages`:

```bash
cd YourApp.app/Contents/Library/Python/bin
export PYTHONPYCACHEPREFIX=/tmp/Pyc
./python3 -m pip install package_name
```

This works, but anything installed here is **destroyed when the runtime is replaced** — for example when AppletBuilder upgrades the applet's Python (the "Update Embedded Python" build option) or reinstalls a missing/broken runtime. Use `Packages/` for anything you want to survive a rebuild.

## Reducing Bundle Size: Thinning the Embedded Python

The embedded Python is a full, universal (arm64 + x86_64) distribution — roughly 60 MB+ — and a typical applet imports only a small slice of the standard library. You can strip the unused parts with `Distribution/Scripts/thin_applet_python.sh`, a front end over the reusable [Python-Embedding](https://github.com/abra-code/Python-Embedding) toolkit. It needs a sibling Python-Embedding checkout next to the OMC repo.

Thinning is **trace-driven and verified**, not a guess: it runs your real workload, records exactly which modules load (transitively, including C extensions and anything reached across a `subprocess`/bin-script boundary), removes the rest, then re-runs the workload to prove nothing needed was deleted (restoring automatically if it was). It works in two phases with a reviewable, committable **plan** in between:

```bash
THIN="OMC/Distribution/Scripts/thin_applet_python.sh"

# 1) PLAN — trace the workload(s) and write a committable plan next to the bundle.
"$THIN" plan MyApp.app \
    --trace "MyApp.app/Contents/Resources/Scripts/MyApp.monitor.start.py" \
    --arch arm64                                  # writes MyApp.thinning-plan.json

# 2) APPLY — perform the removal recorded in the plan, then verify (restores on failure).
"$THIN" apply MyApp.app                            # add --dry-run to preview
```

The wrapper knows the OMC layout, so it automatically thins `Contents/Library/Python`, uses `Contents/Resources/Scripts` as a coverage cross-check, and exports `PYTHONPATH=Contents/Library/Packages` while tracing and verifying — so modules you installed in `Packages/` import the same way they do at runtime. **`Packages/` is never thinned**: only the interpreter's own stdlib/`site-packages` are trimmed.

Key points:

- **Commit the plan.** `MyApp.thinning-plan.json` records module *names* plus options (arch, `include/`, bytecode). Review or hand-tweak `remove.modules`, commit it next to the app, and re-run `apply` any time — for example after AppletBuilder reinstalls a fresh, full Python (which wipes the previous thinning). `apply` resolves names against the *current* interpreter, so it re-thins correctly.
- **Coverage is the rule.** Pass one `--trace` per distinct Python entry point your applet runs (each handler/command, not just the main one). The `--static` cross-check (automatic on the Scripts directory) warns when a handler imports something no trace exercised — heed it, or that module gets removed.
- **`--trace` is the command after `python3 -X importtime`** — pass the script/module + args, with no leading `python3`. For a module entry point use `--trace "-m package.module …"`.

See the Python-Embedding README for the underlying `analyze_python_deps.py` / `thin_with_plan.sh` tools and the full methodology.

## Naming Conventions

Script files follow the same pattern as shell scripts — `AppName.area.action.py`, matching the `COMMAND_ID` in Command.plist:

| File | COMMAND_ID |
|------|-----------|
| `MyApp.monitor.init.py` | `MyApp.monitor.init` |
| `MyApp.monitor.start.py` | `MyApp.monitor.start` |
| `MyApp.export.events.py` | `MyApp.export.events` |
| `lib_myapp.py` | *(shared module, not a command)* |

OMC determines the interpreter from the file extension, so a command can be implemented as either `.sh` or `.py` — just provide one file with the matching name.

## Debugging

- **Print to stdout**: use `print()` statements. Hold the Control key when triggering a command to see output in a window, or temporarily set `EXECUTION_MODE=exe_script_file_with_output_window`
- **Dump environment**: `for name in sorted(os.environ): print(f"{name} = {os.environ[name]}")`
- **Log to file**: `with open("/tmp/myapp_debug.log", "a") as f: f.write("checkpoint\n")`

## Related Documentation

- [Shell Scripting Guide](omc_scripting_guide.md) — Shell-specific patterns for OMC applets
- [OMC Command Reference](omc_command_reference.md) — Command.plist format and all configuration keys
- [OMC Runtime Context Reference](omc_runtime_context_reference.md) — All environment variables and special words
- [omc_dialog_control](omc_dialog_control--help.md) — Full command reference for UI manipulation
- [omc_next_command](omc_next_command--help.md) — Command chaining
- [alert](alert--help.md) — Alert dialog tool
