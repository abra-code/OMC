# Building Command Workshop Applets

## Overview

Command Workshop (formerly OMC) is a low-code macOS app development engine that lets you create standalone applets with custom UI and shell/Python scripting. This guide covers the fundamentals of building a Command Workshop applet from scratch.

### Key Concepts

- **Applet**: A standalone mini-app (`.app` bundle) built on Abracode.framework
- **Command**: An action handler defined in `Command.plist` that executes a script
- **Command Group**: Multiple commands sharing the same `NAME` with unique `COMMAND_ID`s
- **ActionUI window**: a JSON document (in `Base.lproj`) describing a window's views
- **Subcommand**: A command triggered by UI events (button click, dialog init, table selection)

---

## Prerequisites

1. **AppletBuilder**: Download version 5.0+ from https://github.com/abra-code/OMC/releases — `AppletBuilder.app` is the integrated development studio for building Command Workshop applets
2. **Xcode**: Required for compiling/installing `.icon` documents into apps
3. **Git**: For version control (recommended)

> **For AI Agents**: To check the latest Command Workshop release:
> ```bash
> # Fetch latest releases from GitHub API
> curl -s "https://api.github.com/repos/abra-code/OMC/releases?per_page=3"
> # Filter for first non-draft, non-prerelease release
> # Download URL: https://github.com/abra-code/OMC/releases/download/vX.X.X/OMC_X.X.X.zip
> ```
> Compare the latest version to local Command Workshop version if given access to, e.g.:`~/Downloads/OMC_X.X.X/`

---

## Step 1: Create the Applet

### AppletBuilder.app

`AppletBuilder.app` (included in the 5.0+ release) is the integrated development studio for Command Workshop applets. It handles creating new applets from templates, editing an existing applet's commands and scripts, managing services, and building (updating the runtime + codesigning).

**To create a new applet**: Launch `AppletBuilder.app` — the New Applet dialog opens automatically. Fill in the name, bundle ID, choose a template, optionally enable embedded Python, pick an icon, and select a destination folder.

**To open an existing applet**: Drop the `.app` onto `AppletBuilder.app` (or onto its Dock icon) to open the project editor.

### Templates

| Template | Description |
|----------|-------------|
| `Empty` | Bare-bones applet — only Command.plist and a main script |
| `ActionUI Window` | Pre-wired with an ActionUI JSON window (requires macOS 14.6+) |
| `ActionUI Web` | ActionUI window with an embedded WebView for web-based UI |

**Python**: Check "Include Python" in the New Applet dialog to embed a Python 3 runtime — there is no separate Python template.

> **For AI Agents**: When assisting with applet development:
> - **New applet**: Ask the user to create it via `AppletBuilder.app` (GUI-only workflow). You then edit the generated `Command.plist`, scripts, and UI files.
> - **Existing applet**: Edit `Command.plist`, `Scripts/`, and ActionUI JSON files in place.
> - **After editing**: Ask the user to click Build in AppletBuilder's Build & Run pane — it updates the runtime and re-signs. Do NOT manually copy runtime binaries or Abracode.framework.

### Codesign for Local Execution

Codesigning is handled by the **Build & Run** pane inside AppletBuilder. For scripted or CI workflows, `codesign_applet.sh` is provided in the distribution's `Scripts/` folder:

```bash
# OMC_5.0/Scripts/codesign_applet.sh
./Scripts/codesign_applet.sh "MyApp/MyApp.app"
```

### Initial Structure

```
MyApp.app/
├── Contents/
│   ├── Frameworks/Abracode.framework  (OMC engine)
│   ├── MacOS/MyApp                    (app binary)
│   ├── Resources/
│   │   ├── Command.plist              (command definitions)
│   │   ├── Scripts/                   (action handler scripts)
│   │   └── Base.lproj/
│   │       └── *.json                 (ActionUI window definitions)
│   └── _CodeSignature/                (codesigning)
└── Library/                           (Python runtime, if Python was enabled)
```

---

## Step 2: Define Commands in Command.plist

### Root Structure

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN">
<plist version="1.0">
<dict>
    <key>COMMAND_LIST</key>
    <array>
        <!-- Commands go here -->
    </array>
    <key>VERSION</key>
    <integer>2</integer>
</dict>
</plist>
```

### Command Identity

```xml
<dict>
    <key>NAME</key>
    <string>MyApp</string>              <!-- Menu label -->
    <key>COMMAND_ID</key>
    <string>myapp.mycommand</string>   <!-- Unique identifier for subcommands -->
</dict>
```

**Main Command**: The first command in `COMMAND_LIST` is the main command. It either has no `COMMAND_ID` or an explicit `COMMAND_ID` of `<NAME>.main` (or bare `main`) — both forms behave identically. It is executed when files/folders are dropped on the applet (or on launch). Subcommands have unique `COMMAND_ID` values. The main command can be chained to by `<NAME>.main`, `main`, or `top!` (see `NEXT_COMMAND_ID` / `omc_next_command`).

> **For AI Agents**: Understanding command structure is critical:
> - The **main command** (first in list, no `COMMAND_ID` or `COMMAND_ID` = `<NAME>.main`) handles file/folder drops on the app
> - **Subcommands** have `COMMAND_ID` and are triggered by UI events (buttons, table selection)
> - Multiple commands with same `NAME` but different `COMMAND_ID` form a **command group**

### Execution Modes

| Mode | Description |
|------|-------------|
| `exe_script_file` | Executes script file from `Scripts/` directory |
| `exe_shell_script` | Executes inline shell command |
| `exe_script_file_with_output_window` | Script + visible output pane |
| `exe_system` | Synchronous, no env vars (use `__FOO__`) |
| `exe_applescript` | AppleScript execution |

### Activation Modes

| Mode | Description |
|------|-------------|
| `act_always` | Always available |
| `act_file` | File(s) selected/dropped |
| `act_folder` | Folder(s) |
| `act_file_or_folder` | Either |

### Example: Main Launch Command

```xml
<dict>
    <key>NAME</key>
    <string>MyApp</string>          <!-- No COMMAND_ID (or COMMAND_ID = MyApp.main) = main command -->
    <key>ACTIVATION_MODE</key>
    <string>act_folder</string>
    <key>EXECUTION_MODE</key>
    <string>exe_script_file</string>
</dict>
```

Scripts: `Scripts/MyApp.main.sh`

---

## Step 3: Create Action Handler Scripts

Scripts for `exe_script_file` execution mode live in `MyApp.app/Contents/Resources/Scripts/` and are named based on command type:

| Command Type | Script Location | Naming Convention |
|--------------|----------------|------------------|
| Main command | `Scripts/` | `<NAME>.main.<ext>` (e.g., `MyApp.main.sh`) |
| Subcommand | `Scripts/` | `<NAME>.<COMMAND_ID>.<ext>` (e.g., `MyApp.mycommand.sh`) |

| Extension | Interpreter |
|-----------|-------------|
| `.sh` | /bin/sh |
| `.py` | /usr/bin/python3 |
| `.pl` | /usr/bin/perl |
| `.applescript`, `.scpt` | /usr/bin/osascript |
| `.zsh` | /bin/zsh |
| `.bash` | /bin/bash |
| `.csh` | /bin/csh |
| `.tcsh` | /bin/tcsh |
| `.dash` | /bin/dash |
| `.rb` | /usr/bin/ruby |
| `.js`, `.mjs` | JavaScriptCore (macOS 11+)

### Environment Variables Available

| Variable | Description |
|----------|-------------|
| `$OMC_OBJ_PATH` | Selected file/folder path |
| `$OMC_OBJ_NAME` | Base name |
| `$OMC_APP_BUNDLE_PATH` | Applet bundle path |
| `$OMC_APP_PROCESS_ID` | PID of the Command Engine host process (the applet itself here, not the frontmost app) |
| `$OMC_OMC_SUPPORT_PATH` | Command Engine support tools |
| `$OMC_ACTIONUI_WINDOW_UUID` | Window instance ID (`$OMC_NIB_DLG_GUID` is the same value under its older name) |
| `$OMC_CURRENT_COMMAND_GUID` | Command execution ID |

### Example Script (Scripts/MyApp.main.sh)

```bash
#!/bin/bash
echo "Processing: ${OMC_OBJ_PATH}"

# Your code here
ls -la "${OMC_OBJ_PATH}"
```

### Forcing Environment Variables

For `exe_script_file`, environment variables that are not auto-exported must be explicitly declared using `ENVIRONMENT_VARIABLES`:

```xml
<dict>
    <key>COMMAND_ID</key>
    <string>my.action</string>
    <key>EXECUTION_MODE</key>
    <string>exe_script_file</string>
    <key>ENVIRONMENT_VARIABLES</key>
    <dict>
        <key>OMC_DLG_INPUT_TEXT</key>
        <string></string>
    </dict>
</dict>
```

> **For AI Agents**: Use `ENVIRONMENT_VARIABLES` dictionary for forcing env var exports. See [Runtime Context Reference](omc_runtime_context_reference.md) for details.

---

## Step 4: Create Custom UI with ActionUI JSON Windows

Windows are defined with **ActionUI**, a declarative JSON format for SwiftUI-based views. Requires macOS 14.6+.

> Nib (Interface Builder) windows are no longer supported since 6.0. To convert an older applet, see [nib_to_actionui_migration.md](nib_to_actionui_migration.md).

### Connect JSON to Command

```xml
<dict>
    <key>NAME</key>
    <string>MyApp</string>
    <key>COMMAND_ID</key>
    <string>myapp.show.window</string>
    <key>EXECUTION_MODE</key>
    <string>exe_script_file</string>
    <key>ACTIONUI_WINDOW</key>
    <dict>
        <key>JSON_NAME</key>
        <string>MyDialog</string>
        <key>IS_BLOCKING</key>
        <false/>
        <key>INIT_SUBCOMMAND_ID</key>
        <string>myapp.window.init</string>
        <key>END_CANCEL_SUBCOMMAND_ID</key>
        <string>myapp.window.close</string>
        <key>WINDOW_TITLE</key>
        <string>My Dialog</string>
        <key>WINDOW_TYPE</key>
        <string>floating</string>
    </dict>
</dict>
```

### ACTIONUI_WINDOW Keys

| Key | Description |
|-----|-------------|
| `JSON_NAME` | JSON filename without extension (in Resources) |
| `IS_BLOCKING` | `true`=modal, `false`=non-modal |
| `INIT_SUBCOMMAND_ID` | Command on window open |
| `END_OK_SUBCOMMAND_ID` | Command on OK button |
| `END_CANCEL_SUBCOMMAND_ID` | Command on Cancel/close |
| `WINDOW_TITLE` | Static window title (overrides default) |
| `WINDOW_TYPE` | `floating` (utility panel) or `global_floating` (always-on-top utility panel) |

### Communicating with ActionUI

```bash
dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
window_uuid="$OMC_ACTIONUI_WINDOW_UUID"

# Set a value on view with id 1
"${dialog_tool}" "${window_uuid}" "1" "Hello"

# Set a property
"${dialog_tool}" "${window_uuid}" "1" omc_set_property "disabled" true

# Set window title dynamically
"${dialog_tool}" "${window_uuid}" omc_window "New Title"

# Close the window
"${dialog_tool}" "${window_uuid}" omc_window omc_terminate_cancel
```

> See [Command Reference — ACTIONUI_WINDOW](omc_command_reference.md#61-actionui_window--actionui-json-dialogs-omc-50-or-higher) for full details.

---

## Step 5: Communicate with UI

### omc_dialog_control Tool

Located at `$OMC_OMC_SUPPORT_PATH/omc_dialog_control`

```bash
dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
dlg_guid="$OMC_ACTIONUI_WINDOW_UUID"
```

### Common Operations

```bash
# Set table columns
"${dialog_tool}" "${dlg_guid}" "1" "omc_table_set_columns" "Col1" "Col2" "Col3"

# Set column widths
"${dialog_tool}" "${dlg_guid}" "1" "omc_table_set_column_widths" "100" "100" "200"

# Add rows (tab-separated)
echo -e "row1\tdata1\tdata2" | "${dialog_tool}" "${dlg_guid}" "1" "omc_table_add_rows_from_stdin"

# Clear table
"${dialog_tool}" "${dlg_guid}" "1" "omc_table_remove_all_rows"

# Enable/disable control
"${dialog_tool}" "${dlg_guid}" "5" "omc_enable"
"${dialog_tool}" "${dlg_guid}" "5" "omc_disable"

# Set window title
"${dialog_tool}" "${dlg_guid}" "omc_window" "My Window Title"

# Close dialog
"${dialog_tool}" "${dlg_guid}" "omc_window" "omc_terminate_ok"
```

### Reading Control Values

Values are available as environment variables:

```bash
# TextField with id 4
PATTERN="${OMC_ACTIONUI_VIEW_4_VALUE}"

# Toggle with id 2
IS_RECURSIVE="${OMC_ACTIONUI_VIEW_2_VALUE}"

# Table with id 1: column 4 of the selected row
FILE_PATH="${OMC_ACTIONUI_TABLE_1_COLUMN_4_VALUE}"

# All rows, column 0 (special: all columns combined)
ALL_DATA="${OMC_ACTIONUI_TABLE_1_COLUMN_0_ALL_ROWS}"
```

### Table Column Indexing

- Columns are **1-based** (1, 2, 3, ...)
- Column **0** is special: all columns combined into single tab-separated string

---

## Step 6: Dialogs and User Input

### Save As Dialog

```xml
<dict>
    <key>NAME</key>
    <string>Export</string>
    <key>COMMAND_ID</key>
    <string>myapp.export</string>
    <key>EXECUTION_MODE</key>
    <string>exe_script_file</string>
    <key>SAVE_AS_DIALOG</key>
    <dict>
        <key>MESSAGE</key>
        <string>Save As...</string>
        <key>DEFAULT_FILE_NAME</key>
        <array>
            <string>export_</string>
            <string>__OBJ_NAME__</string>
            <string>.txt</string>
        </array>
        <key>DEFAULT_LOCATION</key>
        <array>
            <string>~</string>
        </array>
    </dict>
</dict>
```

Result: `$OMC_DLG_SAVE_AS_PATH` contains selected path.

### Input Dialog

```xml
<dict>
    <key>INPUT_DIALOG</key>
    <dict>
        <key>INPUT_TYPE</key>
        <string>text</string>
        <key>TITLE</key>
        <string>Enter Name</string>
        <key>MESSAGE</key>
        <string>Please enter a name:</string>
        <key>DEFAULT_VALUE</key>
        <string>__OBJ_NAME__</string>
    </dict>
</dict>
```

Result: `$OMC_DLG_INPUT_TEXT` contains user input.

---

## Step 7: Chaining Commands

### Static Chaining

```xml
<dict>
    <key>NEXT_COMMAND_ID</key>
    <string>myapp.step2</string>
</dict>
```

### Dynamic Chaining (from script)

```bash
next_command_tool="$OMC_OMC_SUPPORT_PATH/omc_next_command"
"${next_command_tool}" "$OMC_CURRENT_COMMAND_GUID" "MyApp.step2"
```

---

## Step 7b: Opening the Applet with a URL

Applets created by AppletBuilder declare a URL scheme derived from the applet name (`CFBundleURLSchemes` in `Info.plist`). macOS starts the applet, if needed, and hands it any URL on that scheme.

### Running a Command (`exe`)

```
myapp://exe?commandID=myapp.open.item&text=some%20text
myapp://exe?commandID=myapp.import&file=/Users/me/a.txt&file=/Users/me/b.txt
```

A command can be run this way only when it opts in:

```xml
<dict>
    <key>NAME</key>
    <string>MyApp</string>
    <key>COMMAND_ID</key>
    <string>myapp.open.item</string>
    <key>URL_INVOCABLE</key>
    <true/>
</dict>
```

`text` arrives as `$OMC_OBJ_TEXT`, `file` (repeatable, absolute paths of existing items only) as `$OMC_OBJ_PATH`. Lifecycle commands (`app.will.terminate` and the others) and dialog event handlers are never run by a URL. The full rules are in the [Command Reference](omc_command_reference.md), section 3.

### Handling Any Other URL (`omc.app.handle-url`)

A URL whose host is not `exe`, for example `myapp://item/42`, runs the command with id `omc.app.handle-url`, if the applet defines one. The whole URL is in `$OMC_OBJ_TEXT`. This is the better choice when the applet wants its own URL layout: the script decides what each URL means and ignores the rest.

```bash
#!/bin/bash
# Scripts/omc.app.handle-url.sh
case "$OMC_OBJ_TEXT" in
    myapp://item/*) item_id="${OMC_OBJ_TEXT#myapp://item/}" ;;
    *) exit 0 ;;
esac
```

### Link Content Is Untrusted

Any web page, email, document or application can send a URL, and the sender chooses the command id, the text and the paths.

- Opt in (`URL_INVOCABLE`) only commands meant as entry points, and never one that deletes, overwrites, installs or sends something without asking the user.
- Validate `$OMC_OBJ_TEXT` and `$OMC_OBJ_PATH` before use. Quote them, and never `eval` them.
- `$OMC_TRIGGER_URL` holds the URL for a run started by one, and is absent otherwise. A command shared with a menu or a button can use it to be stricter for links.
- A refused URL runs nothing. Look for `OMC: URL refused` in Console to see why a link did not work.
- An applet that needs no links does not need a URL scheme: remove `CFBundleURLTypes` from its `Info.plist`.

---

## Step 8: Long-Running Processes

Background processes started by scripts can outlive the parent applet. Handle cleanup properly.

### App Lifetime Events

The Command Engine dispatches commands for app lifecycle events when a matching `COMMAND_ID` is defined in `COMMAND_LIST`:

| `COMMAND_ID` | When it fires |
|--------------|---------------|
| `app.will.launch` | Before the app finishes launching |
| `app.did.launch` | After the app finishes launching |
| `app.did.activate` | App came to foreground (e.g., user switched back to it) |
| `app.did.deactivate` | App went to background (e.g., user switched to another app) |
| `app.will.terminate` | App is about to quit |

`app.did.activate` is useful for detecting external changes made while the app was in the background. For per-window activation, use `WINDOW_DID_ACTIVATE_SUBCOMMAND_ID` in `ACTIONUI_WINDOW` (see [Command Reference](omc_command_reference.md)).

### Termination Handler

Special command with `COMMAND_ID=app.will.terminate` runs when app quits:

```xml
<dict>
    <key>NAME</key>
    <string>MyApp</string>
    <key>COMMAND_ID</key>
    <string>app.will.terminate</string>
    <key>EXECUTION_MODE</key>
    <string>exe_script_file</string>
</dict>
```

Script `Scripts/app.will.terminate.sh`:

```bash
#!/bin/bash
# Kill processes started by this app
PROCESS_PATH="${OMC_APP_BUNDLE_PATH}/Contents/Library/Python/bin/"
/usr/bin/pkill -U "${USER}" -f "${PROCESS_PATH}.*"
```

### Tracking Process PIDs

For complex scenarios, write PIDs to preferences:

```bash
# Store PID
echo "${PROCESS_PID}" > "${HOME}/Library/Preferences/com.example.myapp.pids"

# On termination, read and kill
while read -r pid; do
    kill "${pid}" 2>/dev/null
done < "${HOME}/Library/Preferences/com.example.myapp.pids"
```

See [AIChatApp](https://github.com/abra-code/AIChatApp) for full example.

### Best Practices

1. Always register `app.will.terminate` handler
2. Use `-U ${USER}` to avoid killing other users' processes
3. Consider storing PIDs for multi-window scenarios
4. Clean up on window close if processes are window-specific

---

## Step 9: Output Windows

For commands that show results:

```xml
<dict>
    <key>EXECUTION_MODE</key>
    <string>exe_script_file_with_output_window</string>
    <key>OUTPUT_WINDOW_SETTINGS</key>
    <dict>
        <key>WINDOW_TITLE</key>
        <string>Results</string>
        <key>WINDOW_TYPE</key>
        <string>floating</string>
        <key>WINDOW_WIDTH</key>
        <integer>600</integer>
        <key>WINDOW_HEIGHT</key>
        <integer>400</integer>
        <key>TEXT_FONT</key>
        <string>Monaco</string>
        <key>TEXT_SIZE</key>
        <integer>11</integer>
    </dict>
</dict>
```

---

## File Structure Summary

```
MyApp.app/
└── Contents/
    ├── Frameworks/
    │   └── Abracode.framework/
    ├── MacOS/
    │   └── MyApp
    ├── Resources/
    │   ├── Command.plist           <- Command definitions
    │   ├── Scripts/
    │   │   ├── MyApp.main.sh       <- Main launch script
    │   │   ├── MyApp.window.init   <- Window init handler
    │   │   ├── MyApp.window.close  <- Window close handler
    │   │   └── MyApp.app.will.terminate  <- App quit handler
    │   ├── Base.lproj/
    │   │   └── MyDialog.json        <- Window definition
    │   └── *.lproj/                 <- Localizations
    └── _CodeSignature/
```

---

## Debugging Tips

1. **View environment variables**:
   ```bash
   env | grep "OMC" | sort
   ```

2. **Enable output window** temporarily:
   Change `exe_script_file` to `exe_script_file_with_output_window`

3. **Control-click to show output**:
   Hold Control when starting command to see stdout (stdout only: add `exec 2>&1` to the script to see its errors there too)

4. **Check a window's JSON**: AppletBuilder's UI Files pane validates and previews it; `appletbuilder validate` does the same from Terminal

---

## Additional Resources

### Command Workshop Documentation
- [Command Reference](omc_command_reference.md)
- [Runtime Context Reference](omc_runtime_context_reference.md)
- [Nib to ActionUI Migration](nib_to_actionui_migration.md) (for applets made before 6.0)

### Example Applets
- [WatchdogApp](https://github.com/abra-code/WatchdogApp) - File system monitoring in an ActionUI window with Python handlers (version 5.3). Its original NIB-era step-by-step guide, `building_watchdog.md`, is kept unmaintained under `Archive/`
- [FindApp](https://github.com/abra-code/FindApp)
- [DeltaApp](https://github.com/abra-code/DeltaApp)
- [XattrApp](https://github.com/abra-code/XattrApp)
- [AIChatApp](https://github.com/abra-code/AIChatApp)

### Tools Reference
- [omc_dialog_control](omc_dialog_control--help.md) — Manipulate dialog controls
- [omc_next_command](omc_next_command--help.md) — Chain to another command
- [alert](alert--help.md) — Show alert dialogs
- [pasteboard](pasteboard--help.md) — Copy to clipboard
- [notify](notify--help.md) — Send notifications
- [plister](plister--help.md) — Read/write plist files
- [filt](filt--help.md) — Text filtering utility
- [b64](b64--help.md) — Base64 encoding/decoding
- [loco](loco--help.md) — Localization string extraction

---

## Example: Complete Mini Applet

### Command.plist
```xml
<dict>
    <key>NAME</key>
    <string>FileInfo</string>
    <key>ACTIVATION_MODE</key>
    <string>act_file_or_folder</string>
    <key>EXECUTION_MODE</key>
    <string>exe_script_file_with_output_window</string>
    <key>OUTPUT_WINDOW_SETTINGS</key>
    <dict>
        <key>TEXT_FONT</key>
        <string>Monaco</string>
        <key>TEXT_SIZE</key>
        <integer>11</integer>
    </dict>
</dict>
```

### Scripts/FileInfo.main.sh
```bash
#!/bin/bash
/usr/bin/stat -x "${OMC_OBJ_PATH}"
```

> **Note**: The main command (first in list, with no `COMMAND_ID` or an explicit `COMMAND_ID` of `FileInfo.main`) is executed when files/folders are dropped on the applet. The script `FileInfo.main.sh` is the handler for this main command.

Drop a file/folder on the app → output window shows file information.

> **For AI Agents**: When creating example applets:
> - Use the FileInfo example as a template for minimal applets
> - The script MUST have a `.sh` (or appropriate) extension
> - The script name must match: `<NAME>.main.<ext>` where `<NAME>` is the command's NAME field

