#!/bin/bash
# AppletBuilder.commands.selected - Show selected command details and enable buttons

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
cmd_plist="$project_path/Contents/Resources/Command.plist"

# Get selected command index from hidden column 2
cmd_index="$OMC_ACTIONUI_TABLE_501_COLUMN_2_VALUE"

if [ -z "$cmd_index" ]; then
    # No selection — disable buttons, clear detail
    set_enabled "$CMD_REMOVE_BTN_ID" false
    set_enabled "$CMD_REVEAL_BTN_ID" false
    set_enabled "$CMD_VALIDATE_BTN_ID" false
    set_enabled "$CMD_SAVE_BTN_ID" false
    set_value "$CMD_DETAIL_ID" ""
    set_value "$CMD_EDITED_LABEL_ID" ""
    exit 0
fi

# Enable action buttons
set_enabled "$CMD_REMOVE_BTN_ID" true
set_enabled "$CMD_REVEAL_BTN_ID" true
set_enabled "$CMD_VALIDATE_BTN_ID" true
# Save starts disabled until text is edited
set_enabled "$CMD_SAVE_BTN_ID" false
set_value "$CMD_EDITED_LABEL_ID" ""
pb_set "$PB_CMD_DIRTY" ""

if [ ! -f "$cmd_plist" ]; then
    exit 0
fi

# Store selected index for save/validate handlers
pb_set "$PB_CMD_SELECTED" "$cmd_index"

# Store hash of Command.plist for external modification detection
pb_set "$PB_CMD_HASH" "$(file_hash "$cmd_plist")"

# Extract the command dict as XML fragment, stripping the plist wrapper
# (xml declaration, DOCTYPE, <plist> header and </plist> footer)
# so the user sees and edits only the <dict>...</dict> content
cmd_xml=$(/usr/bin/plutil -extract "COMMAND_LIST.$cmd_index" xml1 -o - "$cmd_plist" 2>/dev/null \
    | /usr/bin/sed '1,3d; $d')
set_value "$CMD_DETAIL_ID" "$cmd_xml
"
