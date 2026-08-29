---
name: omc
description: >
  Create, edit, debug, rebuild, or codesign OMC applets for macOS. Use when the user asks to build/rebuild or codesign an applet, add a command, write an action script, configure Command.plist or Command.json, use omc_dialog_control, chain commands, or work with AppletBuilder (incl. the appletbuilder CLI / Build & Run). For ActionUI JSON UI design, also activate the actionui skill.
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

The command manifest lives at `Contents/Resources/Command.plist` (XML/binary plist) **or** `Contents/Resources/Command.json` (JSON). OMC reads either, preferring `Command.json` when both are present; AppletBuilder creates new applets with `Command.json`. The two formats are structurally identical — the same keys, value types, and `VERSION == 2` rule apply (a JSON number `2` for `VERSION`, JSON `true`/`false` for booleans). This guide shows plist XML, but every example maps directly to JSON.

**Root structure (plist):**
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

**Root structure (JSON equivalent):**
```json
{
  "COMMAND_LIST": [
    {  }
  ],
  "VERSION": 2
}
```

### Command Identity Keys

| Key | Type | Notes |
|-----|------|-------|
| `NAME` | string | Human-readable label. Required. Shared across a command group. |
| `COMMAND_ID` | string | Dot-notation ID (e.g. `MyApp.results.selected`). Required for subcommands. On the **main command** either omit it or set it explicitly to `<NAME>.main` (or bare `main`) — both are equivalent. The main command is also addressable for chaining by `<NAME>.main`, `main`, or the legacy internal `top!`. Its script filename follows the convention `<NAME>.main.<ext>`. |
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
| `MyApp.main.sh` | the main command (no `COMMAND_ID`, or `COMMAND_ID` = `MyApp.main`) — `MyApp` is the `NAME` |
| `MyApp.results.selected.py` | `MyApp.results.selected` |
| `MyApp.settings.save.sh` | `MyApp.settings.save` |
| `lib.myapp.sh` | *(shared library — sourced by other scripts, not a command handler)* |

OMC resolves the interpreter from the extension: `.sh` / `.bash` / `.zsh` → corresponding shell, `.py` → Python, `.applescript` → AppleScript, `.js` → JSC.

**No shebang line is needed.** OMC supplies the interpreter path automatically.

For Python applets, the embedded Python at `Contents/Library/Python/bin/python3` is used when present — no system Python dependency. When a bundle has embedded Python, OMC exports — for every handler, shell or Python — `PATH` (prepended with the interpreter's `bin/`), `PYTHONPYCACHEPREFIX=/tmp/Pyc`, and `PYTHONPATH` (prepended with `Contents/Library/Packages/` when it exists). Install third-party modules into `Contents/Library/Packages/` (e.g. `python3 -m pip install --target .../Contents/Library/Packages pkg`) rather than the runtime's own `site-packages`: the `Packages/` dir survives a Python runtime upgrade/rebuild, whereas `Contents/Library/Python/` is replaced wholesale. See `docs/omc_python_scripting_guide.md`.



## Environment Variables

OMC exports these variables into every script's environment:

### Always Available

| Variable | Description |
|----------|-------------|
| `$OMC_APP_BUNDLE_PATH` | Full path to the running applet's `.app` bundle |
| `$OMC_APP_PROCESS_ID` | PID of the host process running OMC, which for an applet is the applet itself - use it to tell whether the instance that owns some state is still alive (not the frontmost app, that is `$OMC_FRONT_PROCESS_ID`) |
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

# Select a Table/List row programmatically (works for Table and List; fires no actionID)
"$dialog_tool" "$window_uuid" <tableID> omc_select_row 3              # by 0-based index
"$dialog_tool" "$window_uuid" <tableID> omc_select_row_with_content "Report.pdf"  # first row with text in any column
"$dialog_tool" "$window_uuid" <tableID> omc_select_row_with_content "42" 1        # text must be in column 1 (1-based)
"$dialog_tool" "$window_uuid" <tableID> omc_deselect                  # clear selection

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

To chain back to the applet's **main command**, target it by `<NAME>.main` (e.g. `MyApp.main`), bare `main`, or the legacy `top!` — all three resolve to the main command whether it was declared with no `COMMAND_ID` or with an explicit `<NAME>.main` / `main` id. The same aliases work in `NEXT_COMMAND_ID`.

### Other support tools (full usage in `docs/<tool>--help.md`)

| Tool | Purpose | Typical call |
|------|---------|--------------|
| `alert` | Modal alert; choice returned via **exit code** (0=OK, 1=Cancel) | `alert --level caution --ok "Go" --cancel "Cancel" "Sure?"` |
| `pasteboard` | Cross-script key-value store; prefix keys with app name + window UUID | `pasteboard my_key set "v"` / `pasteboard my_key get` |
| `notify` | macOS notification | `notify --title "MyApp" "Done."` |
| `plister` | Plist read/write (for complex edits: `plutil -convert json` → edit → `xml1`) | `plister get value "$plist" /COMMAND_LIST/0/NAME` |



## Hard Rules for Agents — read before writing scripts

Each of these caused a real applet failure for an AI agent. The full
explanations, workaround tables, and a debug-logging recipe are in
`docs/omc_agent_tips_and_troubleshooting.md` — read it when any
of these bites or when behavior can't be explained from the code.

1. **`.sh` scripts run under `/bin/sh` = macOS bash 3.2 in POSIX mode.** There
   is no bash 4/5 on macOS. Process substitution (`done < <(cmd)`),
   `mapfile`, `declare -A`, and `${var,,}` are fatal parse errors that kill
   the script mid-file with no UI feedback. **Validate with `sh -n`, never
   `bash -n`** — `bash -n` passes scripts that die under OMC.
2. **Window init code goes in `INIT_SUBCOMMAND_ID`** (runs before the window
   appears). A non-blocking window's main command script runs at an
   unpredictable time — keep it `exit 0`.
3. **Views inside a not-yet-loaded `LoadableView` can't be targeted** by
   `omc_dialog_control`. Populate them in their `viewDidLoadActionID` handler
   from state files; have init write its readiness file last (atomic `mv`)
   and let handlers poll for it.
4. **Never set a Table's value to select a row** — a plain value (`omc_dialog_control
   <id> "text"`) replaces the rows with one string, it does not move the selection.
   To select programmatically use the dedicated verbs: `omc_select_row <0-based
   index>`, `omc_select_row_with_content <text> [1-based column]` (omit column or
   `0` = match any column; selects the first match), or `omc_deselect` to clear.
   These work on Table and List, fire no actionID, and leave the rows untouched; read the
   result back via `$OMC_ACTIONUI_VIEW_<id>_VALUE`. Feed rows via
   `omc_table_set_rows_from_stdin`; extra tab-separated fields beyond the declared columns
   act as hidden columns (read via `$OMC_ACTIONUI_TABLE_<ID>_COLUMN_<N>_VALUE`).
5. **Pickers deliver (and are set by) the 1-based option INDEX**, not the
   option title; TabView delivers the 0-based tab index as trigger context.
   Persist each picker's ordered option list to a state file and resolve
   index → name in handlers. Validate every control-event value before using
   it — programmatic options/value updates can fire actions with bogus values.
6. **When runtime behavior can't be determined from code, instrument it**:
   add a `dbg()` logger to `/tmp` (gated on a flag file), log
   `$OMC_ACTIONUI_TRIGGER_VIEW_ID/_PART_ID/_CONTEXT` in every handler, ask
   the user to perform the UI operation once, read the log back. Don't guess.
7. **Handlers are testable headlessly — do not hand-roll a stub directory.**
   `appletbuilder test <App.app>` runs `Tests/*.test.sh` against a mock OMC
   environment: real handlers, real `plister` and `pasteboard`, a stubbed
   app-modal `alert` with scripted answers, and a recording
   `omc_dialog_control` so you can assert on what a handler pushed toward the
   window (`ui_value`, `ui_rows`, `ui_title`). Shell and Python applets both.
   See the **Testing an Applet** section for the shape and the traps, then read
   `docs/omctest_guide.md` for the full API; copy from `PackageBuilderApp/Tests/`
   or `NotarizeApp/Tests/` if you have them. What it does NOT cover: rendering
   and layout, the `actionID`-to-COMMAND_ID wiring (`validate` cross-checks
   that one statically, so read its warnings), and anything the harness cannot
   intercept — a system binary called by absolute path (`/usr/bin/codesign`,
   `security`), state under `$HOME`, a background worker the handler spawns, or
   a global pasteboard key shared with every other test run. Each of those needs
   an overridable-variable seam in the applet's own lib.



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

### NIB Dialogs (legacy — do not use for new applets)

Nib (Interface Builder) dialogs predate ActionUI. `.nib` files can only be edited in Xcode, so agents cannot work on them directly. When maintaining an *existing* NIB applet: the window UUID is `$OMC_NIB_DLG_GUID`, control values arrive as `$OMC_NIB_DIALOG_CONTROL_<tag>_VALUE`, and the dialog attaches via a `NIB_DIALOG` dict in the command manifest. Full reference: `docs/Nib-Guide.md` and `docs/omc_controls_user_defined_runtime_attributes.md`.



## AppletBuilder

AppletBuilder (`Distribution/AppletBuilder.app`) is the tool for creating and
maintaining applets. Humans use its GUI; **AI agents drive the same operations from
the command line** via the bundled `appletbuilder` CLI — create from a template,
validate, prettify/preview ActionUI, and rebuild — running the *same* underlying
code as the GUI.

### Agent CLI

```
Distribution/AppletBuilder.app/Contents/Resources/Agents/appletbuilder <command> [args]
```

Progress and validation detail go to **stderr**; capturable results (a created
applet's path, prettified JSON, a screenshot path, listings) go to **stdout**.
Exit codes: `0` ok · `2` warnings · `1` errors.

| Command | Does |
|---------|------|
| `create (--template <name|path> \| --clone <App.app>) --name <N> --dest <dir> [--bundle-id <id>] [--python] [--icon <name|path>]` | Copy a template (or clone an applet), rename it, install the framework/executable (and Python if `--python`), set the icon, and codesign. Prints the new `.app` path. |
| `validate <App.app \| Command.json \| UI.json \| script>` | Auto-detects the target and runs the matching validator(s). For a bundle: `Info.plist` + command manifest (Layer 1/2) + every script + every ActionUI JSON. |
| `build <App.app> [--identity <id>] [--thin arm64\|x86_64] [--test] [--warnings-as-errors] [--update-python] [--force]` | Full validation, then refresh framework/executable (newer version auto-copies; `--force` re-copies even when unchanged), thin, and codesign. Halts before signing on validation errors. Independently, a working embedded Python is left untouched unless `--update-python` is given; a missing/broken runtime is always installed. Replacing the runtime wipes anything pip-installed into its `site-packages` — install deps into `Contents/Library/Packages` (on `PYTHONPATH`) so they survive. `--test` runs the applet's test suite after the refresh and before signing, halting on failure. |
| `test <App.app> [--tests <dir>] [--filter <glob>] [--verbose] [--keep-scratch] [--list]` | Run the applet's `Tests/*.test.sh` against a mock OMC environment: real handlers, stubbed `alert`, a recording `omc_dialog_control` you can assert against. Validates the bundle first. Detail to stderr, `omctest: N passed, M failed, K files` to stdout. See `docs/omctest_guide.md`. |
| `prettify <file.json> [--stdout]` | Reformat JSON in place (or to stdout). |
| `preview <UI.json> [--screenshot <out.png>]` | Render an ActionUI view to a PNG (read it to inspect the layout); a `MainMenu.json` menu-bar doc prints a text summary instead. Needs a GUI session. |
| `list-templates` / `list-icons` | Names for `--template` / `--icon`. |

Example — create a Python applet, then validate and build it:

```bash
AB="Distribution/AppletBuilder.app/Contents/Resources/Agents/appletbuilder"
NEWAPP=$("$AB" create --template "ActionUI Window" --name MyApp --dest ~/Desktop --python --icon Bolt)
"$AB" validate "$NEWAPP"
"$AB" build "$NEWAPP" --thin arm64
```

Full reference: `Distribution/AppletBuilder.app/Contents/Resources/Agents/README.md`.

### Templates

| Template | Use when |
|----------|----------|
| `Empty` | Minimal bundle; no dialog |
| `ActionUI Window` | ActionUI JSON dialog (recommended for OMC 5.0+) |
| `ActionUI Web` | ActionUI dialog with embedded WebView |
| `Nib Window` | NIB (Interface Builder) dialog |
| `Nib Web` | NIB dialog with embedded WebView |

The **Name** also becomes the executable name and script prefix. New applets are
created with a `Command.json` manifest. Humans can do the same from the GUI's New
Applet panel.

### For an existing applet

Edit the bundle's files directly:
- `Contents/Resources/Command.json` (or `Command.plist` — OMC reads either, preferring `Command.json` when both exist)
- `Contents/Resources/Scripts/*`
- `Contents/Resources/Base.lproj/*.json` (ActionUI) or `*.nib` (NIB — edit in Xcode)

After editing, run `appletbuilder validate <App.app>` to catch problems.

### Code signing during development

Applets are signed for local execution; editing bundle resources (scripts, ActionUI JSONs, `Command.json`) does not stop the app from launching during development — macOS (as of 26) does not block resource-modified locally-signed apps. Re-sign — `appletbuilder build <App.app>`, the **Build** button in AppletBuilder's Build & Run pane, or `Scripts/codesign_applet.sh` — after changing binaries/frameworks, before distributing, or if the OS refuses to launch the app.

For full GUI-navigation help (Project Editor tabs, Commands editor, UI Files Validate/Preview/Prettify buttons, etc.), see `docs/appletbuilder_user_guide.md`.



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



## Testing an Applet (omctest)

An applet's logic lives in handler scripts that have no callable entry point:
the engine runs them in response to UI events, feeds them `$OMC_*` variables,
and receives their output through `omc_dialog_control` calls against a live
window. Without a harness, every change is verified by launching the app and
clicking — and the error paths, which are the ones that destroy user data, are
the least likely to be walked by hand.

`appletbuilder test <App.app>` runs the applet's real handlers against a
simulated OMC environment. **Read `docs/omctest_guide.md` before writing tests**
— it is the full API reference. This section is the shape and the traps.

### Layout and the run

`Tests/` sits **next to** the bundle, never inside it (tests in the bundle bloat
the shipped app and dirty its code signature):

```
MyAppApp/
    MyApp.app/
    Tests/
        lib.test.myapp.sh        your applet's accessors, sourced by every file
        10-window.test.sh        numbered; they run in lexical order
        20-....test.sh
        helpers/                 fakes and scripts too big to inline
        fixtures/                read-only; fixture_copy makes a writable copy
```

```bash
appletbuilder test MyApp.app [--filter '20-*'] [--verbose] [--keep-scratch]
appletbuilder build MyApp.app --test      # run the suite before codesigning
```

A human at the GUI has the same thing on the **Test** button in AppletBuilder's
Build & Run pane (next to Build and Run), which logs into the build log. Plain
`build`, and the Build button, do not run tests.

Each file gets its own scratch tree, its own window UUID, and its own
interposition directory. `alert`, `notify`, `omc_dialog_control` and
`omc_next_command` are stubbed (the first would hang forever with no user, the
third becomes the virtual window you assert against); `plister`, `b64`, `filt`
and `loco` are real. `pasteboard` is the real tool behind a wrapper that
namespaces the board NAME per file per run - a named pasteboard lives in the
login pasteboard server, which no amount of `$HOME` isolation can reach.

### The idiom

```sh
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.myapp.sh"

section "opening a document"
omc_object "$(fixture_copy Sample.myappdoc)"   # what the engine would set
omc_run MyApp.main.init                        # dispatch by SCRIPT STEM
check "the field was populated" "com.example.thing" "$(ui_value "$NAME_ID")"
check "the table was fed"       "2"               "$(ui_row_count "$TABLE_ID")"
check_status "it exited cleanly" 0

# Cumulative across the file (API 4+): one check at the end covers everything.
section "no writes to undeclared view ids"
check "no undeclared ids" "" "$(ui_unknown_writes)"

omctest_end                                    # summary + counts; this EXITS
```

`omc_run` takes the script's **file stem**, not the `COMMAND_ID`. They are
usually the same string — except for the primary command, which typically has no
`COMMAND_ID` at all and is dispatched as `<NAME>.main`.

### The seam contract — the thing most applets have to change

The harness intercepts OMC support tools by rebuilding `$OMC_OMC_SUPPORT_PATH`.
It **cannot** reach anything named by an absolute path or a bundle-relative one.
So anything an applet must not really do under test has to be named through an
overridable variable in its shared lib:

```sh
# One variable per binary - a variable holds one word, so a multi-word
# invocation keeps its subcommand at the call site: "$xcrun_tool" notarytool ...
codesign_tool="${MYAPP_CODESIGN_TOOL:-/usr/bin/codesign}"
xcrun_tool="${MYAPP_XCRUN_TOOL:-/usr/bin/xcrun}"
```

**It is not only binaries.** Three other kinds of seam are needed just as often,
and each is easy to forget until a test edits the machine it runs on:

- **State that lives under `$HOME`.** `prefs_dir="${MYAPP_PREFS_DIR:-$HOME/Library/Application Support/MyApp}"`.
  `$TMPDIR` is redirected for you; `$HOME` is not.
- **Background workers the handler spawns.** A poll loop or a downloader started
  with `&` keeps running and keeps writing into the window, which races every
  assertion in the file. Name the script through a variable, point it at a
  recorder, and assert that the right worker was launched with the right
  arguments — which is all a handler is responsible for.
- **Anything the applet reaches through `defaults` on a DOMAIN, or through a path
  built from `/Users/$USER` rather than `"$HOME"`.** Neither can be intercepted -
  cfprefsd keys the user domain by uid, and redirecting an absolute path would
  need a mount namespace - so a test that reaches them touches the real home of
  whoever runs the suite. The suite names every such line at startup. Fix them in
  the applet: `"$HOME"` is the same path in production and under test.

Where a tool is deterministic and safe, **run it for real** (`ditto`, `plutil`,
`xar`, `textutil`, `pkgbuild`): that is what makes the assertions about its
output worth anything. An applet that skips a seam simply has those handlers
excluded from coverage — say so in the test file rather than implying they are
covered.

### Traps that produce green tests that prove nothing

1. **A handler's write does not become the next dispatch's input.** The engine
   exports current control values on every dispatch; the harness records what a
   handler wrote but does **not** feed it back as
   `OMC_ACTIONUI_VIEW_<id>_VALUE`. A field one handler prefilled is invisible to
   the next unless the test bridges it:
   `omc_control "$ID" "$(ui_value "$ID")"`. Same for a table:
   `omctest_setvar "OMC_ACTIONUI_TABLE_10_COLUMN_2_ALL_ROWS" "$rows"`.
2. **A backgrounded worker has not necessarily run when `omc_run` returns.**
   Poll for its record with `omc_wait_for`; never `sleep`.
3. **Compare paths as paths, not as strings.** `$TMPDIR` keeps its trailing
   slash, so an applet's own construction can carry an interior `//` that
   `cd -P`/`pwd -P`/`realpath` normalize away — and `/var` resolves to
   `/private/var`. Build the expected value the same way the applet builds the
   actual one, or assert with `[ -e ]`.
4. **The trigger and dialog families are one-shot**, cleared after every
   `omc_run`. A second dispatch needs its own `omc_trigger` / `omc_dialog_answer`
   — without it the handler exits at its guard and every check about it passes
   vacuously.
5. **`omc_control_defaults <DocName>`, not `omc_reset_controls`.** A window where
   every toggle is off cannot exist; a test written against it describes
   something no user has ever seen.
6. **The pasteboard outlives the process.** `omc_child_sheet`/`omc_window_switch`
   derive their UUID from the name you pass, so two sections using the same name
   share keys - clear every key your applet uses in your reset helper. What you
   no longer have to handle (API 4+) is the *cross-run* half: every board name is
   namespaced per file per run, so a stale value from another run, or from the
   copy of the applet you have running, can no longer arrive in a handler. Both
   had been measured. A test lib that snapshots and restores global keys itself
   can drop that machinery; an applet that grew a `PB_PREFIX` seam only for
   testing no longer needs it.
7. **`ui_enabled` / `ui_visible` return empty for NEVER TOUCHED**, not just for
   off. `check "the button is off" "" "$(ui_enabled "$ID")"` therefore passes
   when the handler never ran at all, and worse: it pins the omission, so the
   obvious fix — adding the missing `omc_disable` — turns the test red. Assert
   the state the *user* meets (`"$(ui_enabled "$ID")" = 1` or not), so both
   routes to a disabled button satisfy it and a handler that skipped the element
   entirely does not.
8. **Chain history is cumulative.** `chains_reset` before any section that
   asserts a chain did *not* happen. So are the three diagnostic logs, as of API
   4 — if your lib checks them per section and then resets, call
   `ui_reset_diagnostics` after the check or one real hit is reported once per
   remaining section, naming the wrong one each time. Ids the applet mints at
   runtime (`omc_insert_element`) are not in the statically-extracted
   `known_ids.txt`: declare them with `ui_declare_ids 2000 2010`, one id at a
   time rather than a range, so the check stays live for everything else.
9. **Import view ids from the applet, never restate them** — and guard the
   import, or a renamed constant expands to empty and every check fails with no
   hint why. Match the applet's own spelling: `NAME_ID=129`, `ID_TABLE = 10`
   (Python), and `MODEL_PICKER=25` (bare, no suffix) all need different patterns.

### Writing checks that can actually fail

**A check that cannot fail is worse than no check**, because it reads as
coverage. Before believing a new assertion, break the thing it names — delete
the guard, make the function a no-op — and confirm it goes red, then restore.
Prefer assertions that name a value the code must *produce*; when you must
assert absence, pair it with a positive control in the same section.

### Out of scope, permanently

No rendering or layout. No synthesized UI events, so a typo'd `actionID` is
silent here — `appletbuilder validate` is what catches that, so read its
warnings. No NIB dialogs. A green `omctest` plus a green `validate` means the
handler logic is correct *given the documented engine contract*; a human still
launches the app once per release and confirms the window looks right.



## Validating Command.plist

After creating or editing a command manifest, validate it before building. The verifier handles both formats — `Command.plist` and `Command.json` — transparently (by extension):

```bash
python3 Skill/scripts/validate_command_plist.py <App.app | Command.plist | Command.json>
```

Pass the **applet bundle** (`.app` / `.omc`) rather than the bare file to also run bundle cross-checks (Layer 2); for a bundle the verifier resolves the command file itself, preferring `Command.json` when both exist (as OMC does): every `exe_script_file` command has a matching `Scripts/<COMMAND_ID>.*`, the `ACTIONUI_WINDOW` JSON / `NIB_DIALOG` nib resources exist, subcommand IDs (`INIT_SUBCOMMAND_ID`, `END_OK_SUBCOMMAND_ID`, `NEXT_COMMAND_ID`, …) resolve, and every `actionID` in the bundle's JSON UI documents points at a command that exists.

Exit codes: `0` clean · `2` warnings only · `1` errors (`[INFO]` lines are advisory and never affect the exit code). Fix every `[ERROR]` before building; investigate each `[WARNING]` (usually a typo, a wrong value type, or a key with no effect in its context); `[INFO]` lines are just FYI.

Common findings:
- **Unknown key** — typo or hallucinated key; check the schema for that dictionary.
- **Wrong value type** — e.g. `DEFAULT_LOCATION` / `DEFAULT_FILE_NAME` must be an *array*; a bare string is silently ignored by the engine.
- **Deprecated `EXECUTION_MODE` alias** — use the modern name (`exe_popen` → `exe_shell_script`).
- **`VERSION` not `2`** — the engine loads nothing unless the root `VERSION` is `2`.
- **"has no effect unless …"** — the key is ignored in this context (e.g. `CUSTOM_*` without `WINDOW_TYPE=custom`; `OUTPUT_WINDOW_SETTINGS` / `PROGRESS` without a popen / `*_with_output_window` mode; `INPUT_MENU` without a popup/combo `INPUT_TYPE`).
- **Dangling subcommand ID / missing dialog resource** — a referenced `COMMAND_ID` (`INIT_SUBCOMMAND_ID`, `NEXT_COMMAND_ID`, …) or a `JSON_NAME` / `NIB_NAME` resource doesn't exist in the bundle. These are errors.
- **Unresolvable `actionID` (warning)** - a control in a JSON UI document names a command that no `COMMAND_ID`, synthesized script, or engine-reserved id (`omc.dialog.ok`, `omc.dialog.cancel`, ...) provides, so clicking it does nothing. Scanned documents are `Resources/*.json` and `Resources/*.lproj/*.json` (where the engine looks one up by `JSON_NAME`), including `MainMenu.json`; every key that is exactly `actionID` or ends in `ActionID` (`onDropActionID`, `valueChangeActionID`, `viewDidLoadActionID`, ...) is checked. Nothing else statically checks this hop, so read these warnings.
- **`actionID` matching "only case-insensitively" (warning)** - the command exists but is spelled with different case. The engine dispatches case-sensitively, so this control is just as dead as a typo. Match the `COMMAND_ID` exactly, and remember a script-only command's id is its filename's case (`MyApp.Save.sh` -> `MyApp.Save`).
- **"no executable body" (info)** — a command has no inline `COMMAND` and no matching script file. This is a *valid, common* pattern when the command presents a dialog (its subcommands do the work) or chains via `NEXT_COMMAND_ID`, so it is only flagged at `[INFO]` level — and not at all when a dialog/chain is present. If the command was meant to run a script, the info note also catches a typo'd `COMMAND_ID`.

The verifier's key knowledge lives in `Skill/scripts/schemas/` (`Command.json` plus one file per sub-dictionary). Read the relevant schema when unsure about a key name, type, or allowed values. This is the same verifier AppletBuilder runs on **Build** and on the Commands tab **Validate** button.



## Reference Documentation

Full OMC reference is in the `docs/` folder (also bundled in `AppletBuilder.app/Contents/Resources/Documentation/`):

| File | Contents |
|------|----------|
| `docs/omc_agent_tips_and_troubleshooting.md` | **For AI agents**: sh-vs-bash fatal syntax, script test harness, init/LoadableView lifecycle, table & picker runtime semantics, debug-logging workflow, pre-flight checklist — with real failure case studies |
| `docs/building_omc_applet.md` | Step-by-step applet creation guide with all details |
| `docs/omc_applet_catalog.md` | **Before building a new applet**: a classified inventory of every working applet in the collection - which one to clone for a batch converter, document editor, inspector, pipeline, or local-AI app, which are NIB-based (not agent-editable), and where to find each UI technique |
| `docs/appletbuilder_user_guide.md` | UI navigation reference for the AppletBuilder GUI app (for human users) |
| `docs/omc_command_reference.md` | Complete `Command.plist` key reference — all execution modes, dialog keys, output window settings, progress dialogs, input dialogs, services |
| `docs/omc_runtime_context_reference.md` | Every `$OMC_*` environment variable and `__SPECIAL_WORD__` substitution |
| `docs/omctest_guide.md` | **Writing tests**: the `Tests/` layout, the full helper API (driving the window, dispatching handlers, asserting on the virtual window), which `omc_dialog_control` verbs replay, the seam contract for binaries the harness cannot intercept, and how to write checks that can actually fail |
| `docs/omc_scripting_guide.md` | Shell script patterns: reading controls, updating UI, tables, state, debugging |
| `docs/omc_python_scripting_guide.md` | Python handlers: env (`PATH`/`PYTHONPATH`/`Packages`), equivalents of all shell patterns, installing deps into `Contents/Library/Packages`, and thinning the embedded Python (the `thin_applet_python.sh` plan/apply workflow) |
| `docs/omc_dialog_control--help.md` | Full `omc_dialog_control` command reference with all operations |
| `docs/omc_next_command--help.md` | `omc_next_command` reference |
| `docs/alert--help.md` | `alert` tool reference with all flags |
| `docs/pasteboard--help.md` | `pasteboard` tool reference |
| `docs/notify--help.md` | `notify` tool reference |
| `docs/plister--help.md` | `plister` plist tool reference |
| `docs/omc_services_reference.md` | macOS Services integration via `NSServices` in `Info.plist` |
| `docs/Nib-Guide.md` | Nib dialog creation: editing in Xcode, control classes, connecting to OMC |
| `docs/omc_controls_user_defined_runtime_attributes.md` | All OMC control classes in Nibs and their settable properties |
| `docs/MenuBar-Guide.md` | Menu bar JSON (`MainMenu.json`) in 5.1 applets: `actionID` command wiring, the `autoPopulate` Commands menu, deletion via `replacing`, Open Recent — the base array-root format is in the ActionUI skill (`ActionUI-MenuBar-JSON-Guide.md`) |

When you need the exact keys for `NIB_DIALOG`, the complete list of `omc_dialog_control` operations, or the full env-var table, read the relevant `docs/` file directly.

For ActionUI JSON UI (element types, properties, validation, patterns): read the **ActionUI skill** (`../ActionUI/Skill/SKILL.md`). The OMC skill only covers how ActionUI connects to OMC — the JSON format itself is entirely in the ActionUI skill.



*Generated by Skill/build_skill.py — edit Skill/master/content/*.md, not this file.*
