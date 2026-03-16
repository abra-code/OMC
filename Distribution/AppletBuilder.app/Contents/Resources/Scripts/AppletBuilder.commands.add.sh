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

# Get current count to determine new index
count=$(/usr/bin/plutil -extract COMMAND_LIST raw "$cmd_plist" 2>/dev/null)
if [ -z "$count" ]; then
    count=0
fi

# Insert a new command template dict at the end of the array
/usr/bin/plutil -insert "COMMAND_LIST.$count" -dictionary "$cmd_plist" 2>/dev/null
/usr/bin/plutil -insert "COMMAND_LIST.$count.NAME" -string "$app_name" "$cmd_plist" 2>/dev/null
/usr/bin/plutil -insert "COMMAND_LIST.$count.COMMAND_ID" -string "$app_name.new.command" "$cmd_plist" 2>/dev/null
/usr/bin/plutil -insert "COMMAND_LIST.$count.EXECUTION_MODE" -string "exe_script_file" "$cmd_plist" 2>/dev/null

# Refresh the commands table
"$OMC_OMC_SUPPORT_PATH/omc_next_command" "${OMC_CURRENT_COMMAND_GUID}" "AppletBuilder.commands.loaded"
