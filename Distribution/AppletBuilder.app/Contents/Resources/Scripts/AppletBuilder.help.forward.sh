#!/bin/bash
# AppletBuilder.help.forward - Navigate forward in help viewer

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

# Increment nav count when going forward
nav_count=$(pb_get "$PB_HELP_NAV_COUNT")
if [ -n "$nav_count" ]; then
    nav_count=$((nav_count + 1))
    pb_set "$PB_HELP_NAV_COUNT" "$nav_count"
fi

set_value "$HELP_WEBVIEW_ID" "goForward"
