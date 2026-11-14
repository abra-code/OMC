#!/bin/bash

# echo "[$(/usr/bin/basename "$0")]"
# env | sort

# Main command: an applet given at launch (dropped on AppletBuilder, opened with it) opens in its
# project window; with none, the Welcome window (Open, Clone, New Applet, recent applets). The
# command shows no file chooser at launch (USE_NAV_DIALOG_FOR_MISSING_FILE_CONTEXT false): a
# canceled chooser left a Linux AppletBuilder with no window, and it quit.
next_cmd="$OMC_OMC_SUPPORT_PATH/omc_next_command"
pasteboard_tool="$OMC_OMC_SUPPORT_PATH/pasteboard"
cmd_guid="$OMC_CURRENT_COMMAND_GUID"
app_path="${OMC_OBJ_PATH%/}"

if [ -n "$app_path" ] && [[ "$app_path" == *.app ]] && [ -d "$app_path" ] && [ -f "$app_path/Contents/Info.plist" ]; then
    # Valid .app dropped — stash path for project.init, open project window
    "$pasteboard_tool" "appletbuilder_pending_project" set "$app_path"
    "$next_cmd" "$cmd_guid" "AppletBuilder.project"
else
    "$next_cmd" "$cmd_guid" "AppletBuilder.welcome"
fi
