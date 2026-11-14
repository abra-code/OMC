#!/bin/bash
# AppletBuilder.welcome.new - The Welcome window's New Applet button: the New Applet dialog as the
# File menu's New opens it. The Welcome window stays until a project window opens.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"

pb_set "$PB_NEW_MODE" ""
"$next_cmd" "$cmd_guid" "AppletBuilder.new.applet"
