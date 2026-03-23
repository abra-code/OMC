# OMC Shell Scripting Guide

Shell scripts are the most common way to implement action handlers in OMC applets. A script runs in response to a user interaction — a button click, table selection, dialog result, or file drop — and can read input, update UI controls, and chain to other commands.

## Typical Script Flow

A typical script looks something like this:

```bash
#!/bin/bash
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.myapp.sh"

# Read inputs from environment variables or state files
# Validate
# Do work
# Update UI
# Chain to next command or exit
```

## Shared Library

You may want to create a shared library file (e.g. `lib.myapp.sh`) and source it at the beginning of your other scripts. This is useful because it gives you a single place to define tool paths, control ID constants, and reusable helper functions — so you don't repeat yourself across dozens of scripts.

```bash
# lib.myapp.sh

# Tool paths — defined once, used everywhere
dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
next_cmd="$OMC_OMC_SUPPORT_PATH/omc_next_command"
pasteboard_tool="$OMC_OMC_SUPPORT_PATH/pasteboard"
alert_tool="$OMC_OMC_SUPPORT_PATH/alert"

# Window context
window_uuid="$OMC_ACTIONUI_WINDOW_UUID"
cmd_guid="$OMC_CURRENT_COMMAND_GUID"

# Control IDs — giving names to numbers makes scripts readable
NAME_FIELD_ID=101
STATUS_TEXT_ID=102
SAVE_BTN_ID=103
TABLE_ID=110
```

## Reading Control Values

When a script runs, OMC exports control values as environment variables. The naming pattern depends on the UI type:

| Pattern | Source |
|---------|--------|
| `$OMC_ACTIONUI_VIEW_{ID}_VALUE` | ActionUI text field, picker, toggle, etc. |
| `$OMC_ACTIONUI_TABLE_{ID}_COLUMN_{N}_VALUE` | ActionUI table column (1-based; column 0 = all columns combined) |
| `$OMC_NIB_DIALOG_CONTROL_{ID}_VALUE` | Nib dialog control by tag |
| `$OMC_DLG_CHOOSE_OBJECT_PATH` | File/folder chooser dialog result |
| `$OMC_DLG_SAVE_AS_PATH` | Save-as dialog result |
| `$OMC_OBJ_PATH` | Input object path (file drop, contextual menu) |

```bash
# ActionUI text field
name="${OMC_ACTIONUI_VIEW_101_VALUE}"

# ActionUI table — hidden column with file path
selected_path="$OMC_ACTIONUI_TABLE_110_COLUMN_2_VALUE"

# Nib checkbox (1=on, 0=off)
is_recursive="${OMC_NIB_DIALOG_CONTROL_2_VALUE}"

# File chooser result
chosen_file="$OMC_DLG_CHOOSE_OBJECT_PATH"
```

## Updating UI Controls

The `omc_dialog_control` tool lets you set values, enable/disable controls, show/hide elements, and more. It is helpful to wrap common operations in functions:

```bash
set_value() {
    "$dialog_tool" "$window_uuid" "$1" "$2"
}

set_enabled() {
    local view_id="$1"
    if [ "$2" = "true" ]; then
        "$dialog_tool" "$window_uuid" "$view_id" omc_enable
    else
        "$dialog_tool" "$window_uuid" "$view_id" omc_disable
    fi
}

set_visible() {
    local view_id="$1"
    if [ "$2" = "true" ]; then
        "$dialog_tool" "$window_uuid" "$view_id" omc_show
    else
        "$dialog_tool" "$window_uuid" "$view_id" omc_hide
    fi
}
```

Then in your scripts:

```bash
set_value "$STATUS_TEXT_ID" "File saved"
set_enabled "$SAVE_BTN_ID" false
set_visible "$DETAIL_ROW_ID" true
```

You can also set ActionUI properties dynamically:

```bash
"$dialog_tool" "$window_uuid" "$PICKER_ID" omc_set_property "options" '["Option A","Option B"]'
```

## Populating Tables

Tables expect tab-separated rows. A common approach is to build a buffer string and pipe it to the table via stdin. A hidden column is handy for storing data (like file paths or indices) that the user doesn't need to see:

```bash
refresh_table() {
    local buffer=""
    for file in "$scripts_dir"/*; do
        [ ! -f "$file" ] && continue
        local name=$(/usr/bin/basename "$file")
        buffer="${buffer}${name}\t${file}\n"
    done
    printf "%s" "$buffer" | "$dialog_tool" "$window_uuid" "$TABLE_ID" omc_table_set_rows_from_stdin
}
```

To clear a table before repopulating:

```bash
"$dialog_tool" "$window_uuid" "$TABLE_ID" omc_table_remove_all_rows
```

To add rows incrementally (e.g. as events arrive):

```bash
echo "${row_data}" | "$dialog_tool" "$window_uuid" "$TABLE_ID" omc_table_add_rows_from_stdin
```

## State Management

Scripts in OMC are short-lived processes — each invocation starts fresh. If you need to share state between scripts (e.g. remembering which file is selected), a simple approach is to write to files in a temp directory keyed by window UUID:

```bash
state_dir="/tmp/myapp_${OMC_ACTIONUI_WINDOW_UUID}"

get_state_dir() {
    /bin/mkdir -p "$state_dir"
    echo "$state_dir"
}

# Save
echo "$project_path" > "$(get_state_dir)/project_path"

# Read
project_path=$(cat "$(get_state_dir)/project_path" 2>/dev/null)
```

Each window instance gets its own directory, so multiple windows don't interfere. The `/tmp/` location means it cleans up on reboot.

For persistent user preferences that survive reboots, `defaults` works well:

```bash
prefs_domain="com.mycompany.myapp"

get_preference() {
    /usr/bin/defaults read "$prefs_domain" "$1" 2>/dev/null
}

save_preference() {
    /usr/bin/defaults write "$prefs_domain" "$1" "$2"
}
```

## Cross-Window Communication

When one window needs to pass data to another (e.g. a main window opening a child dialog), the pasteboard tool is useful. Keying by window UUID avoids collisions:

```bash
# Parent window: store data before opening child dialog
"$pasteboard_tool" "ProjectPath_${OMC_ACTIONUI_WINDOW_UUID}" set "$project_path"
"$next_cmd" "$cmd_guid" "MyApp.child.dialog"

# Child window init script: read parent's data
parent_uuid="$OMC_PARENT_DIALOG_GUID"
project_path=$("$pasteboard_tool" "ProjectPath_${parent_uuid}" get)
"$pasteboard_tool" "ProjectPath_${parent_uuid}" set ""  # clean up
```

## Chaining Commands

`omc_next_command` schedules another command to run after the current script finishes. This is how you open dialogs, trigger table refreshes in parent windows, or run multi-step workflows:

```bash
"$next_cmd" "$cmd_guid" "MyApp.next.action"
```

## Validation and User Feedback

It is good practice to validate inputs early and give the user clear feedback. There are a few levels of feedback you can use depending on the situation:

**Inline status** — for quick hints and non-blocking messages:
```bash
if [ -z "$name" ]; then
    set_value "$STATUS_TEXT_ID" "Name is required"
    exit 1
fi
```

**Alert dialog** — for confirmations or errors that need attention:
```bash
if [ -f "$target_file" ]; then
    "$alert_tool" --level critical --title "MyApp" \
        --ok "OK" "File \"$name\" already exists."
    exit 1
fi
```

**Output window** — for detailed multi-line output (error logs, build results). Set up a command with `EXECUTION_MODE=exe_script_file_with_output_window` in Command.plist.

## Handling Table Selection

A common pattern is to enable/disable action buttons based on whether something is selected, and load detail content:

```bash
selected="$OMC_ACTIONUI_TABLE_110_COLUMN_2_VALUE"

if [ -z "$selected" ]; then
    set_enabled "$EDIT_BTN_ID" false
    set_enabled "$REMOVE_BTN_ID" false
    set_value "$DETAIL_ID" ""
    exit 0
fi

# Remember selection for other scripts
echo "$selected" > "$(get_state_dir)/selected_path"

set_enabled "$EDIT_BTN_ID" true
set_enabled "$REMOVE_BTN_ID" true

content=$(/bin/cat "$selected")
set_value "$DETAIL_ID" "$content"
```

## Initialization Scripts

When a dialog opens, OMC runs the command specified by `INIT_SUBCOMMAND_ID`. This is a good place to populate fields, set up table columns, and load initial data:

```bash
#!/bin/bash
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.myapp.sh"

# Read data passed from parent
parent_uuid="$OMC_PARENT_DIALOG_GUID"
project_path=$("$pasteboard_tool" "ProjectPath_${parent_uuid}" get)
"$pasteboard_tool" "ProjectPath_${parent_uuid}" set ""

# Populate fields
set_value "$NAME_FIELD_ID" "$default_name"

# Set up a picker dynamically
"$dialog_tool" "$window_uuid" "$TYPE_PICKER_ID" omc_set_property "options" '["Option A","Option B"]'

# Load table data
refresh_table "$data_dir"
```

## Working with Plist Files

`plutil` handles validation and simple reads. For deeper access, `plister` (bundled with OMC) can navigate plist paths:

```bash
# Validate
/usr/bin/plutil -lint "$plist_file" > /dev/null 2>&1 || { echo "Invalid plist"; exit 1; }

# Read a value
value=$(/usr/bin/plutil -extract "KEY_NAME" raw "$plist_file" 2>/dev/null)

# Read nested values with plister
plister="$OMC_OMC_SUPPORT_PATH/plister"
count=$("$plister" get count "$plist_file" /COMMAND_LIST 2>/dev/null)
cmd_id=$("$plister" get value "$plist_file" "/COMMAND_LIST/0/COMMAND_ID" 2>/dev/null)
```

For complex edits, converting to JSON and back can be easier than editing XML directly:

```bash
temp=$(/usr/bin/mktemp /tmp/edit_XXXXXX.json)
/usr/bin/plutil -convert json -o "$temp" "$plist_file"
# ... edit $temp ...
/usr/bin/plutil -convert xml1 -o "$plist_file" "$temp"
/bin/rm -f "$temp"
```

## Naming Conventions

Script files follow the pattern `AppName.area.action.sh`, matching the `COMMAND_ID` in Command.plist (prefixed by `NAME`):

| File | COMMAND_ID |
|------|-----------|
| `MyApp.project.init.sh` | `MyApp.project.init` |
| `MyApp.files.save.detail.sh` | `MyApp.files.save.detail` |
| `MyApp.settings.browse.editor.sh` | `MyApp.settings.browse.editor` |
| `lib.myapp.sh` | *(shared library, not a command)* |

## Debugging

A few approaches that can help when things aren't working as expected:

- **Dump environment**: `env | sort > /tmp/debug_env.txt` — shows all variables OMC exports for your script
- **Output window**: temporarily change `EXECUTION_MODE` to `exe_script_file_with_output_window` to see stdout/stderr. Or hold the Control key when triggering the command.
- **Manual testing**: run `omc_dialog_control` from Terminal with the window UUID to test commands interactively
- **Log file**: `echo "checkpoint reached" >> /tmp/myapp_debug.log`

## Related Documentation

- [Python Scripting Guide](omc_python_scripting_guide.md) — Python-specific patterns for OMC applets
- [OMC Command Reference](omc_command_reference.md) — Command.plist format and all configuration keys
- [OMC Runtime Context Reference](omc_runtime_context_reference.md) — All environment variables and special words
- [omc_dialog_control](omc_dialog_control--help.md) — Full command reference for UI manipulation
- [omc_next_command](omc_next_command--help.md) — Command chaining
- [pasteboard](pasteboard--help.md) — Pasteboard tool for data passing
- [plister](plister--help.md) — Plist reading/writing tool
- [alert](alert--help.md) — Alert dialog tool
