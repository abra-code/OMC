#!/bin/bash
# AppletBuilder.uifiles.remove - Remove selected UI file

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

# Get selected path from hidden column 2
selected_path="$OMC_ACTIONUI_TABLE_701_COLUMN_2_VALUE"
selected_name="$OMC_ACTIONUI_TABLE_701_COLUMN_1_VALUE"

if [ -z "$selected_path" ]; then
    exit 0
fi

# Confirm before deleting
alert_tool="$OMC_OMC_SUPPORT_PATH/alert"
"$alert_tool" --level caution --title "AppletBuilder" \
    --ok "Delete" --cancel "Cancel" \
    "Delete \"${selected_name}\"? This cannot be undone."
result=$?
if [ "$result" -ne 0 ]; then
    exit 0
fi

if [ -d "$selected_path" ]; then
    # It's a .nib bundle
    /bin/rm -rf "$selected_path"
elif [ -f "$selected_path" ]; then
    /bin/rm "$selected_path"
fi

# Disable buttons
set_enabled "$UI_REMOVE_BTN_ID" false
set_enabled "$UI_EDIT_BTN_ID" false
set_enabled "$UI_REVEAL_BTN_ID" false
set_value "$UI_DETAIL_ID" ""

# Refresh the UI files table
"$OMC_OMC_SUPPORT_PATH/omc_next_command" "${OMC_CURRENT_COMMAND_GUID}" "AppletBuilder.uifiles.loaded"
