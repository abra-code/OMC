#!/bin/bash
# AppletBuilder.services.remove - Remove selected NSService from Info.plist

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
plist="$project_path/Contents/Info.plist"

svc_index="$OMC_ACTIONUI_TABLE_330_COLUMN_2_VALUE"
svc_label="$OMC_ACTIONUI_TABLE_330_COLUMN_1_VALUE"

if [ -z "$svc_index" ] || [ ! -f "$plist" ]; then
    exit 0
fi

# Confirm
alert_tool="$OMC_OMC_SUPPORT_PATH/alert"
"$alert_tool" --level caution --title "AppletBuilder" \
    --ok "Remove" --cancel "Cancel" \
    "Remove service \"${svc_label}\"?"
result=$?
if [ "$result" -ne 0 ]; then
    exit 0
fi

plist_edit "$plist" remove_service "$svc_index"

# Clear detail fields
set_enabled "$SVC_REMOVE_BTN_ID" false
set_enabled "$SVC_MENU_TITLE_ID" false
set_enabled "$SVC_COMMAND_PICKER_ID" false
set_enabled "$SVC_INPUT_PICKER_ID" false
set_value "$SVC_MENU_TITLE_ID" ""
set_value "$SVC_STATUS_ID" "Service removed"

# Clear selected index
state_dir=$(get_state_dir)
/bin/rm -f "$state_dir/svc_selected_index"

# Reload services table
"$next_cmd" "${OMC_CURRENT_COMMAND_GUID}" "AppletBuilder.services.reload"
