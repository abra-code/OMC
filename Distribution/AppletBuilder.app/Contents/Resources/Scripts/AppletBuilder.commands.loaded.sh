#!/bin/bash
# AppletBuilder.commands.loaded - Populate Commands table from Command.plist

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.tables.sh"

project_path=$(load_project_path)
cmd_plist=$(command_file_path "$project_path")

if [ ! -f "$cmd_plist" ]; then
    set_value "$CMD_DETAIL_ID" "No Command.plist found"
    exit 0
fi

refresh_commands_table "$cmd_plist"
