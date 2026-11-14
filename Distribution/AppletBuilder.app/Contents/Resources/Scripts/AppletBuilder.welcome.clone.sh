#!/bin/bash
# AppletBuilder.welcome.clone - The Welcome window's Clone button: the New Applet dialog set to
# "Clone Existing App", asking at once for the applet to copy (AppletBuilder.new.init reads the
# mode). The Welcome window stays until a project window opens.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"

pb_set "$PB_NEW_MODE" "clone"
"$next_cmd" "$cmd_guid" "AppletBuilder.new.applet"
