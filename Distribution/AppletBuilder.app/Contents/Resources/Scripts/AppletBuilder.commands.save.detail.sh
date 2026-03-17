#!/bin/bash
# Save edited command XML back to Command.plist

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
cmd_plist="$project_path/Contents/Resources/Command.plist"

state_dir=$(get_state_dir)
cmd_index=$(cat "$state_dir/cmd_selected_index" 2>/dev/null)

if [ -z "$cmd_index" ] || [ ! -f "$cmd_plist" ]; then
    set_value "$CMD_EDITED_LABEL_ID" "Error: no command selected"
    exit 1
fi

edited_xml="${OMC_ACTIONUI_VIEW_502_VALUE}"
if [ -z "$edited_xml" ]; then
    set_value "$CMD_EDITED_LABEL_ID" "Error: empty content"
    exit 1
fi

# Write edited XML to a temp file, convert to plist, then replace the command entry
temp_file=$(/usr/bin/mktemp /tmp/appletbuilder_cmd.XXXXXX)
cat > "$temp_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
${edited_xml}
</plist>
EOF

# Validate the XML is a valid plist
if ! /usr/bin/plutil -lint "$temp_file" > /dev/null 2>&1; then
    set_value "$CMD_EDITED_LABEL_ID" "Error: invalid plist XML"
    /bin/rm -f "$temp_file"
    exit 1
fi

# Replace the command entry in the plist
/usr/bin/plutil -replace "COMMAND_LIST.$cmd_index" -xml "$temp_file" "$cmd_plist" 2>/dev/null
result=$?
/bin/rm -f "$temp_file"

if [ "$result" -eq 0 ]; then
    set_enabled "$CMD_SAVE_BTN_ID" false
    set_value "$CMD_EDITED_LABEL_ID" "Saved"
else
    set_value "$CMD_EDITED_LABEL_ID" "Error: failed to save"
fi
