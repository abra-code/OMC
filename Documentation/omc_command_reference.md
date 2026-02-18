# OMC Command Reference

## Introduction

This reference documents the **plist command format** for **OnMyCommand (OMC)**, a low-code engine for building macOS **applets** (standalone mini-apps) and contextual menu items. Commands are defined as dictionaries within command plist file, enabling shell scripts, AppleScripts, or command-line tools to execute in response to user actions via UI triggers such as buttons, menus, or file drops.

This document reorganizes and updates the legacy [Command Description Manual](https://www.abracode.com/free/cmworkshop/Command_Description_Manual.html) by:
- Grouping keys **logically**.
- Highlighting **latest best practices**.
- Marking **deprecated patterns**.

> **Terminology**:
> - **Command** = A description of action to execute in form of a dictionary in the plist.
> - **Action Handler** = A command triggered by a user action (e.g., button click, file drop, dialog init).
> - **Command Group** = Multiple action handlers sharing the same `NAME` but with unique `COMMAND_ID`s (e.g., one group for a dialog: init, OK, cancel, table selection).
> - **Applet** = A standalone mini-app (formerly "droplet").
> - **OnMyCommandCM.plugin** = Legacy contextual menu plug-in formerly loaded in-proc by applications in early macOSes. Apple removed that functionality and nowadays the only way to load and execute old style contextual menu plug-ins is via [Abracode Shortcuts.app] (https://github.com/abra-code/Shortcuts).

---


## 0. Plist Root Structure

The starting point for OMC engine is a `Command.plist` file in applet's bundle in `MyApp.app/Contents/Resources/` or a file in `/Users/<username>/Library/Preferences/com.abracode.OnMyCommandCMPrefs.plist` for `OnMyCommandCM.plugin`. The file is a **property list** containing a root dictionary with two required keys:

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `COMMAND_LIST` | Array of Dictionaries | Yes | Contains all **action handlers** (commands). Each dictionary follows the format described in subsequent sections. |
| `VERSION` | Integer | Yes | **Command format version** – indicates the plist schema version understood by OMC. **Current value: `2`**. This is **not** the same as the optional `VERSION` inside individual commands (which is ignored by the OMC engine). |

### Command Plist Root Structure

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>COMMAND_LIST</key>
  <array>
    <!-- Action handlers go here -->
    <dict>
      <!-- ... one command definition ... -->
    </dict>
  </array>
  <key>VERSION</key>
  <integer>2</integer>
</dict>
</plist>
```

> **Best Practice**:
> - Always set `<key>VERSION</key><integer>2</integer>` at the root level for the latest OMC engine.

---


## 1. Command Structure & Identity

| Key | Type | Required | Description & Best Practice | Example |
|-----|------|----------|-------------------------------|----------|
| `NAME` | String or Array<String> | Yes | Visible label in menus. Use array for dynamic labels. Shared across a **command group**. | `["Set Xattr: ", "__OBJ_NAME__"]` (only `__FOO__` form works here) |
| `COMMAND_ID` | String | Yes | **Unique identifier** for the action handler. **Unique readable strings are recommended**. Used to name script files and for subcommand chaining. | `"my.action.handler"` |
| `VERSION` | Integer or String | No | Semantic version for your reference (ignored by OMC). | `"1.0"` |
| `NOTES` | String | No | Developer comments (ignored by OMC). | `"Removes quarantine bit"` |
| `DISABLED` | Boolean | No | `<true/>` disables the action handler. | — |
| `CATEGORIES` | Array<String> | No | For organization of commands in a catalog (ignored by OMC). | `["File", "Extended Attributes"]` |
| `SUBMENU_NAME` | String | No | Menu nesting path in contextual menus for managing many items. Use `"/"` for root. | `"/File Commands"` |

> **Best Practices**:
> - Group related action handlers (e.g., dialog init, OK, cancel) under **one `NAME`** with **unique `COMMAND_ID`s**. A command group shows as one item in a menu.
> - `VERSION`, `DISABLED`, `CATEGORIES`, `SUBMENU_NAME` are rarely used. Skip adding unnecessary key-value pairs for concise and readable command description.

---


## 2. Execution Modes

Declared with `<key>EXECUTION_MODE</key>`. Default `exe_shell_script` if key not present and `COMMAND` exists or `exe_script_file` if `COMMAND` is not specified.

| Mode | Async/Sync | Env Vars? | Best For | Notes |
|------|------------|-----------|---------|-------|
| `exe_script_file` | **Async** (unless `WAIT_FOR_TASK_COMPLETION=true`) | Yes | **Applets** | **Recommended**. Script at `Resources/Scripts/<COMMAND_ID>.sh` |
| `exe_shell_script` | **Async** (unless wait) | Yes | **Contextual menus** | Inline script; default for simple cases |
| `exe_system` | **Sync** | No | Legacy sync | **No env vars** — use `__FOO__` only |
| `exe_applescript` | **Sync** | No | UI scripting, driving other apps | **No env vars** — use `__FOO__` |
| `exe_terminal` / `exe_iterm` | **Async** | Yes | Debugging, commands for advanced users | Opens in Terminal/iTerm |
| `exe_shell_script_with_output_window` | **Async** (unless wait) | Yes | User feedback | Shows output pane |
| `exe_script_file_with_output_window` | **Async** (unless wait) | Yes | Applet + feedback | |
| `exe_applescript_with_output_window` | **Sync** | No | AppleScript + output | |

> **Deprecated aliases**:
> - `exe_popen`, `exe_silent_popen`, `exe_silent` → use `exe_shell_script` 
> - `exe_popen_with_output_window` → use `exe_shell_script_with_output_window`
> - `exe_silent_system` → use `exe_system`
>
> **New in v4.3**: `WAIT_FOR_TASK_COMPLETION` (boolean) forces sync for some async modes.


> **Best Practices**:
> - **For Applets**: Use `exe_script_file` + external script files in `MyApp.app/Contents/Resources/Scripts/`. Script file name matches `COMMAND_ID` name (plus known extension like `.sh` or `.bash`)
> - **For Contextual Menus (OnMyCommandCM)**: Use `exe_shell_script` + inline `COMMAND` array (or single string with env vars).
> - **Prefer `$OMC_FOO` env vars**; fall back to `__FOO__` only in `exe_system` or `exe_applescript`.
> - **Always quote env vars**: `"${OMC_OBJ_PATH}"`.
> - **Use unique descriptive `COMMAND_ID`s** (early OMC 4-character limit is deprecated).

---


## 3. Activation & Context

Controls **when** an action handler is available and what primary runtime context it expects.

| Key | Type | Default | Description |
|-----|------|---------|-----------|
| `ACTIVATION_MODE` | String | `act_always` | Trigger context. See table below. |
| `ACTIVATION_EXTENSIONS` | Array<String> | — | File extensions (without dot). Case-insensitive. |
| `ACTIVATION_FILE_TYPES` | Array<String> | — | UTI codes (e.g., `"public.zip-archive"`). |
| `ACTIVATION_OBJECT_STRING_MATCH` | Dict | — | Advanced regex/name/path matching |

### Activation Modes

| Mode | Description |
|------|-----------|
| `act_always` | Always available |
| `act_file` | File(s) selected or dropped |
| `act_folder` | Folder(s) |
| `act_file_or_folder` | Either |
| `act_selected_text` | Text selected or in clipboard |
| `act_file_or_folder_not_finder_window` | Excludes Desktop/Finder window |

---


## 4. Command Definition: Two Recommended Patterns

### Pattern A: **Applet Action Handler** (`exe_script_file`)

**Use when building standalone applets.**

```xml
<dict>
  <key>NAME</key>
  <string>Clear Quarantine</string>
  <key>COMMAND_ID</key>
  <string>clear_quarantine</string>
  <key>ACTIVATION_MODE</key>
  <string>act_file_or_folder</string>
  <key>EXECUTION_MODE</key> <!-- optional, exe_script_file is default when COMMAND is absent -->
  <string>exe_script_file</string>
</dict>
```

**Script file**:  
`MyApp.app/Contents/Resources/Scripts/clear_quarantine.sh`

```bash
#!/bin/bash
xattr -dr com.apple.quarantine "${OMC_OBJ_PATH}"
```

> **Advantages**:
> - Clean separation of logic.
> - Full shell scripting (functions, error handling).
> - Easy debugging and reuse.

---

### Pattern B: **Contextual Menu Command** (`exe_shell_script`)

**Use in `OnMyCommandCM` or simple applets.**

```xml
<dict>
  <key>NAME</key>
  <string>Uncompress GZip</string>
  <key>COMMAND_ID</key>
  <string>uncompress_gzip</string>
  <key>ACTIVATION_MODE</key>
  <string>act_file</string>
  <key>ACTIVATION_EXTENSIONS</key>
  <array>
    <string>gz</string>
    <string>tgz</string>
  </array>
  <key>EXECUTION_MODE</key>  <!-- optional, exe_shell_script is default -->
  <string>exe_shell_script</string>
  <key>COMMAND</key>
  <array>
    <string>gzip -d "${OMC_OBJ_PATH}"</string>
  </array>
</dict>
```

> **Best Practices**:
> - Any special context keyword in form of `__FOO__` must be a separate string in the `COMMAND` array
> - When using environment variables you don't need to chop the script into multiple strings in `COMMAND` array so one string is sufficient.
> - **Always quote** environment variables: `"${OMC_OBJ_PATH}"`
> - Use `{}` to avoid shell parsing issues.
> - Multiple strings in `COMMAND` array are concatenated without spaces. So an array like: `["gzip", "-d", "${OMC_OBJ_PATH}"]` → `gzip-d/path` → **broken**.

---

## 5. Runtime Context: Environment Variables vs Special Words

See the full **[OMC Runtime Context Reference](omc_runtime_context_reference.md)** for complete list.

**Summary**:
- **Env Vars** (`$OMC_FOO`): Preferred in scripts. Exported if `OMC_FOO` appears in `COMMAND`.
- **Special Words** (`__FOO__`): Inline substitution. Required in `NAME` arrays and for `exe_system`/`exe_applescript`.

**Best Practices**:
- Use `$OMC_FOO` in scripts.
- Use `__FOO__` only in `NAME` arrays or when env vars are unavailable.
- Force export for `exe_script_file` by putting an env var in a comment in `COMMAND` or add explicit `ENVIRONMENT_VARIABLES`.

---


## 6. NIB_DIALOG – Custom User Interfaces

`NIB_DIALOG` allows an **action handler** to present a **custom Interface Builder (.nib) dialog** instead of using built-in input prompts. The nib is loaded from the applet bundle, and OMC bridges controls to command execution via **subcommands** and **runtime tools**.

---

### `NIB_DIALOG` Dictionary Keys

| Key | Type | Required | Description & Best Practices |
|-----|------|----------|------------------------------|
| `NIB_NAME` | String | Yes | Name of the `.nib` file **without extension** in `Resources/Nibs/`. Case-sensitive. | `"MySettingsDialog"` |
| `IS_BLOCKING` | Boolean | No (default: `true`) | If `<false/>`, dialog is non-modal (async). Use for background tasks with live updates. | `<false/>` |
| `INIT_SUBCOMMAND_ID` | String | No | `COMMAND_ID` to run **before** dialog appears (e.g., populate table). | `"init_table"` |
| `END_OK_SUBCOMMAND_ID` | String | No | `COMMAND_ID` to run on **OK / Confirm** button. | `"apply_changes"` |
| `END_CANCEL_SUBCOMMAND_ID` | String | No | `COMMAND_ID` to run on **Cancel**. | `"cleanup"` |

> **Note**: `IS_COCOA` is **removed** in recent OMC versions.

---

### Example: Full NIB_DIALOG Definition

```xml
<dict>
  <key>NAME</key>
  <string>Edit Metadata</string>
  <key>COMMAND_ID</key>
  <string>show_metadata_editor</string>
  <key>EXECUTION_MODE</key>
  <string>exe_script_file</string>
  <key>NIB_DIALOG</key>
  <dict>
    <key>NIB_NAME</key>
    <string>MetadataEditor</string>
    <key>IS_BLOCKING</key>
    <true/>
    <key>INIT_SUBCOMMAND_ID</key>
    <string>populate_metadata</string>
    <key>END_OK_SUBCOMMAND_ID</key>
    <string>save_metadata</string>
    <key>END_CANCEL_SUBCOMMAND_ID</key>
    <string>discard_changes</string>
  </dict>
</dict>
```

---

### Subcommand Flow Example

```xml
<!-- Init: Populate table -->
<dict>
  <key>NAME</key>
  <string>Edit Metadata</string>
  <key>COMMAND_ID</key>
  <string>populate_metadata</string>
  <key>EXECUTION_MODE</key>
  <string>exe_script_file</string>
</dict>

<!-- OK: Save changes -->
<dict>
  <key>NAME</key>
  <string>Edit Metadata</string>
  <key>COMMAND_ID</key>
  <string>save_metadata</string>
  <key>EXECUTION_MODE</key>
  <string>exe_script_file</string>
</dict>
```

**Script** (`Scripts/populate_metadata.sh`):
```bash
#!/bin/bash
# Read file metadata
tags=$(/usr/bin/mdls -name kMDItemKeywords "${OMC_OBJ_PATH}" | grep -o '"[^"]*"')
# Populate table ID 101
echo "Tag\tValue" > /tmp/table_data
for tag in $tags; do
  echo "${tag}\tEditable" >> /tmp/table_data
done
omc_dialog_control "${OMC_NIB_DLG_GUID}" 101 add_rows "$(cat /tmp/table_data)"
```

---

### Runtime Control Tools (in scripts)

| Tool | Purpose |
|------|--------|
| `omc_dialog_control "$OMC_NIB_DLG_GUID" <ID> <value>` | Set/get control value. |
| `omc_dialog_control "$OMC_NIB_DLG_GUID" <tableID> add_rows "<tab-sep data>"` | Populate table. |
| `omc_next_command <COMMAND_ID>` | Chain to another action handler. |

---

### Best Practices

- **Prefer `IS_BLOCKING=false`** unless you have a specific need for a modal dialog disallowing user interaction with other UI elements of the applet.
- **Prefer `exe_script_file`** for subcommands/action handlers.

---

*See [OMC Runtime Context Reference](omc_runtime_context_reference.md) for nib-related special words and env vars.

---

## 6.1. ACTIONUI_WINDOW – ActionUI JSON Dialogs (under development)

`ACTIONUI_WINDOW` allows an **action handler** to present a **custom dialog** defined by a JSON content view description using the [ActionUI library](https://github.com/abra-code/ActionUI). The JSON file is loaded from the applet bundle, and OMC bridges controls to command execution via **subcommands** and **runtime tools**, similar to `NIB_DIALOG`.

> **Note**: This is a work-in-progress. ActionUI will be integrated into your OMC for this feature to work. The ActionUI library provides SwiftUI-like declarative UI definitions in JSON format.

---

### `ACTIONUI_WINDOW` Dictionary Keys

| Key | Type | Required | Description & Best Practices |
|-----|------|----------|------------------------------|
| `JSON_NAME` | String | Yes | Name of the `json` file **without extension** in app bundle resources. Case-sensitive. |
| `IS_BLOCKING` | Boolean | No (default: `true`) | If `<false/>`, dialog is non-modal | `INIT_SUBCOMMAND_ID` | String | No | `COMMAND_ID` to run **before** dialog appears (e.g., populate values). |
| `END_OK_SUBCOMMAND_ID` | String | No | `COMMAND_ID` to run on **OK / Confirm** button (actionID matching button's actionID). |
| `END_CANCEL_SUBCOMMAND_ID` | String | No | `COMMAND_ID` to run on **Cancel** (actionID matching button's actionID). |

> **Note**: Unlike `NIB_DIALOG` which uses commandIDs for controls, `ACTIONUI_WINDOW` uses **actionIDs** defined in the JSON. Buttons in the JSON should have an `actionID` property that matches the `COMMAND_ID` of the handler you want to execute.

---

### Example: Full ACTIONUI_WINDOW Definition

**JSON File** (`Resources/SettingsDialog.json`):
```json
{
  "type": "VStack",
  "properties": {
    "spacing": 10.0,
    "padding": "default"
  },
  "children": [
    {
      "type": "Text",
      "properties": {
        "text": "Settings"
      },
      "id": "title"
    },
    {
      "type": "TextField",
      "properties": {
        "placeholder": "Enter name"
      },
      "id": 1
    },
    {
      "type": "Button",
      "properties": {
        "title": "OK",
        "buttonStyle": "borderedProminent",
        "actionID": "save_settings"
      },
      "id": 2
    },
    {
      "type": "Button",
      "properties": {
        "title": "Cancel",
        "actionID": "cancel_settings"
      },
      "id": 3
    }
  ]
}
```

**Command.plist**:
```xml
<dict>
  <key>NAME</key>
  <string>Edit Settings</string>
  <key>COMMAND_ID</key>
  <string>show_settings_dialog</string>
  <key>EXECUTION_MODE</key>
  <string>exe_script_file</string>
  <key>ACTIONUI_WINDOW</key>
  <dict>
    <key>JSON_NAME</key>
    <string>SettingsDialog</string>
    <key>INIT_SUBCOMMAND_ID</key>
    <string>init_settings</string>
  </dict>
</dict>

<!-- Init: Set initial values -->
<dict>
  <key>NAME</key>
  <string>Edit Settings</string>
  <key>COMMAND_ID</key>
  <string>init_settings</string>
  <key>EXECUTION_MODE</key>
  <string>exe_script_file</string>
</dict>

<!-- OK: Save settings -->
<dict>
  <key>NAME</key>
  <string>Edit Settings</string>
  <key>COMMAND_ID</key>
  <string>save_settings</string>
  <key>EXECUTION_MODE</key>
  <string>exe_script_file</string>
</dict>

<!-- Cancel -->
<dict>
  <key>NAME</key>
  <string>Edit Settings</string>
  <key>COMMAND_ID</key>
  <string>cancel_settings</string>
  <key>EXECUTION_MODE</key>
  <string>exe_script_file</string>
</dict>
```

**Script** (`Scripts/init_settings.sh`):
```bash
#!/bin/bash
# Set initial values for controls via runtime tool
# View ID 1 is a TextField - set its value using omc_dialog_control
omc_dialog_control "${OMC_ACTIONUI_WINDOW_UUID}" 1 set_value "Default Value"
```

---

### ActionUI View Access

View values are accessed via environment variables and special words similar to NIB_DIALOG:

| Special Word | Environment Variable | Description |
|--------------|---------------------|-------------|
| `__ACTIONUI_WINDOW_UUID__` | `OMC_ACTIONUI_WINDOW_UUID` | Unique window identifier |
| `__ACTIONUI_VIEW_N_VALUE__` | `OMC_ACTIONUI_VIEW_N_VALUE` | Value of view with ID N |

> **Note**: ActionUI uses integer IDs for views (defined as `id` in JSON). Access them using the numeric ID: `__ACTIONUI_VIEW_1_VALUE__` or `$OMC_ACTIONUI_VIEW_1_VALUE`.

---

### Best Practices

- **Prefer `exe_script_file`** for subcommands/action handlers.
- **Use descriptive view IDs** in your JSON for easier scripting.
- **Set initial values dynamically** using `omc_dialog_control` in init subcommand script.

---

*See [OMC Runtime Context Reference](omc_runtime_context_reference.md) for ActionUI-related special words and env vars.

---

## 7. File Navigation Dialogs Options

The sub-dictionaries `SAVE_AS_DIALOG`, `CHOOSE_FILE_DIALOG`, `CHOOSE_FOLDER_DIALOG`, and `CHOOSE_OBJECT_DIALOG` customize built-in file/folder selection dialogs. They are placed directly in an action handler and affect the behavior of dialogs triggered by context variables like `OMC_DLG_SAVE_AS_PATH` or `OMC_DLG_CHOOSE_FILE_PATH`.

All four dialogs share **most options**. Only `DEFAULT_FILE_NAME` option is exclusive to `SAVE_AS_DIALOG`. Omit the dictionary for default behavior.

---

### Shared Options (All Dialogs)

| Key | Type | Default | Applies To | Description & Best Practices |
|-----|------|---------|-------------|------------------------------|
| `MESSAGE` | String | `"Save As..."` / `"Choose File..."` / `"Choose Folder..."` / `"Choose..."` | All | Custom prompt text. | `"Select Output Folder:"` |
| `DEFAULT_LOCATION` | Array<String> | None | All | Starting directory (resolved via special words). Use array for fallbacks. | `["__OBJ_PARENT_PATH__", "~"]` |
| `SHOW_INVISIBLE_ITEMS` | Boolean | `false` | All | Show hidden files/folders. | `<true/>` for system paths |
| `USE_PATH_CACHING` | Boolean | `false` | All | Remember last-used path (post-v2.5). | `<true/>` for repeat workflows |

---

### `SAVE_AS_DIALOG` – Exclusive Option

| Key | Type | Default | Description & Best Practices |
|-----|------|---------|------------------------------|
| `DEFAULT_FILE_NAME` | String or Array<String> | None | Pre-filled filename in the save field. Use array for dynamic names. | `["Backup-", __OBJ_NAME__, ".zip"]` |

---

### Example: Shared + Exclusive Usage

```xml
<!-- Save As with pre-filled name and cached location -->
<key>SAVE_AS_DIALOG</key>
<dict>
  <key>MESSAGE</key>
  <string>Save Processed File</string>
  <key>DEFAULT_FILE_NAME</key>
  <array>
    <string>Processed-</string>
    <string>__OBJ_NAME__</string>
  </array>
  <key>DEFAULT_LOCATION</key>
  <array>
    <string>__OBJ_PARENT_PATH__</string>
  </array>
  <key>USE_PATH_CACHING</key>
  <true/>
</dict>

<!-- Choose Folder with cached path -->
<key>CHOOSE_FOLDER_DIALOG</key>
<dict>
  <key>MESSAGE</key>
  <string>Select Destination</string>
  <key>DEFAULT_LOCATION</key>
  <array>
    <string>~</string>
  </array>
  <key>USE_PATH_CACHING</key>
  <true/>
</dict>

<key>COMMAND</key>
<array>
  <string>cp "${OMC_OBJ_PATH}" "${OMC_DLG_SAVE_AS_PATH}"</string>
</array>
```

---

> ### Best Practices:
> - **Dynamic Paths**: Use `__OBJ_PARENT_PATH__` or `~` in `DEFAULT_LOCATION`.
> - **Caching**: Enable `USE_PATH_CACHING` for consistent user experience.
> - **Error Handling**: Always check for cancellation:
>   
>   if [ -z "${OMC_DLG_SAVE_AS_PATH}" ]; then
>     echo "Save canceled" >&2
>     exit 1
>   fi
>   
> - **Granular Access**: Use `$OMC_DLG_SAVE_AS_NAME`, `$OMC_DLG_CHOOSE_FILE_PARENT_PATH`, etc. for fine control.
> *See [OMC Runtime Context Reference](omc_runtime_context_reference.md) for all dialog-related variables.

---

## 8. OUTPUT_WINDOW_SETTINGS – Customizing Output Feedback

The `OUTPUT_WINDOW_SETTINGS` dictionary controls the **output window** shown when using execution modes that support user-visible feedback (`exe_shell_script_with_output_window`, `exe_script_file_with_output_window`, `exe_applescript_with_output_window`).

This provides a lightweight alternative to full NIB dialogs for displaying command results or logs.

---

### `OUTPUT_WINDOW_SETTINGS` Dictionary Keys

| Key | Type | Default | Description & Best Practices |
|-----|------|---------|------------------------------|
| `WINDOW_TITLE` | String or Array<String> | Command `NAME` | Window title. Use array for dynamic content. | `["Result: ", __OBJ_NAME__]` |
| `WINDOW_TYPE` | String | `"floating"` | Window behavior: `"regular"` (standard), `"floating"` (app-top), `"global_floating"` (always-top), `"custom"` (PNG-shaped). | `"custom"` |
| `WINDOW_POSITION` | String | `"alert"` | Positioning: `"absolute"` (fixed coords), `"alert"` (alert-like), `"center"` (screen center), `"cascade"` (stacked). | `"center"` |
| `WINDOW_WIDTH` | Integer | `400` | Window width in points. | `600` |
| `WINDOW_HEIGHT` | Integer | `200` | Window height in points. | `400` |
| `FRACT_POSITION_LEFT` | Real | `0.5` | Left fraction of screen (0.0=left, 1.0=right). Requires `WINDOW_POSITION="absolute"`. | `0.1` (left side) |
| `FRACT_POSITION_TOP` | Real | `0.5` | Top fraction of screen (0.0=top, 1.0=bottom). Requires `WINDOW_POSITION="absolute"`. | `0.9` (bottom) |
| `ABSOLUTE_POSITION_TOP` | Integer | `50` | Absolute top position (points; for `"absolute"`). | `100` |
| `ABSOLUTE_POSITION_LEFT` | Integer | `50` | Absolute left position (points; for `"absolute"`). | `100` |
| `WINDOW_ALPHA` | Real | `1.0` | Transparency (0.0=transparent, 1.0=opaque). | `0.95` |
| `TEXT_FONT` | String | `"Monaco"` | Font family. | `"Menlo-Regular"` |
| `TEXT_SIZE` | Integer | `10` | Font size in points. | `12` |
| `TEXT_COLOR` | String | `"000000"` | Text color (6-hex RRGGBB). | `"#002B36"` |
| `BACKGROUND_COLOR` | String | `"FFFFFF"` | Background color (6-hex RRGGBB). | `"#FDF6E3"` |
| `CUSTOM_WINDOW_PNG_IMAGE` | String | None | PNG path for `WINDOW_TYPE="custom"` (defines shape/background). | `"custom.png"` |
| `CUSTOM_TEXTBOX_POSITION_TOP` | Integer | `0` | Text area top offset (custom only). | `20` |
| `CUSTOM_TEXTBOX_POSITION_LEFT` | Integer | `0` | Text area left offset (custom only). | `20` |
| `CUSTOM_TEXTBOX_WIDTH` | Integer | Window width | Text area width (custom only). | `300` |
| `CUSTOM_TEXTBOX_HEIGHT` | Integer | Window height | Text area height (custom only). | `200` |
| `CUSTOM_CLOSEBOX_POSITION_TOP` | Integer | `0` | Close area top (custom only). | `5` |
| `CUSTOM_CLOSEBOX_POSITION_LEFT` | Integer | `0` | Close area left (custom only). | `5` |
| `CUSTOM_CLOSEBOX_WIDTH` | Integer | Window width | Close area width (custom only). | `20` |
| `CUSTOM_CLOSEBOX_HEIGHT` | Integer | Window height | Close area height (custom only). | `20` |
| `WINDOW_OPEN_FADE_IN` | Boolean | `false` | Fade in on open. | `<true/>` |
| `WINDOW_CLOSE_FADE_OUT` | Boolean | `false` | Fade out on close. | `<true/>` |
| `AUTO_CLOSE_TIMEOUT` | Real | `0` (no auto-close) | Auto-close delay (seconds; post-v1.7). | `5.0` |
| `AUTO_CLOSE_ON_SUCCESS_ONLY` | Boolean | `false` | Auto-close only on success (exit 0). | `<true/>` |

---

### Execution Mode Requirements

| Mode | Sync/Async | Output Window |
|------|------------|---------------|
| `exe_shell_script_with_output_window` | Async | Yes |
| `exe_script_file_with_output_window` | Async | Yes |
| `exe_applescript_with_output_window` | Sync | Yes |

> **Note**: Standard modes do **not** show output windows.

---

### Example: Custom Shaped Window with Fade & Positioning

```xml
<dict>
  <key>NAME</key>
  <string>Run Diagnosis</string>
  <key>COMMAND_ID</key>
  <string>run_diagnostic</string>
  <key>EXECUTION_MODE</key>
  <string>exe_script_file_with_output_window</string>
  <key>OUTPUT_WINDOW_SETTINGS</key>
  <dict>
    <key>WINDOW_TITLE</key>
    <array>
      <string>Diagnosis: </string>
      <string>__OBJ_NAME__</string>
    </array>
    <key>WINDOW_TYPE</key>
    <string>custom</string>
    <key>WINDOW_POSITION</key>
    <string>absolute</string>
    <key>FRACT_POSITION_LEFT</key>
    <real>0.66</real>
    <key>FRACT_POSITION_TOP</key>
    <real>0.33</real>
    <key>WINDOW_WIDTH</key>
    <integer>300</integer>
    <key>WINDOW_HEIGHT</key>
    <integer>200</integer>
    <key>WINDOW_ALPHA</key>
    <real>0.95</real>
    <key>TEXT_FONT</key>
    <string>Menlo-Regular</string>
    <key>TEXT_SIZE</key>
    <integer>12</integer>
    <key>TEXT_COLOR</key>
    <string>002B36</string>
    <key>BACKGROUND_COLOR</key>
    <string>FDF6E3</string>
    <key>CUSTOM_WINDOW_PNG_IMAGE</key>
    <string>bezel.png</string>
    <key>CUSTOM_TEXTBOX_POSITION_TOP</key>
    <integer>20</integer>
    <key>CUSTOM_TEXTBOX_POSITION_LEFT</key>
    <integer>20</integer>
    <key>CUSTOM_CLOSEBOX_POSITION_TOP</key>
    <integer>5</integer>
    <key>CUSTOM_CLOSEBOX_POSITION_LEFT</key>
    <integer>5</integer>
    <key>WINDOW_OPEN_FADE_IN</key>
    <true/>
    <key>WINDOW_CLOSE_FADE_OUT</key>
    <true/>
    <key>AUTO_CLOSE_TIMEOUT</key>
    <real>5.0</real>
    <key>AUTO_CLOSE_ON_SUCCESS_ONLY</key>
    <true/>
  </dict>
</dict>
```

**Script** (`Scripts/run_diagnostic.sh`):
```bash
#!/bin/bash
echo "Starting diagnostic on: ${OMC_OBJ_PATH}"
echo "----------------------------------------"
system_profiler SPHardwareDataType
echo "----------------------------------------"
echo "Done."
exit 0
```

---

> ### Best Practices:
> - **Fonts**: Use monospaced like `Menlo` for logs.
> - **Positioning**: `FRACT_POSITION_*` for relative; `ABSOLUTE_*` for fixed.
> - **Custom**: PNG must match window size; define clickable close area.
> - **Colors**: 6-hex without `#`.
> - **Fades/Auto-Close**: Enhance UX for transient output.

---


## 9. Pre-Built Dialog `END_NOTIFICATION` – Task Completion Alert

Displays a notification dialog when an asynchronous task ends. Only for async modes (e.g., `exe_shell_script`, `exe_shell_script_with_output_window`). Falls back to last output line if no `MESSAGE`.

| Key | Type | Default | Description & Best Practices |
|-----|------|---------|------------------------------|
| `TITLE` | String | Command `NAME` | Alert title. | `"Task Complete"` |
| `MESSAGE` | String | Last output line | Custom message. | `"Processing finished for ${OMC_OBJ_NAME}"` (use `__OBJ_NAME__` for dynamic) |

**Example**:
```xml
<dict>
  <key>NAME</key>
  <string>Process File</string>
  <key>EXECUTION_MODE</key>
  <string>exe_shell_script</string>
  <key>END_NOTIFICATION</key>
  <dict>
    <key>TITLE</key>
    <string>Complete!</string>
    <key>MESSAGE</key>
    <string>File "${OMC_OBJ_NAME}" has been optimized.</string>
  </dict>
</dict>
```

**Notes**:
- No output from `exe_system` means no fallback `MESSAGE`.
- Use with `WAIT_FOR_TASK_COMPLETION=false` for true async feedback.

---

## 10. Pre-Built Dialog `PROGRESS` – Progress Bar Dialog

Shows a progress dialog parsing command output. Only for popen-based modes (e.g., `exe_shell_script_with_output_window`). Supports **three sub-modes**:

1. `DETERMINATE_STEPS` – Fixed text matches  
2. `DETERMINATE_COUNTER` – Regex-extracted counter  
3. **Indeterminate (default)** – Auto-advances per object or shows last output line  

---

#### Shared Keys (All Modes)

| Key | Type | Default | Description & Best Practices |
|-----|------|---------|------------------------------|
| `TITLE` | String | `"Progress"` | Dialog title. | `"Processing Files"` |
| `DELAY` | Real | `0.0` | Seconds to wait before showing (avoids showing UI if action is quick). | `1.0` |
| `SUPPRESS_NON_MATCHING_TEXT` | Boolean | `false` | Hide non-matching output lines in log (determinate modes only). | `<true/>` |


#### 1. `DETERMINATE_STEPS` – Fixed Text Matches
Matches fixed text in output to set progress percentages.

| Key | Type | Default | Description & Best Practices |
|-----|------|---------|------------------------------|
| `MATCH_METHOD` | String | `"match_contains"` | `"match_exact"`, `"match_contains"`, `"match_regular_expression"`. | `"match_regular_expression"` for flexibility |
| `COMPARE_CASE_INSENSITIVE` | Boolean | `false` | Ignore case in matches. | `<true/>` |
| `STEPS` | Array<Dict> | None | Steps array. Each dict: `STRING` (match text), `VALUE` (0-100 integer), `STATUS` (optional replacement text). | See example |

**Example**:
```xml
<key>PROGRESS</key>
<dict>
  <key>DETERMINATE_STEPS</key>
  <dict>
    <key>MATCH_METHOD</key>
    <string>match_contains</string>
    <key>COMPARE_CASE_INSENSITIVE</key>
    <false/>
    <key>SUPPRESS_NON_MATCHING_TEXT</key>
    <false/>
    <key>STEPS</key>
    <array>
      <dict>
        <key>STRING</key>
        <string>Starting</string>
        <key>VALUE</key>
        <integer>0</integer>
        <key>STATUS</key>
        <string>Initializing...</string>
      </dict>
      <dict>
        <key>STRING</key>
        <string>Processing</string>
        <key>VALUE</key>
        <integer>50</integer>
        <key>STATUS</key>
        <string>Halfway done</string>
      </dict>
      <dict>
        <key>STRING</key>
        <string>Finished</string>
        <key>VALUE</key>
        <integer>100</integer>
      </dict>
    </array>
  </dict>
</dict>
```

#### 2. `DETERMINATE_COUNTER` – Regex Counter
Extracts numeric counter from output via regex (e.g., "Task 3 of 10") and maps to progress.

| Key | Type | Default | Description & Best Practices |
|-----|------|---------|------------------------------|
| `REGULAR_EXPRESSION_MATCH` | String | None | Regex with subgroups for counter/range (e.g., `"Task (.+) of (.+)"`). | Use non-capturing groups if needed |
| `STATUS` | String | None | Replacement text with `$1`/`$2` for groups. | `"Progress: $1/$2"` |
| `SUBSTRING_INDEX_FOR_COUNTER` | Integer | 1 | Subgroup index for current value. | `1` (first capture) |
| `SUBSTRING_INDEX_FOR_RANGE_END` | Integer | 2 | Subgroup index for max value. | `2` |
| `SUBSTRING_INDEX_FOR_RANGE_START` | Integer | 0 | Subgroup index for min value (optional). | Omit for 0 start |
| `IS_COUNTDOWN` | Boolean | `false` | Treat as decreasing counter (end=0). | `<true/>` for timers |
| `RANGE_START` | Real | `0` | Progress min (ignored if subgroups used). | `0` |
| `RANGE_END` | Real | `100` | Progress max (ignored if subgroups used). | `100` |

**Example**:
```xml
<key>PROGRESS</key>
<dict>
  <key>DETERMINATE_COUNTER</key>
  <dict>
    <key>REGULAR_EXPRESSION_MATCH</key>
    <string>Task (.+) of (.+)</string>
    <key>STATUS</key>
    <string>Task $1 of $2 complete</string>
    <key>SUBSTRING_INDEX_FOR_COUNTER</key>
    <integer>1</integer>
    <key>SUBSTRING_INDEX_FOR_RANGE_END</key>
    <integer>2</integer>
    <key>IS_COUNTDOWN</key>
    <false/>
    <key>RANGE_START</key>
    <real>0</real>
    <key>RANGE_END</key>
    <real>100</real>
  </dict>
</dict>
```

**Notes**:
- Output must print matching lines for progress to update.
- Use with output-window modes for combined log + bar.
- `STATUS` localizable; supports `$N` placeholders.

---

#### 3. **Indeterminate (Default)**
- Indeterminate bar for single object.
- Advances per object if multiple objects are processed.
- Shows last output line as status.

**Example (Indeterminate)**:
```xml
<key>PROGRESS</key>
<dict>
  <key>TITLE</key>
  <string>Task in progress</string>
  <key>DELAY</key>
  <real>2.0</real>
</dict>
```

---

> ### Best Practices:
> - **Async Only**: Pair with async modes + `WAIT_FOR_TASK_COMPLETION=false`.
> - **Output Design**: Scripts should print exact match strings for reliable progress.
> - **User-Friendly**: Use `STATUS` for polished messages; suppress noise with `SUPPRESS_NON_MATCHING_TEXT=true`.
> - **NIB Alternative**: For interactive progress, use `omc_dialog_control` in custom NIBs

---


### 11. `INPUT_DIALOG` – User Input Prompt

Prompts **before** command runs. Value available via `$OMC_DLG_INPUT_TEXT`.

| Key | Type | Default | Description & Best Practices |
|-----|------|---------|------------------------------|
| `INPUT_TYPE` | String | `"text"` | `"text"`, `"password"`, `"popup"`, `"combo"`. | `"password"` for secure |
| `TITLE` | String | Command `NAME` | Dialog title. | `"Enter Value"` |
| `MESSAGE` | String | `""` | Prompt text. | `"Enter name:"` |
| `DEFAULT_VALUE` | String or Array<String> | `""` | Pre-filled value. Use array for dynamic. | `["User: ", __OBJ_NAME__]` |
| `INPUT_MENU` | Array<String> | None | Menu items for `popup`/`combo`. | `["Option 1", "Option 2"]` |

**Examples**:

**Text Input**:
```xml
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
```

**Password**:
```xml
<key>INPUT_DIALOG</key>
<dict>
  <key>INPUT_TYPE</key>
  <string>password</string>
  <key>MESSAGE</key>
  <string>Enter password:</string>
</dict>
```

**Popup Menu**:
```xml
<key>INPUT_DIALOG</key>
<dict>
  <key>INPUT_TYPE</key>
  <string>popup</string>
  <key>MESSAGE</key>
  <string>Select option:</string>
  <key>INPUT_MENU</key>
  <array>
    <string>Low</string>
    <string>Medium</string>
    <string>High</string>
  </array>
  <key>DEFAULT_VALUE</key>
  <string>Medium</string>
</dict>
```

**Notes**:
- `$OMC_DLG_INPUT_TEXT` returns:
  - Text/password: entered string
  - Popup/combo: selected item
- Use `__DLG_INPUT_TEXT__` in `COMMAND` for substitution.
- Dialog is **blocking**.
- `combo` allows typing; `popup` is dropdown only.

---

## Miscellaneous Command Description Options

These options handle advanced behaviors like multi-object processing, input piping, shell customization, command chaining, and escaping. They are placed directly in an command description dictionary.

---

### `MULTIPLE_OBJECT_SETTINGS` – Multi-Object Processing

Controls how multiple selected objects (files/folders) are handled. Defaults to separate execution per object.

| Key | Type | Default | Description & Best Practices |
|-----|------|---------|------------------------------|
| `PROCESSING_MODE` | String | `"proc_separately"` | `"proc_separately"` (run command per object) or `"proc_together"` (single run with composed paths). | `"proc_together"` for batch tools like `tar`. |
| `PREFIX` | String | `""` | Text before each path (e.g., `"`). | `"` for quoted paths. |
| `SUFFIX` | String | `""` | Text after each path (e.g., `"`). | `"` |
| `SEPARATOR` | String | `""` | Text between paths (e.g., space or `\n`). | `" "` for space-separated. |
| `SORT_METHOD` | String | `"sort_none"` | `"sort_none"` or `"sort_by_name"`. | `"sort_by_name"` for ordered input. |
| `SORT_OPTIONS` | Dict | `{}` | Sub-keys for sorting (if `SORT_METHOD` != none): `SORT_ASCENDING` (bool, default `true`), `COMPARE_CASE_INSENSITIVE` (bool, default `false`), `COMPARE_NONLITERAL` (bool, default `false`), `COMPARE_LOCALIZED` (bool, default `false`), `COMPARE_NUMERICAL` (bool, default `false`). | `{ "SORT_ASCENDING": <true/>, "COMPARE_CASE_INSENSITIVE": <true/> }` for Finder-like sort. |

**Example** (Batch quote and space-separate paths):
```xml
<key>MULTIPLE_OBJECT_SETTINGS</key>
<dict>
  <key>PROCESSING_MODE</key>
  <string>proc_together</string>
  <key>PREFIX</key>
  <string>"</string>
  <key>SUFFIX</key>
  <string>"</string>
  <key>SEPARATOR</key>
  <string> </string>
  <key>SORT_METHOD</key>
  <string>sort_by_name</string>
  <key>SORT_OPTIONS</key>
  <dict>
    <key>SORT_ASCENDING</key>
    <true/>
    <key>COMPARE_CASE_INSENSITIVE</key>
    <true/>
  </dict>
</dict>
<key>COMMAND</key>
<array>
  <string>ls -1</string>
</array>
```

**Notes**: Paths compose as `<PREFIX>path1<SUFFIX><SEPARATOR><PREFIX>path2<SUFFIX>`. Use with `act_file` for selections.

---

### `STANDARD_INPUT_PIPE` – Stdin Piping

Pipes context (e.g., text) to command stdin. Array of strings/special words (no env vars). Works only with popen modes (`exe_shell_script`, etc.).

| Key | Type | Default | Description & Best Practices |
|-----|------|---------|------------------------------|
| `STANDARD_INPUT_PIPE` | Array<String> | None | Content to pipe (e.g., `__OBJ_TEXT__`). | `["__OBJ_TEXT__"]` for selected text. |

**Related Keys**:
- `TEXT_REPLACE_OPTION` (String): `"txt_replace_none"` (default), `"txt_replace_cr_with_lf"`, etc., for line endings.

**Example** (Grep selected text):
```xml
<key>STANDARD_INPUT_PIPE</key>
<array>
  <string>__OBJ_TEXT__</string>
</array>
<key>TEXT_REPLACE_OPTION</key>
<string>txt_replace_cr_with_lf</string>
<key>COMMAND</key>
<array>
  <string>grep 'hello'</string>
</array>
<key>EXECUTION_MODE</key>
<string>exe_shell_script_with_output_window</string>
```

**Notes**: Avoids shell escaping; ideal for large/sensitive data. Command tool must read stdin.

---

### `POPEN_SHELL` – Custom Popen Shell

Overrides default shell (`/bin/sh -c <command>`) for popen modes like `exe_shell_script`

| Key | Type | Default | Description & Best Practices |
|-----|------|---------|------------------------------|
| `POPEN_SHELL` | Array<String> | `["/bin/sh", "-c"]` | Shell path + flags (command appended by OMC). | `["/bin/zsh", "-c"]` for zsh. |

**Example** (Use tcsh):
```xml
<key>POPEN_SHELL</key>
<array>
  <string>/bin/tcsh</string>
  <string>-c</string>
</array>
<key>COMMAND</key>
<array>
  <string>env</string>
</array>
<key>EXECUTION_MODE</key>
<string>exe_shell_script_with_output_window</string>
```

**Notes**: Useful for shells with better features (e.g., zsh arrays). Test for compatibility.

---

### `NEXT_COMMAND_ID` – Static Command Chaining

Unconditionally chains to another command on success (no cancel).

| Key | Type | Default | Description & Best Practices |
|-----|------|---------|------------------------------|
| `NEXT_COMMAND_ID` | String | None | ID of next command (overridden by dynamic `omc_next_command`). |

**Example**:
```xml
<key>NEXT_COMMAND_ID</key>
<string>post.process</string>
```

**Notes**: Use for fixed sequences; dynamic tool takes precedence. No env var export to next.

---

### `ESCAPE_SPECIAL_CHARS` – Special Char Escaping

Escapes inserted objects (paths/text) for safe execution. Applies only to inline objects in form of `__FOO__`. Not applied when exporting `OMC_FOO` environment variables.

| Key | Type | Default | Description & Best Practices |
|-----|------|---------|------------------------------|
| `ESCAPE_SPECIAL_CHARS` | String | `"esc_with_backslash"` | Options: `"esc_none"`, `"esc_with_backslash"` (backslash spaces/LF/CR), `"esc_with_percent"` (URL), `"esc_with_percent_all"` (full URL), `"esc_for_applescript"` (AS quotes), `"esc_wrap_with_single_quotes_for_shell"` (quoted shell). | `"esc_wrap_with_single_quotes_for_shell"` for complex paths. |

**Example** (Shell-quoted):
```xml
<key>ESCAPE_SPECIAL_CHARS</key>
<string>esc_wrap_with_single_quotes_for_shell</string>
<key>COMMAND</key>
<array>
  <string>ls</string>
  <string>__OBJ_PATH__</string>
</array>
```

**Notes**: `"esc_with_backslash"` default for inline paths/text objects. Avoid with quoted inserts. Use `"esc_for_applescript"` for AppleScript modes.

---

> ### Best Practices:
> - **Multi-Object**: Test composed paths in scripts; use sorting for consistency.
> - **Piping**: Prefer for text-heavy context objects and passwords or other secrets.
> - **Chaining**: Use static for simple flows.

---



## Related Documentation

The OMC project includes additional help files in the same directory as this reference. These documents cover companion tools and utilities shipped with the engine:

| File | Description |
|------|-------------|
| [`omc_controls_user_defined_runtime_attributes.md`](omc_controls_user_defined_runtime_attributes.md) | Guide to setting user-defined runtime attributes for OMC controls in Interface Builder. |
| [`plister--help.md`](plister--help.md) | Help for `plister`, a tool for reading and writing property lists. |
| [`pasteboard--help.md`](pasteboard--help.md) | Help for `pasteboard`, a command-line interface to the macOS pasteboard (clipboard). |
| [`omc_next_command--help.md`](omc_next_command--help.md) | Help for `omc_next_command`, used to chain execution to another action handler. |
| [`omc_dialog_control--help.md`](omc_dialog_control--help.md) | Full command reference for `omc_dialog_control` – manipulate dialog controls, tables, progress, etc. |
| [`notify--help.md`](notify--help.md) | Help for `notify`, sending user notifications via Notification Center. |
| [`loco--help.md`](loco--help.md) | Help for `loco`, a localization string extraction and management tool. |
| [`filt--help.md`](filt--help.md) | Help for `filt`, a text filtering and transformation utility. |
| [`b64--help.md`](b64--help.md) | Help for `b64`, base64 encoding/decoding from command line. |
| [`alert--help.md`](alert--help.md) | Help for `alert`, displaying modal alert dialogs. |

> **Note**: These files are located in the root of the [OMC GitHub repository](https://github.com/abra-code/OMC/tree/master).

---


## Example Full Applets:

[Find.app](https://github.com/abra-code/FindApp)<br>
[Delta.app](https://github.com/abra-code/DeltaApp)<br>
[Xattr.app](https://github.com/abra-code/XattrApp)<br>
[AIChat.app](https://github.com/abra-code/AIChatApp)<br>

---


