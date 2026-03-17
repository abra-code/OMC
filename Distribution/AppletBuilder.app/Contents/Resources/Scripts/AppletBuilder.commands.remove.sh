#!/bin/bash
# AppletBuilder.commands.remove - Remove selected command from Command.plist

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
cmd_plist="$project_path/Contents/Resources/Command.plist"

# Get selected command index from hidden column 2
cmd_index="$OMC_ACTIONUI_TABLE_501_COLUMN_2_VALUE"
cmd_label="$OMC_ACTIONUI_TABLE_501_COLUMN_1_VALUE"

if [ -z "$cmd_index" ] || [ ! -f "$cmd_plist" ]; then
    exit 0
fi

# Confirm before removing
alert_tool="$OMC_OMC_SUPPORT_PATH/alert"
"$alert_tool" --level caution --title "AppletBuilder" \
    --ok "Remove" --cancel "Cancel" \
    "Remove command \"${cmd_label}\" from Command.plist? This cannot be undone."
result=$?
if [ "$result" -ne 0 ]; then
    exit 0
fi

# Remove the command at the given index
/usr/bin/plutil -remove "COMMAND_LIST.$cmd_index" "$cmd_plist" 2>/dev/null

# Disable buttons (no selection after removal)
set_enabled "$CMD_REMOVE_BTN_ID" false
set_enabled "$CMD_REVEAL_BTN_ID" false
set_enabled "$CMD_VALIDATE_BTN_ID" false
set_enabled "$CMD_SAVE_BTN_ID" false
set_enabled "$CMD_EXT_EDIT_BTN_ID" false
set_value "$CMD_DETAIL_ID" ""
set_value "$CMD_EDITED_LABEL_ID" ""

# Refresh the commands table
"$OMC_OMC_SUPPORT_PATH/omc_next_command" "${OMC_CURRENT_COMMAND_GUID}" "AppletBuilder.commands.loaded"
