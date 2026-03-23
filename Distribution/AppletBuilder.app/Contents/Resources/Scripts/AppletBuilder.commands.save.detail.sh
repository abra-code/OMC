#!/bin/bash
# Save edited command XML back to Command.plist

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
cmd_plist="$project_path/Contents/Resources/Command.plist"

cmd_index=$(pb_get "$PB_CMD_SELECTED")

if [ -z "$cmd_index" ] || [ ! -f "$cmd_plist" ]; then
    set_value "$CMD_EDITED_LABEL_ID" "Error: no command selected"
    exit 1
fi

edited_xml="${OMC_ACTIONUI_VIEW_502_VALUE}"
if [ -z "$edited_xml" ]; then
    set_value "$CMD_EDITED_LABEL_ID" "Error: empty content"
    exit 1
fi

# Wrap the dict fragment in a plist envelope for validation and JSON conversion
temp_plist=$(/usr/bin/mktemp /tmp/appletbuilder_cmd.XXXXXX.plist)
cat > "$temp_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
${edited_xml}
</plist>
EOF

# Validate the XML is a valid plist
if ! /usr/bin/plutil -lint "$temp_plist" > /dev/null 2>&1; then
    set_value "$CMD_EDITED_LABEL_ID" "Error: invalid plist XML"
    /bin/rm -f "$temp_plist"
    exit 1
fi

# Convert edited dict to JSON
temp_json=$(/usr/bin/mktemp /tmp/appletbuilder_cmd.XXXXXX.json)
/usr/bin/plutil -convert json -o "$temp_json" "$temp_plist"
/bin/rm -f "$temp_plist"

# Replace the command entry via JSON round-trip
plist_edit "$cmd_plist" replace_command "$cmd_index" "$temp_json"
result=$?
/bin/rm -f "$temp_json"

if [ "$result" -eq 0 ]; then
    set_enabled "$CMD_SAVE_BTN_ID" false
    set_value "$CMD_EDITED_LABEL_ID" "✅ Saved"
    "$next_cmd" "${OMC_CURRENT_COMMAND_GUID}" "AppletBuilder.commands.loaded"
else
    set_value "$CMD_EDITED_LABEL_ID" "Error: failed to save"
fi
