---
id: env-tools
level: 1
flavors: [claude, capable, lite]
---

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

### Other support tools (full usage in `docs/<tool>--help.md`)

| Tool | Purpose | Typical call |
|------|---------|--------------|
| `alert` | Modal alert; choice returned via **exit code** (0=OK, 1=Cancel) | `alert --level caution --ok "Go" --cancel "Cancel" "Sure?"` |
| `pasteboard` | Cross-script key-value store; prefix keys with app name + window UUID | `pasteboard my_key set "v"` / `pasteboard my_key get` |
| `notify` | macOS notification | `notify --title "MyApp" "Done."` |
| `plister` | Plist read/write (for complex edits: `plutil -convert json` → edit → `xml1`) | `plister get value "$plist" /COMMAND_LIST/0/NAME` |
