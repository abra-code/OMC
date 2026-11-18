#!/bin/bash
# AppletBuilder.commands.loaded - Populate the Commands table from the project's command file

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.tables.sh"

project_path=$(load_project_path)
cmd_plist=$(command_file_path "$project_path")

if [ ! -f "$cmd_plist" ]; then
    set_value "$CMD_DETAIL_ID" "No command file found"
    exit 0
fi

refresh_commands_table "$cmd_plist"
