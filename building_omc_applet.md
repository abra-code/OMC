# Building OMC Applets

## Overview

OMC (OnMyCommand) is a low-code macOS app development engine that lets you create standalone applets with custom UI and shell/Python scripting. This guide covers the fundamentals of building an OMC applet from scratch.

### Key Concepts

- **Applet**: A standalone mini-app (`.app` bundle) built on Abracode.framework
- **Command**: An action handler defined in `Command.plist` that executes a script
- **Command Group**: Multiple commands sharing the same `NAME` with unique `COMMAND_ID`s
- **NIB**: Interface Builder file containing window/layout definitions
- **Subcommand**: A command triggered by UI events (button click, dialog init, table selection)

---

## Prerequisites

1. **OMC Release**: Download from https://github.com/abra-code/OMC/releases
2. **Xcode**: Required for building applets and editing nibs
3. **Git**: For version control (recommended)

> **For AI Agents**: To check the latest OMC release:
> ```bash
> # Fetch latest releases from GitHub API
> curl -s "https://api.github.com/repos/abra-code/OMC/releases?per_page=3"
> # Filter for first non-draft, non-prerelease release
> # Download URL: https://github.com/abra-code/OMC/releases/download/vX.X.X/OMC_X.X.X.zip
> ```
> Compare the latest version to local OMC version if given access to, e.g.:`~/Downloads/OMC_X.X.X/`

---

## Step 1: Create the Applet

### Choose a Template

| Template | Description | Use When |
|----------|-------------|----------|
| `OMCApplet.app` | Base template, minimal size | Shell scripts only, no Python needed |
| `OMCPythonApplet.app` | Includes embedded Python 3 | Need Python modules (e.g., watchdog) |

> **For AI Agents**: Always use the provided scripts to create applets:
> - `build_applet.sh` - Creates applet from template, handles renaming, Info.plist updates
> - `codesign_applet.sh` - Signs the applet after modifications
>
> Do NOT manually copy files from the template - let the scripts handle it.

### Build the Applet

```bash
cd ~/Downloads/OMC_4.4.1/
./Scripts/build_applet.sh \
    --omc-applet="Products/Applications/OMCApplet.app" \
    --icon="MyApp/Icon/MyIcon.icon" \
    --bundle-id=com.example.myapp \
    --creator=MApp \
    MyApp/MyApp.app
```

### Codesign for Local Execution

```bash
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
│   │       └── *.nib                  (window definitions)
│   └── _CodeSignature/                (codesigning)
└── Library/                           (Python if OMCPythonApplet)
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

**Main Command**: The first command in `COMMAND_LIST` (without `COMMAND_ID`) is the main command. It is executed when files/folders are dropped on the applet. Subcommands have unique `COMMAND_ID` values.

> **For AI Agents**: Understanding command structure is critical:
> - The **main command** (first in list, no `COMMAND_ID`) handles file/folder drops on the app
> - **Subcommands** have `COMMAND_ID` and are triggered by UI events (buttons, table selection)
> - Multiple commands with same `NAME` but different `COMMAND_ID` form a **command group**
> - The script naming convention is: `<NAME>.main.<ext>` for main, `<NAME>.<COMMAND_ID>.<ext>` for subcommands

### Main vs Subcommand Scripts

| Command Type | Script Location | Naming Convention |
|--------------|----------------|------------------|
| Main command | `Scripts/` | `<NAME>.main.<ext>` (e.g., `MyApp.main.sh`) |
| Subcommand | `Scripts/` | `<NAME>.<COMMAND_ID>.<ext>` (e.g., `MyApp.mycommand.sh`) |

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
    <string>MyApp</string>          <!-- No COMMAND_ID = main command -->
    <key>ACTIVATION_MODE</key>
    <string>act_folder</string>
    <key>EXECUTION_MODE</key>
    <string>exe_script_file</string>
</dict>
```

Scripts: `Scripts/MyApp.main.sh`

---

## Step 3: Create Action Handler Scripts

Scripts live in `MyApp.app/Contents/Resources/Scripts/` and are named based on command type:

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
| `$OMC_OMC_SUPPORT_PATH` | OMC support tools |
| `$OMC_NIB_DLG_GUID` | Dialog instance ID |
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

## Step 4: Create Custom UI with NIBs

### NIB Formats

| Format | Editable | Loadable | Notes |
|--------|----------|----------|-------|
| `.xib` | Yes | No | Xcode format, needs compilation |
| `.nib` (flat) | No | Yes | Compiled by Xcode |
| `.nib` (bundled) | Yes | Yes | Contains `designable.nib` + `keyedobjects.nib` |

**Recommendation**: Use bundled `.nib` format for in-place editing.

> **For AI Agents**: Prefer editing existing NIB files rather than creating new ones. Use [WatchdogMonitor.nib](`WatchdogApp/Watchdog.app/Contents/Resources/Base.lproj/WatchdogMonitor.nib/designable.nib`) as a reference. Key patterns:
>
> **Adding OMC properties** via `userDefinedRuntimeAttributes`:
> ```xml
> <userDefinedRuntimeAttributes>
>     <userDefinedRuntimeAttribute type="string" keyPath="commandID" value="watchdog.ok"/>
>     <userDefinedRuntimeAttribute type="string" keyPath="selectionCommandID" value="watchdog.selection"/>
> </userDefinedRuntimeAttributes>
> ```
>
> **Tags**: Most controls use direct `tag="123"` attribute. Only add `tag` to `userDefinedRuntimeAttributes` for OMC controls without native tag support (OMCBox, OMCIKImageView, OMCPDFView, OMCProgressIndicator, OMCTextView, OMCView, OMCWebView). See [omc_controls_user_defined_runtime_attributes.md](omc_controls_user_defined_runtime_attributes.md) for full property list.
>
> **Special chars**: base64-encoded in `base64-UTF8="YES"` (e.g., `\n` = `Cg==`, `\t` = `JQ==`)

### Create Window

1. Open Xcode
2. File → New → File → macOS → User Interface → Window
3. Save as `MyDialog.xib`

### Compile to Bundled NIB

```bash
/usr/bin/xcrun ibtool --compile MyDialog.nib --flatten NO MyDialog.xib
```

Result:
```
MyDialog.nib/
    designable.nib    <- Editable XML
    keyedobjects.nib   <- Loadable binary
```

### Place in Applet

```
MyApp.app/Contents/Resources/Base.lproj/MyDialog.nib
```

### Connect NIB to Command

```xml
<dict>
    <key>NAME</key>
    <string>MyApp</string>
    <key>COMMAND_ID</key>
    <string>myapp.show.window</string>
    <key>EXECUTION_MODE</key>
    <string>exe_script_file</string>
    <key>NIB_DIALOG</key>
    <dict>
        <key>NIB_NAME</key>
        <string>MyDialog</string>
        <key>IS_BLOCKING</key>
        <false/>                      <!-- Non-modal -->
        <key>INIT_SUBCOMMAND_ID</key>
        <string>myapp.window.init</string>
        <key>END_CANCEL_SUBCOMMAND_ID</key>
        <string>myapp.window.close</string>
    </dict>
</dict>
```

### NIB Dialog Keys

| Key | Description |
|-----|-------------|
| `NIB_NAME` | NIB filename without extension |
| `IS_BLOCKING` | `true`=modal, `false`=non-modal |
| `INIT_SUBCOMMAND_ID` | Command on window open |
| `END_OK_SUBCOMMAND_ID` | Command on OK button |
| `END_CANCEL_SUBCOMMAND_ID` | Command on Cancel/close |

---

## Step 5: Add Controls to NIB

### OMC-Specific Controls

| Control | Class in Xcode | Purpose |
|---------|----------------|---------|
| Button | OMCButton | Triggers command on click |
| TextField | OMCTextField | Text input |
| TableView | OMCTableView | Data display |
| PopUpButton | OMCPopUpButton | Dropdown menu |
| Slider | OMCSlider | Value selection |
| SearchField | OMCSearchField | Search input |
| ProgressIndicator | OMCProgressIndicator | Progress display |

### Control Properties (User Defined Runtime Attributes)

#### OMCButton
| Property | Type | Description |
|----------|------|-------------|
| `commandID` | String | Command to trigger on click |
| `mappedOnValue` | String | Value when checked (checkbox) |
| `mappedOffValue` | String | Value when unchecked |
| `acceptFileDrop` | Boolean | Accept file drops |
| `acceptTextDrop` | Boolean | Accept text drops |

#### OMCTableView
| Property | Type | Description |
|----------|------|-------------|
| `selectionCommandID` | String | Command on selection change |
| `doubleClickCommandID` | String | Command on double-click |
| `combinedSelectionSeparator` | String | Separator for multi-select |
| `multipleColumnSeparator` | String | Column separator |

#### OMCTextField
| Property | Type | Description |
|----------|------|-------------|
| `commandID` | String | Command on return/confirm |
| `escapingMode` | String | Text escaping mode |

### Control Tags

- **Tag = 0**: Control not findable by OMC (use for buttons that only trigger commands)
- **Tag > 0**: Control findable via `OMC_NIB_DIALOG_CONTROL_<TAG>_VALUE`

Example: TextField with tag=4 → value available as `$OMC_NIB_DIALOG_CONTROL_4_VALUE`

### Configure Table View

1. Add NSTableView inside NSScrollView
2. Set `customClass="OMCTableView"`
3. Add columns with header cells
4. Set `tag="1"` directly as attribute on the table view

> **Tip**: Copy from WatchdogMonitor.nib and modify for your needs.

---

## Step 6: Communicate with UI

### omc_dialog_control Tool

Located at `$OMC_OMC_SUPPORT_PATH/omc_dialog_control`

```bash
dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
dlg_guid="$OMC_NIB_DLG_GUID"
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

# Close dialog
"${dialog_tool}" "${dlg_guid}" "omc_window" "omc_terminate_ok"
```

### Reading Control Values

Values are available as environment variables:

```bash
# TextField with tag 4
PATTERN="${OMC_NIB_DIALOG_CONTROL_4_VALUE}"

# Checkbox (1=on, 0=off)
IS_RECURSIVE="${OMC_NIB_DIALOG_CONTROL_2_VALUE}"

# Table column 4 of selected row
FILE_PATH="${OMC_NIB_TABLE_1_COLUMN_4_VALUE}"

# All rows, column 0 (special: all columns combined)
ALL_DATA="${OMC_NIB_TABLE_1_COLUMN_0_ALL_ROWS}"
```

### Table Column Indexing

- Columns are **1-based** (1, 2, 3, ...)
- Column **0** is special: all columns combined into single tab-separated string

---

## Step 7: Dialogs and User Input

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

## Step 8: Chaining Commands

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

## Step 9: Long-Running Processes

Background processes started by scripts can outlive the parent applet. Handle cleanup properly.

### Termination Handler

Special command with `NAME=app.will.terminate` runs when app quits:

```xml
<dict>
    <key>NAME</key>
    <string>app.will.terminate</string>
    <key>EXECUTION_MODE</key>
    <string>exe_script_file</string>
</dict>
```

Script `Scripts/MyApp.app.will.terminate.sh`:

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

## Step 10: Output Windows

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
    │   │   └── MyDialog.nib         <- Window definition
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
   Hold Control when starting command to see stdout

4. **Test nib loading**:
   ```bash
   omc_dialog_control <GUID> omc_window omc_show
   ```

---

## Additional Resources

### OMC Documentation
- [Command Reference](omc_command_reference.md)
- [Runtime Context Reference](omc_runtime_context_reference.md)
- [Controls Reference](omc_controls_user_defined_runtime_attributes.md)

### Example Applets
- [WatchdogApp](https://github.com/abra-code/WatchdogApp) — File system monitoring with custom UI (see `building_watchdog.md` for detailed step-by-step guide)
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

> **Note**: The main command (first in list, no `COMMAND_ID`) is executed when files/folders are dropped on the applet. The script `FileInfo.main.sh` is the handler for this main command.

Drop a file/folder on the app → output window shows file information.

> **For AI Agents**: When creating example applets:
> - Use the FileInfo example as a template for minimal applets
> - The script MUST have a `.sh` (or appropriate) extension
> - The script name must match: `<NAME>.main.<ext>` where `<NAME>` is the command's NAME field

