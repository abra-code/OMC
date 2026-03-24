#!/bin/bash

# echo "[$(/usr/bin/basename "$0")]"
# env | sort

# Main command: detect context and dispatch to the appropriate window
next_cmd="$OMC_OMC_SUPPORT_PATH/omc_next_command"
pasteboard_tool="$OMC_OMC_SUPPORT_PATH/pasteboard"
cmd_guid="$OMC_CURRENT_COMMAND_GUID"
app_path="${OMC_OBJ_PATH}"

if [ -n "$app_path" ] && [[ "$app_path" == *.app ]] && [ -d "$app_path" ] && [ -f "$app_path/Contents/Info.plist" ]; then
    # Valid .app dropped — stash path for project.init, open project window
    "$pasteboard_tool" "appletbuilder_pending_project" set "$app_path"
    "$next_cmd" "$cmd_guid" "AppletBuilder.project"
else
    # No valid app context — open New Applet dialog
    "$next_cmd" "$cmd_guid" "AppletBuilder.new.applet"
fi
