---
id: script-patterns
level: 2
flavors: [claude, capable]
---

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
