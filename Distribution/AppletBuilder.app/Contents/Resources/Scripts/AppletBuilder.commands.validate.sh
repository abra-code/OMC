#!/bin/bash
# Validate Command.plist with plutil

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
cmd_plist="$project_path/Contents/Resources/Command.plist"

if [ ! -f "$cmd_plist" ]; then
    set_value "$CMD_EDITED_LABEL_ID" "No Command.plist found"
    exit 0
fi

result=$(/usr/bin/plutil -lint "$cmd_plist" 2>&1)
if [ "$?" -eq 0 ]; then
    set_value "$CMD_EDITED_LABEL_ID" "Valid plist"
else
    set_value "$CMD_EDITED_LABEL_ID" "Invalid plist"
    show_errors "Plist validation error in Command.plist:

$result"
fi
