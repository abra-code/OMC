---
name: omc
description: >
  Create, edit, and debug OMC applets for macOS. Use when the user asks to build an OMC applet, add a command, write an action script, configure Command.plist, use omc_dialog_control, chain commands, or work with AppletBuilder. For ActionUI JSON UI design, also activate the actionui skill.
version: "1.0"
---

# OMC Skill


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

`Command.plist` is an XML plist at `Contents/Resources/Command.plist`. It declares every command the applet handles.

**Root structure:**
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

### Command Identity Keys

| Key | Type | Notes |
|-----|------|-------|
| `NAME` | string | Human-readable label. Required. Shared across a command group. |
| `COMMAND_ID` | string | Dot-notation ID (e.g. `MyApp.results.selected`). Required for subcommands; **omit on the main command** of an applet. The script filename for the main command follows the convention `<NAME>.main.<ext>`. |
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
| `MyApp.main.sh` | the main command (no `COMMAND_ID`) — `MyApp` is the `NAME` |
| `MyApp.results.selected.py` | `MyApp.results.selected` |
| `MyApp.settings.save.sh` | `MyApp.settings.save` |
| `lib.myapp.sh` | *(shared library — sourced by other scripts, not a command handler)* |

OMC resolves the interpreter from the extension: `.sh` / `.bash` / `.zsh` → corresponding shell, `.py` → Python, `.applescript` → AppleScript, `.js` → JSC.

**No shebang line is needed.** OMC supplies the interpreter path automatically.

For Python applets, the embedded Python at `Contents/Library/Python/bin/python3` is used when present — no system Python dependency.



## Environment Variables

OMC exports these variables into every script's environment:

### Always Available

| Variable | Description |
|----------|-------------|
| `$OMC_APP_BUNDLE_PATH` | Full path to the running applet's `.app` bundle |
| `$OMC_OMC_SUPPORT_PATH` | Path to OMC's support directory — all runtime tools live here |
| `$OMC_CURRENT_COMMAND_GUID` | GUID of the current command invocation (pass to `omc_next_command`) |
| `$OMC_OBJ_PATH` | Path of the file/folder that triggered the command (drag & drop / open panel / service) |

### Window Context

| Variable | Description |
|----------|-------------|
| `$OMC_ACTIONUI_WINDOW_UUID` | Window UUID for ActionUI dialog scripts |
| `$OMC_NIB_DLG_GUID` | Window UUID for NIB dialog scripts |

### Control Values

| Variable | Description |
|----------|-------------|
| `$OMC_ACTIONUI_VIEW_<N>_VALUE` | Current value of ActionUI element with `id` N |
| `$OMC_NIB_DIALOG_CONTROL_<N>_VALUE` | Value of NIB control with tag N |
| `$OMC_NIB_TABLE_<N>_COLUMN_<M>_VALUE` | Selected row value from NIB table tag N, column M (1-based; column 0 = all columns tab-joined) |

### ActionUI Trigger Context

Set when a script runs as the handler for an `actionID` or `valueChangeActionID`:

| Variable | Description |
|----------|-------------|
| `$OMC_ACTIONUI_TRIGGER_VIEW_ID` | `id` of the element that fired the action |
| `$OMC_ACTIONUI_TRIGGER_VIEW_PART_ID` | Part ID (e.g. column index for Table) |
| `$OMC_ACTIONUI_TRIGGER_CONTEXT` | JSON string with full trigger context |

## Runtime Tools

All tools are at `$OMC_OMC_SUPPORT_PATH/`. Source a shared library at the top of every script:

```bash
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.myapp.sh"
```

Set up aliases once in `lib.myapp.sh`:

```bash
dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
next_cmd="$OMC_OMC_SUPPORT_PATH/omc_next_command"
alert_tool="$OMC_OMC_SUPPORT_PATH/alert"
pasteboard_tool="$OMC_OMC_SUPPORT_PATH/pasteboard"
notify_tool="$OMC_OMC_SUPPORT_PATH/notify"
plister_tool="$OMC_OMC_SUPPORT_PATH/plister"
```

### omc_dialog_control — set control values and state

```bash
# Set text value
"$dialog_tool" "$window_uuid" <id> "value"

# ActionUI: set rich content
"$dialog_tool" "$window_uuid" <id> markdown "# Hello"
"$dialog_tool" "$window_uuid" <id> html "<p>Hello</p>"

# Enable / disable a control
"$dialog_tool" "$window_uuid" <id> omc_enable
"$dialog_tool" "$window_uuid" <id> omc_disable

# Show / hide a control
"$dialog_tool" "$window_uuid" <id> omc_show
"$dialog_tool" "$window_uuid" <id> omc_hide

# Set window title
"$dialog_tool" "$window_uuid" omc_window "My Window Title"

# Feed a table from stdin (tab-separated; each line is a row)
printf "Label1\t/data/1\nLabel2\t/data/2\n" | \
  "$dialog_tool" "$window_uuid" <tableID> omc_table_set_rows_from_stdin

# ActionUI only: set a property directly (value is string or JSON fragment)
"$dialog_tool" "$window_uuid" <id> omc_set_property "options" '["A","B","C"]'
"$dialog_tool" "$window_uuid" <id> omc_set_property "disabled" true

# ActionUI only: present an alert
"$dialog_tool" "$window_uuid" omc_window \
  omc_present_alert "Title" "Message" "OK::ok.action" "Cancel:cancel:"

# ActionUI only: insert / remove elements at runtime
"$dialog_tool" "$window_uuid" <parentID> \
  omc_insert_element '{"id":99,"type":"Text","properties":{"text":"Hi"}}'
"$dialog_tool" "$window_uuid" <elementID> omc_remove_element
```

Button spec for alerts: `"title:role:actionID"` — role is `cancel`, `destructive`, or empty for default.

### omc_next_command — chain to another command

```bash
"$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "MyApp.next.step"
```

Schedules `MyApp.next.step` to run after the current script exits. The chained script runs in a fresh environment with the same window context.

### alert — modal alert dialog

The choice is returned via exit code, not stdout.

```bash
"$alert_tool" --level caution --title "MyApp" \
  --ok "Proceed" --cancel "Cancel" "Are you sure?"
result=$?
# 0 = OK/Proceed, 1 = Cancel, 2 = Other, 3 = timeout, -1 = error
```

Levels: `plain` (default), `note`, `caution`, `stop`.

### pasteboard — cross-script key-value store

```bash
"$pasteboard_tool" my_key set "value"
value=$("$pasteboard_tool" my_key get)
```

Use for state that must survive across separate script invocations (e.g., passing the selected file path from a `selected` handler to a later `save` handler). Key names should be unique — prefix with app name + window UUID to avoid collisions between windows.

### notify — macOS notification

```bash
"$notify_tool" --title "MyApp" "Task complete."
# Optional: --sound default
```

### plister — plist file read/write

```bash
# Read a count or value from a plist
count=$("$plister_tool" get count "$plist" /COMMAND_LIST)
name=$("$plister_tool" get value "$plist" /COMMAND_LIST/0/NAME)
```

For complex plist edits, use `plutil -convert json` → Python edit → `plutil -convert xml1` (the pattern used in `plist_edit.py`).



## Execution Modes

Set via `EXECUTION_MODE` in a command dictionary.

| Mode | Description | Use when |
|------|-------------|----------|
| `exe_script_file` | Runs matching script from `Scripts/`; async; full env vars | **Primary mode for all applets** |
| `exe_script_file_with_output_window` | Like above; stdout shown in an output window | Debugging; long-running tasks |
| `exe_shell_script` | Inline `COMMAND` string; `__SPECIAL_WORDS__` substituted; async | Contextual menu one-liners |
| `exe_shell_script_with_output_window` | Inline script with output window | |
| `exe_system` | Inline `COMMAND`; synchronous; no env vars | Simple `open` or `launch` calls |
| `exe_applescript` | Inline AppleScript `COMMAND`; synchronous | AppleScript-only tasks |
| `exe_applescript_with_output_window` | AppleScript with output window | |
| `exe_terminal` | Runs `COMMAND` in a new Terminal window | Interactive CLI tasks |
| `exe_iterm` | Like above but uses iTerm2 | |

**Recommended patterns:**
- ActionUI / NIB applet: `exe_script_file` for every handler. The main command (no `COMMAND_ID`) attaches `ACTIONUI_WINDOW` or `NIB_DIALOG` and opens the window on launch.
- Contextual menu plugin: `exe_shell_script` for simple inline commands; `exe_script_file` for anything requiring env-var access or UI manipulation.

## Activation Modes

Set via `ACTIVATION_MODE`. Controls when the command is visible in contextual menus.

| Mode | Activates when |
|------|---------------|
| `act_always` | Always (use for applet launcher commands and subcommands) |
| `act_file` | A file is selected / right-clicked |
| `act_folder` | A folder is selected / right-clicked |
| `act_file_or_folder` | Either a file or folder is selected |
| `act_file_or_folder_not_finder_window` | File or folder (not just a Finder background click) |
| `act_selected_text` | Text is selected in any application |

## Dialog Integration Keys

Attach a dialog to a command by adding one of these keys to the command dict:

### ACTIONUI_WINDOW

```xml
<key>ACTIONUI_WINDOW</key>
<dict>
    <key>JSON_NAME</key>
    <string>MainWindow</string>          <!-- filename without .json, in Base.lproj/ -->
    <key>INIT_SUBCOMMAND_ID</key>
    <string>MyApp.main.init</string>     <!-- fires when window loads; populate tables here -->
    <key>WINDOW_DID_ACTIVATE_SUBCOMMAND_ID</key>
    <string>MyApp.main.activated</string>
    <key>WINDOW_DID_DEACTIVATE_SUBCOMMAND_ID</key>
    <string>MyApp.main.deactivated</string>
</dict>
```

The JSON file `Contents/Resources/Base.lproj/MainWindow.json` defines the UI (see ActionUI skill).

### NIB_DIALOG

```xml
<key>NIB_DIALOG</key>
<dict>
    <key>NIB_NAME</key>
    <string>MyDialog</string>            <!-- .nib bundle in Base.lproj/ -->
    <key>IS_BLOCKING</key>
    <false/>                             <!-- false = modeless window -->
    <key>INIT_SUBCOMMAND_ID</key>
    <string>MyApp.dialog.init</string>
    <key>END_OK_SUBCOMMAND_ID</key>
    <string>MyApp.dialog.ok</string>
    <key>END_CANCEL_SUBCOMMAND_ID</key>
    <string>MyApp.dialog.cancel</string>
</dict>
```

`INIT_SUBCOMMAND_ID` fires when the window opens — use it to populate initial data.
`END_OK_SUBCOMMAND_ID` fires when the user confirms (OK button or `omc_terminate_ok`).
`END_CANCEL_SUBCOMMAND_ID` fires on cancel.

## Other Useful Command Keys

| Key | Type | Description |
|-----|------|-------------|
| `NEXT_COMMAND_ID` | string | Static: always chains to this command after execution |
| `END_NOTIFICATION` | dict | Shows a completion alert (`TITLE`, `MESSAGE` strings) |
| `PROGRESS` | dict | Progress bar dialog (`TITLE`, `MODE`: `steps`/`counter`/`indeterminate`) |
| `INPUT_DIALOG` | dict | Prompts for user input before running (`TYPE`: `text`/`password`/`popup`/`combo`) |
| `SUBMENU_NAME` | string | Groups this command under a submenu in contextual menus |
| `CATEGORIES` | array | Filter categories for OMC's command list UI |

## App Lifetime Event COMMAND_IDs

These are invoked automatically without being declared in `COMMAND_LIST`:

| COMMAND_ID | When |
|------------|------|
| `app.will.launch` | Before the app is fully launched |
| `app.did.launch` | After launch completes |
| `app.did.activate` | App comes to the foreground |
| `app.did.deactivate` | App loses focus |
| `app.will.terminate` | App is about to quit — use to clean up background processes |



## UI Dialogs

OMC applets have two dialog paradigms. Most new applets should use ActionUI JSON.

### ActionUI JSON (recommended, OMC 5.0+, macOS 14.6+)

A JSON file in `Contents/Resources/Base.lproj/` defines the UI using the ActionUI framework. Connect it to a command via `ACTIONUI_WINDOW` in `Command.plist`:

```xml
<key>ACTIONUI_WINDOW</key>
<dict>
    <key>JSON_NAME</key><string>MainWindow</string>
    <key>INIT_SUBCOMMAND_ID</key><string>MyApp.main.init</string>
</dict>
```

**For ActionUI JSON format** (element types, properties, layout patterns) — read the ActionUI skill. The OMC-specific concerns are:

- `actionID` property value on buttons/pickers/etc. is the `COMMAND_ID` of the handler script that runs on click
- `valueChangeActionID` fires as the value changes (e.g., every keystroke in a TextField)
- Window UUID is `$OMC_ACTIONUI_WINDOW_UUID`
- Read element values via `$OMC_ACTIONUI_VIEW_<id>_VALUE`
- `INIT_SUBCOMMAND_ID` fires when the window loads — populate tables, pickers, and initial state here

**Init script pattern:**

```bash
# MyApp.main.init.sh
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.myapp.sh"

# Populate a picker (element id=20)
"$dialog_tool" "$OMC_ACTIONUI_WINDOW_UUID" 20 \
  omc_set_property "options" '["Option A","Option B","Option C"]'

# Enable a button that starts disabled (element id=10)
"$dialog_tool" "$OMC_ACTIONUI_WINDOW_UUID" 10 omc_enable
```

### NIB Dialogs (AppKit, Interface Builder)

Nib files define UI using AppKit controls. Edit `.nib` files in Xcode via Interface Builder. Use the "Edit" button in AppletBuilder's UI Files or Scripts tabs to open a file in the configured external editor.

**Three steps to make a control interactive:**

1. Rename its class from the standard AppKit version to the OMC version in Xcode's Identity Inspector:

   | Standard class | OMC class |
   |----------------|-----------|
   | `NSButton` | `OMCButton` |
   | `NSTextField` | `OMCTextField` |
   | `NSTableView` | `OMCTableView` |
   | `NSPopUpButton` | `OMCPopUpButton` |
   | `NSSlider` | `OMCSlider` |
   | `NSTextView` | `OMCTextView` |
   | `NSView` (web content) | `OMCWebKitView` |

   Static labels, images, and separators do not need OMC class names.

2. Set the control's **tag** (Identity Inspector → View → Tag) to a non-zero integer. This is the numeric ID scripts use to read/write the control. Some classes (`OMCBox`, `OMCIKImageView`, `OMCPDFView`, `OMCProgressIndicator`, `OMCTextView`, `OMCView`, `OMCWebKitView`) have no native `tag` attribute — add `tag` (Number) as a User Defined Runtime Attribute instead.

3. Add User Defined Runtime Attributes in the Identity Inspector as needed:
   - `commandID` (String) — `COMMAND_ID` to fire when the control is activated (for tables use `selectionCommandID` / `doubleClickCommandID`)
   - `escapingMode` (String) — how the control's value is escaped for `__FOO__` substitution (e.g. `esc_with_backslash`, `esc_wrap_with_single_quotes_for_shell`); not needed when reading via env vars

4. Access the value in scripts via `$OMC_NIB_DIALOG_CONTROL_<tag>_VALUE`.

Connect the nib to a command via `NIB_DIALOG` in `Command.plist` (see execution-modes section for the full key reference). The window UUID for NIB scripts is `$OMC_NIB_DLG_GUID`.

For full NIB documentation: `docs/Nib-Guide.md` and `docs/omc_controls_user_defined_runtime_attributes.md`.



## AppletBuilder

AppletBuilder (`Distribution/AppletBuilder.app`) is the GUI tool users launch to create or edit applets. **AI agents cannot drive AppletBuilder directly** — its workflows are UI-only (template picker, project editor tabs, codesign panel).

### When a user needs a new applet

Direct them to launch AppletBuilder and pick one of the templates:

| Template | Use when |
|----------|----------|
| `Empty` | Minimal bundle; no dialog |
| `ActionUI Window` | ActionUI JSON dialog (recommended for OMC 5.0+) |
| `ActionUI Web` | ActionUI dialog with embedded WebView |
| `Nib Window` | NIB (Interface Builder) dialog |
| `Nib Web` | NIB dialog with embedded WebView |

The user enters **Name** (also becomes the executable name and script prefix), **Bundle ID**, optional icon, and can opt to embed Python. AppletBuilder copies the template, installs `Abracode.framework`, and codesigns the bundle.

### For an existing applet

The agent edits files directly:
- `Contents/Resources/Command.plist`
- `Contents/Resources/Scripts/*`
- `Contents/Resources/Base.lproj/*.json` (ActionUI) or `*.nib` (NIB — edit in Xcode)

### After the agent edits scripts or framework binaries

Ask the user to click **Build** in AppletBuilder's Build & Run pane to re-codesign the bundle. For scripted workflows, `Scripts/codesign_applet.sh` in the distribution does the same.

For full UI-navigation help (Project Editor tabs, Commands editor, UI Files Validate/Preview/Prettify buttons, etc.), see `docs/appletbuilder_user_guide.md`.



## Script Patterns

### Shared Library Pattern

Define tool paths and control IDs once in `lib.myapp.sh` and source it from every handler. This is the standard pattern in every OMC applet.

```bash
# lib.myapp.sh
dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
next_cmd="$OMC_OMC_SUPPORT_PATH/omc_next_command"
alert_tool="$OMC_OMC_SUPPORT_PATH/alert"
pasteboard_tool="$OMC_OMC_SUPPORT_PATH/pasteboard"
notify_tool="$OMC_OMC_SUPPORT_PATH/notify"

# Works for both ActionUI and NIB windows
window_uuid="${OMC_ACTIONUI_WINDOW_UUID:-$OMC_NIB_DLG_GUID}"
cmd_guid="$OMC_CURRENT_COMMAND_GUID"

# Control IDs — match id values in ActionUI JSON or tag values in NIB
STATUS_LABEL_ID=100
RESULTS_TABLE_ID=101
SAVE_BTN_ID=110

# Helper functions
set_value() { "$dialog_tool" "$window_uuid" "$1" "$2"; }
set_enabled() {
    if [ "$2" = "1" ]; then
        "$dialog_tool" "$window_uuid" "$1" omc_enable
    else
        "$dialog_tool" "$window_uuid" "$1" omc_disable
    fi
}
```

Each handler sources the library immediately:
```bash
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.myapp.sh"
```

### State Management

**Per-window state** — keyed to window UUID; lost when the window closes:
```bash
key="myapp_selection_${window_uuid}"
"$pasteboard_tool" "$key" set "$selected_path"
selected_path=$("$pasteboard_tool" "$key" get)
```

**Persistent preferences** — survive app restarts; use `defaults`:
```bash
/usr/bin/defaults write com.example.myapp LastUsedPath "$path"
saved=$(/usr/bin/defaults read com.example.myapp LastUsedPath 2>/dev/null)
```

**Temporary files** — for processing within a single command:
```bash
tmp=$(/usr/bin/mktemp)
# ... write to $tmp, read from $tmp ...
/bin/rm -f "$tmp"
```

### Feeding an ActionUI Table

ActionUI `Table` and `List` elements receive rows via `omc_table_set_rows_from_stdin`. Each row is tab-separated; fields map to columns in order.

```bash
# Two-column table (display name + data path)
{
    while IFS= read -r filepath; do
        name=$(/usr/bin/basename "$filepath")
        printf "%s\t%s\n" "$name" "$filepath"
    done < "$file_list"
} | "$dialog_tool" "$window_uuid" "$RESULTS_TABLE_ID" omc_table_set_rows_from_stdin
```

The number of tab-separated fields per row must match the `widths` array length in the ActionUI JSON. The `actionID` on the Table fires when the user selects a row; read the selected value via `$OMC_ACTIONUI_VIEW_<id>_VALUE`.

### Reading Selected Rows

When a Table's `actionID` fires, the selected value is in `$OMC_ACTIONUI_VIEW_<id>_VALUE`. For multi-column tables, the trigger context identifies which column was used:

```bash
# In MyApp.results.selected.sh
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.myapp.sh"

selected_path="$OMC_ACTIONUI_VIEW_101_VALUE"

if [ -z "$selected_path" ]; then
    set_enabled "$OPEN_BTN_ID" 0
    exit 0
fi

# Save selection and enable action buttons
key="myapp_selection_${window_uuid}"
"$pasteboard_tool" "$key" set "$selected_path"
set_enabled "$OPEN_BTN_ID" 1
set_enabled "$REMOVE_BTN_ID" 1
```

### Command Chaining

Use `omc_next_command` when one script needs to trigger another after finishing — for example, chaining an init sequence or refreshing the UI after a background operation completes:

```bash
# Trigger refresh after processing
"$next_cmd" "$cmd_guid" "MyApp.results.loaded"
```

The chained command runs in its own script invocation with the same window context. Chain depth is not limited, but avoid circular chains.

For static always-chain (every execution), use `NEXT_COMMAND_ID` in `Command.plist` instead.

### Enabling/Disabling Controls Based on Selection

A common pattern — enable action buttons only when something is selected:

```bash
has_selection=0
if [ -n "$OMC_ACTIONUI_VIEW_101_VALUE" ]; then
    has_selection=1
fi

set_enabled "$OPEN_BTN_ID" "$has_selection"
set_enabled "$REMOVE_BTN_ID" "$has_selection"
set_enabled "$REVEAL_BTN_ID" "$has_selection"
```

### Debugging

Control-click (or right-click + hold Ctrl) when triggering a command to see stdout in a window, without permanently setting `EXECUTION_MODE` to `exe_script_file_with_output_window`.

Dump the full environment from any script:
```bash
/usr/bin/printenv | /usr/bin/sort
```



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



## Reference Documentation

Full OMC reference is in the `docs/` folder (also bundled in `AppletBuilder.app/Contents/Resources/Documentation/`):

| File | Contents |
|------|----------|
| `docs/building_omc_applet.md` | Step-by-step applet creation guide with all details |
| `docs/appletbuilder_user_guide.md` | UI navigation reference for the AppletBuilder GUI app (for human users) |
| `docs/omc_command_reference.md` | Complete `Command.plist` key reference — all execution modes, dialog keys, output window settings, progress dialogs, input dialogs, services |
| `docs/omc_runtime_context_reference.md` | Every `$OMC_*` environment variable and `__SPECIAL_WORD__` substitution |
| `docs/omc_scripting_guide.md` | Shell script patterns: reading controls, updating UI, tables, state, debugging |
| `docs/omc_python_scripting_guide.md` | Python equivalents of all shell patterns |
| `docs/omc_dialog_control--help.md` | Full `omc_dialog_control` command reference with all operations |
| `docs/omc_next_command--help.md` | `omc_next_command` reference |
| `docs/alert--help.md` | `alert` tool reference with all flags |
| `docs/Nib-Guide.md` | NIB dialog creation: editing in Xcode, control classes, connecting to OMC |
| `docs/omc_controls_user_defined_runtime_attributes.md` | All OMC control classes and their settable properties |
| `docs/omc_services_reference.md` | macOS Services integration via `NSServices` in `Info.plist` |
| `docs/pasteboard--help.md` | `pasteboard` tool reference |
| `docs/notify--help.md` | `notify` tool reference |
| `docs/plister--help.md` | `plister` plist tool reference |

When you need the exact keys for `NIB_DIALOG`, the complete list of `omc_dialog_control` operations, or the full env-var table, read the relevant `docs/` file directly.

For ActionUI JSON UI (element types, properties, validation, patterns): read the **ActionUI skill** (`../ActionUI/Skill/SKILL.md`). The OMC skill only covers how ActionUI connects to OMC — the JSON format itself is entirely in the ActionUI skill.



*Generated by Skill/build_skill.py — edit Skill/master/content/*.md, not this file.*
