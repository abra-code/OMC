#!/bin/bash
# AppletBuilder.welcome.recent.open - A recent applet double-clicked in the Welcome window opens in
# a project window (which closes the Welcome window). One no longer there is taken off the list.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.prefs.sh"

# The double-clicked row's first column (hidden): the applet's path
applet="${OMC_ACTIONUI_TABLE_1020_COLUMN_1_VALUE%/}"
if [ -z "$applet" ]; then
    exit 0
fi
if [ ! -f "$applet/Contents/Info.plist" ]; then
    # Rewriting the list drops every path that is gone; the window shows the list again
    recent_applets_add ""
    set_value "$WELCOME_NOTE_ID" "$(/usr/bin/basename "$applet") is no longer in its folder."
    "$dialog_tool" "$window_uuid" "$WELCOME_NOTE_ID" omc_set_property "hidden" "false"
    "$next_cmd" "$cmd_guid" "AppletBuilder.welcome.init"
    exit 0
fi
ab_open_project "$applet"
