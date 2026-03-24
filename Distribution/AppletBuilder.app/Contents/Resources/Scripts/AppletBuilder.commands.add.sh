#!/bin/bash
# AppletBuilder.commands.add - Open the New Command dialog

# echo "[$(/usr/bin/basename "$0")]"
# env | sort

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
cmd_plist="$project_path/Contents/Resources/Command.plist"

if [ ! -f "$cmd_plist" ]; then
    set_value "$CMD_DETAIL_ID" "No Command.plist found"
    exit 0
fi

# Pass project path to the new dialog via pasteboard keyed by our dialog UUID
# Subcommands of the new dialog will access this using OMC_PARENT_DIALOG_GUID
"$pasteboard_tool" "ProjectPath_${OMC_ACTIONUI_WINDOW_UUID}" set "$project_path"

# Open the New Command dialog (the init subcommand will populate defaults)
"$next_cmd" "$cmd_guid" "AppletBuilder.commands.new.dialog"
