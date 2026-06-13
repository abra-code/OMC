---
id: execution-modes
level: 2
flavors: [claude, capable]
---

## Execution Modes

Set via `EXECUTION_MODE` in a command dictionary.

| Mode | Description | Use when |
|------|-------------|----------|
| `exe_script_file` | Runs matching script from `Scripts/`; async; full env vars | **Primary mode for all applets** — every handler |
| `exe_script_file_with_output_window` | Like above; stdout shown in an output window | Debugging; long-running tasks |
| `exe_shell_script` | Inline `COMMAND` string; `__SPECIAL_WORDS__` substituted; async | Contextual menu one-liners |

Other modes exist for special cases — `exe_shell_script_with_output_window`, `exe_system`, `exe_applescript[_with_output_window]`, `exe_terminal`, `exe_iterm` — see `docs/omc_command_reference.md`.

The main command (no `COMMAND_ID`) attaches `ACTIONUI_WINDOW` or `NIB_DIALOG` and opens the window on launch.

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

### NIB_DIALOG (legacy)

Same shape with `NIB_NAME` instead of `JSON_NAME`, plus `IS_BLOCKING` (false = modeless), `END_OK_SUBCOMMAND_ID`, `END_CANCEL_SUBCOMMAND_ID`. See `docs/Nib-Guide.md`.

`INIT_SUBCOMMAND_ID` fires when the window opens — use it to populate initial data. `END_OK_SUBCOMMAND_ID` / `END_CANCEL_SUBCOMMAND_ID` fire on confirm / cancel (these and `IS_BLOCKING` work for `ACTIONUI_WINDOW` too).

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
