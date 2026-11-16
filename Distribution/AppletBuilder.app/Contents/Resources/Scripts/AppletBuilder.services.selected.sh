#!/bin/bash
# AppletBuilder.services.selected - Show selected service details

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.plist.sh"

# Get selected index from hidden column 2
svc_index="$OMC_ACTIONUI_TABLE_330_COLUMN_2_VALUE"

if [ -z "$svc_index" ]; then
    set_enabled "$SVC_REMOVE_BTN_ID" false
    set_enabled "$SVC_MENU_TITLE_ID" false
    set_enabled "$SVC_COMMAND_PICKER_ID" false
    set_enabled "$SVC_INPUT_PICKER_ID" false
    set_value "$SVC_MENU_TITLE_ID" ""
    set_value "$SVC_STATUS_ID" ""
    exit 0
fi

project_path=$(load_project_path)
plist="$project_path/Contents/Info.plist"

if [ ! -f "$plist" ]; then
    exit 0
fi

# Store selected index for save/remove
pb_set "$PB_SVC_SELECTED" "$svc_index"

# Enable editing controls
set_enabled "$SVC_REMOVE_BTN_ID" true
set_enabled "$SVC_MENU_TITLE_ID" true
set_enabled "$SVC_COMMAND_PICKER_ID" true
set_enabled "$SVC_INPUT_PICKER_ID" true
set_value "$SVC_STATUS_ID" ""

# Read service details
menu_title=$(/usr/bin/plutil -extract "NSServices.${svc_index}.NSMenuItem.default" raw "$plist" 2>/dev/null)
user_data=$(/usr/bin/plutil -extract "NSServices.${svc_index}.NSUserData" raw "$plist" 2>/dev/null)
# The Input kind by the rule update_service compares a save with (lib.plist.sh): files, folders,
# text, or other (types the pane cannot write, which a save keeps)
input_kind="$(info_plist_service_kind "$plist" "$svc_index")"

# Populate fields
set_value "$SVC_MENU_TITLE_ID" "$menu_title"
set_value "$SVC_COMMAND_PICKER_ID" "$user_data"
set_value "$SVC_INPUT_PICKER_ID" "$input_kind"

if [ "$input_kind" = "other" ]; then
    set_value "$SVC_STATUS_ID" "Input: the types this service declares, kept as they are"
fi
