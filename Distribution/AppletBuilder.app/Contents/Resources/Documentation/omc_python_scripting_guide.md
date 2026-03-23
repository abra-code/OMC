# OMC Python Scripting Guide

Python scripts are a natural alternative to shell scripts for implementing action handlers in OMC applets. Python applets come with an embedded relocatable Python distribution, so your scripts run without requiring any system-wide Python installation.

## Python Environment

OMC Python applets set up the environment automatically:

- **PATH** includes the embedded Python at `YourApp.app/Contents/Library/Python/bin/`, so `python3` and any installed packages are available without full paths
- **PYTHONPYCACHEPREFIX** is set to `/tmp/Pyc`, keeping `.pyc` files out of the app bundle
- No shebang line is needed — OMC determines the interpreter from the file extension

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

The embedded Python distribution includes `pip`, so you can install additional packages. From Terminal:

```bash
cd YourApp.app/Contents/Library/Python/bin
export PYTHONPYCACHEPREFIX=/tmp/Pyc
./python3 -m pip install package_name
```

For Universal binary compatibility on Apple Silicon Macs, you may want to build packages for both architectures:

```bash
export ARCHFLAGS="-arch x86_64 -arch arm64"
arch -x86_64 ./python3 -m pip install --force-reinstall --no-binary :all: package_name
```

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
