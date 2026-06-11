#!/bin/bash
# Save the edited command (JSON object or plist XML fragment) back to the
# project's command file (Command.json or Command.plist).

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.plist.sh"

project_path=$(load_project_path)
cmd_plist=$(command_file_path "$project_path")

cmd_index=$(pb_get "$PB_CMD_SELECTED")

if [ -z "$cmd_index" ] || [ ! -f "$cmd_plist" ]; then
    set_value "$CMD_EDITED_LABEL_ID" "Error: no command selected"
    exit 1
fi

edited_text="${OMC_ACTIONUI_VIEW_502_VALUE}"
if [ -z "$edited_text" ]; then
    set_value "$CMD_EDITED_LABEL_ID" "Error: empty content"
    exit 1
fi

check_file_modified "$cmd_plist" "$PB_CMD_HASH"
case $? in
    1)  # Reload from Disk — re-extract the command at the selected index
        if is_json_command_file "$cmd_plist"; then
            cmd_text=$(/usr/bin/plutil -extract "COMMAND_LIST.$cmd_index" json -o - "$cmd_plist" 2>/dev/null \
                | "$python3" -m json.tool)
        else
            cmd_text=$(/usr/bin/plutil -extract "COMMAND_LIST.$cmd_index" xml1 -o - "$cmd_plist" 2>/dev/null \
                | /usr/bin/sed '1,3d; $d')
        fi
        set_value "$CMD_DETAIL_ID" "$cmd_text
"
        pb_set "$PB_CMD_HASH" "$(file_hash "$cmd_plist")"
        pb_set "$PB_CMD_DIRTY" ""
        set_enabled "$CMD_SAVE_BTN_ID" false
        set_value "$CMD_EDITED_LABEL_ID" "Reloaded from disk"
        "$next_cmd" "${OMC_CURRENT_COMMAND_GUID}" "AppletBuilder.commands.loaded"
        exit 0
        ;;
    2)  # Cancel
        exit 0
        ;;
esac

# Build a JSON file holding the edited command dict (plist_edit's replace_command
# takes a JSON file). For a JSON command file the edited text is already JSON; for
# a plist it is an XML dict fragment that we wrap, lint, and convert.
temp_json=$(/usr/bin/mktemp /tmp/appletbuilder_cmd.XXXXXX.json)

if is_json_command_file "$cmd_plist"; then
    printf '%s' "$edited_text" > "$temp_json"
    if ! "$python3" -m json.tool "$temp_json" > /dev/null 2>&1; then
        set_value "$CMD_EDITED_LABEL_ID" "Error: invalid JSON"
        /bin/rm -f "$temp_json"
        exit 1
    fi
else
    # Wrap the dict fragment in a plist envelope for validation and JSON conversion
    temp_plist=$(/usr/bin/mktemp /tmp/appletbuilder_cmd.XXXXXX.plist)
    cat > "$temp_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
${edited_text}
</plist>
EOF

    # Validate the XML is a valid plist
    if ! /usr/bin/plutil -lint "$temp_plist" > /dev/null 2>&1; then
        set_value "$CMD_EDITED_LABEL_ID" "Error: invalid plist XML"
        /bin/rm -f "$temp_plist" "$temp_json"
        exit 1
    fi

    # Convert edited dict to JSON
    /usr/bin/plutil -convert json -o "$temp_json" "$temp_plist"
    /bin/rm -f "$temp_plist"
fi

# Replace the command entry (plist_edit handles json/plist output format)
plist_edit "$cmd_plist" replace_command "$cmd_index" "$temp_json"
result=$?
/bin/rm -f "$temp_json"

if [ "$result" -eq 0 ]; then
    pb_set "$PB_CMD_HASH" "$(file_hash "$cmd_plist")"
    pb_set "$PB_CMD_DIRTY" ""
    set_enabled "$CMD_SAVE_BTN_ID" false
    set_value "$CMD_EDITED_LABEL_ID" "✅ Saved"
    "$next_cmd" "${OMC_CURRENT_COMMAND_GUID}" "AppletBuilder.commands.loaded"
else
    set_value "$CMD_EDITED_LABEL_ID" "Error: failed to save"
fi
