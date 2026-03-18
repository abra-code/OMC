#!/bin/bash
# AppletBuilder.services.add - Add a new NSService entry to Info.plist

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
plist="$project_path/Contents/Info.plist"

if [ ! -f "$plist" ]; then
    set_value "$SVC_STATUS_ID" "No Info.plist found"
    exit 1
fi

# Get the first available command ID for default
cmd_plist="$project_path/Contents/Resources/Command.plist"
plister="$OMC_OMC_SUPPORT_PATH/plister"
default_cmd=""
if [ -f "$cmd_plist" ]; then
    default_cmd=$("$plister" get value "$cmd_plist" "/COMMAND_LIST/0/COMMAND_ID" 2>/dev/null)
    if [ -z "$default_cmd" ]; then
        default_cmd=$("$plister" get value "$cmd_plist" "/COMMAND_LIST/0/NAME" 2>/dev/null | /usr/bin/tr -d '\n')
    fi
fi

if [ -z "$default_cmd" ]; then
    set_value "$SVC_STATUS_ID" "Add commands first"
    exit 1
fi

app_name=$(plist_read "$plist" CFBundleName)
menu_title="${app_name:-New Service}"

plist_edit "$plist" append_service "$menu_title" "$default_cmd"

if [ $? -eq 0 ]; then
    set_value "$SVC_STATUS_ID" "Service added"
    "$next_cmd" "${OMC_CURRENT_COMMAND_GUID}" "AppletBuilder.services.reload"
else
    set_value "$SVC_STATUS_ID" "Error adding service"
fi
