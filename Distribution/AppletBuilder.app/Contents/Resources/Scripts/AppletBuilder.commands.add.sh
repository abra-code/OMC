#!/bin/bash
# AppletBuilder.commands.add - Add a new command entry to Command.plist

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
cmd_plist="$project_path/Contents/Resources/Command.plist"
app_name=$(/usr/bin/basename "${project_path%.app}")

if [ ! -f "$cmd_plist" ]; then
    set_value "$CMD_DETAIL_ID" "No Command.plist found"
    exit 0
fi

plist_edit "$cmd_plist" append_command "$app_name"

# Refresh the commands table
"$OMC_OMC_SUPPORT_PATH/omc_next_command" "${OMC_CURRENT_COMMAND_GUID}" "AppletBuilder.commands.loaded"
