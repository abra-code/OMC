---
id: execution-modes
level: 2
flavors: [claude, capable]
---

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
