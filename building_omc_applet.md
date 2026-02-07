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

---

## Step 1: Create the Applet

### Choose a Template

| Template | Description | Use When |
|----------|-------------|----------|
| `OMCApplet.app` | Base template, minimal size | Shell scripts only, no Python needed |
| `OMCPythonApplet.app` | Includes embedded Python 3 | Need Python modules (e.g., watchdog) |

### Build the Applet

```bash
cd ~/git
./OMC/build_applet.sh \
    --omc-applet="OMC_4.4.0/Products/Applications/OMCPythonApplet.app" \
    --icon="MyApp/Icon/MyIcon.icon" \
    --bundle-id=com.example.myapp \
    --creator=MApp \
    MyApp/MyApp.app
```

### Codesign for Local Execution

```bash
./OMC/codesign_applet.sh "MyApp/MyApp.app"
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
    <string>My Command</string>              <!-- Menu label -->
    <key>COMMAND_ID</key>
    <string>my.command.id</string>           <!-- Unique identifier -->
</dict>
```

### Execution Modes

| Mode | Description |
|------|-------------|
| `exe_script_file` | Executes script file in `Scripts/<COMMAND_ID>.<ext>` |
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
    <string>MyApp</string>
    <key>COMMAND_ID</key>
    <string>myapp.main</string>
    <key>ACTIVATION_MODE</key>
    <string>act_folder</string>
    <key>EXECUTION_MODE</key>
    <string>exe_script_file</string>
</dict>
```

---

## Step 3: Create Action Handler Scripts

Scripts live in `MyApp.app/Contents/Resources/Scripts/` and are named by `COMMAND_ID` without extension.

### Environment Variables Available

| Variable | Description | Always Exported |
|----------|-------------|-----------------|
| `$OMC_OBJ_PATH` | Selected file/folder path | Yes |
| `$OMC_OBJ_NAME` | Base name | No |
| `$OMC_APP_BUNDLE_PATH` | Applet bundle path | Yes |
| `$OMC_OMC_SUPPORT_PATH` | OMC support tools | Yes |
| `$OMC_NIB_DLG_GUID` | Dialog instance ID | Yes |
| `$OMC_CURRENT_COMMAND_GUID` | Command execution ID | Yes |

### Example Script

```bash
#!/bin/bash
echo "Processing: ${OMC_OBJ_PATH}"

# Your code here
ls -la "${OMC_OBJ_PATH}"
```

### Forcing Environment Variables

For `exe_script_file`, non-auto variables require forcing:

```xml
<dict>
    <key>COMMAND_ID</key>
    <string>my.action</string>
    <key>EXECUTION_MODE</key>
    <string>exe_script_file</string>
    <key>COMMAND</key>
    <array>
        <string># OMC_OBJ_NAME</string>  <!-- Forces export -->
    </array>
</dict>
```

---

## Step 4: Create Custom UI with NIBs

### NIB Formats

| Format | Editable | Loadable | Notes |
|--------|----------|----------|-------|
| `.xib` | Yes | No | Xcode format, needs compilation |
| `.nib` (flat) | No | Yes | Compiled by Xcode |
| `.nib` (bundled) | Yes | Yes | Contains `designable.nib` + `keyedobjects.nib` |

**Recommendation**: Use bundled `.nib` format for in-place editing.

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

1. Change class: `NSTableView` → `OMCTableView`
2. Change Content Mode: `View Based` → `Cell Based`
3. Set Tag: `0` → `1`
4. Add columns in code or nib

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
"${next_command_tool}" "$OMC_CURRENT_COMMAND_GUID" "myapp.step2"
```

---

## Step 9: Long-Running Processes

Background processes started by scripts can outlive the parent applet. Handle cleanup properly.

### Termination Handler

Special `COMMAND_ID=app.will.terminate` runs when app quits:

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
    │   │   ├── myapp.main.sh       <- Main launch script
    │   │   ├── myapp.window.init    <- Window init handler
    │   │   ├── myapp.window.close   <- Window close handler
    │   │   └── app.will.terminate   <- App quit handler
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
    <string>File Info</string>
    <key>COMMAND_ID</key>
    <string>file.info</string>
    <key>ACTIVATION_MODE</key>
    <string>act_file</string>
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

### Scripts/file.info.sh
```bash
#!/bin/bash
echo "File: ${OMC_OBJ_PATH}"
echo "---"
/usr/bin/stat -x "${OMC_OBJ_PATH}"
```

Drop a file on the app → output window shows file information.

