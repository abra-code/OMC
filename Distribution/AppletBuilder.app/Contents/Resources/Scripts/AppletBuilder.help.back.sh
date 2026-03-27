#!/bin/bash
# AppletBuilder.help.back - Navigate back in help viewer

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

# Mark that user went back so forward button can be enabled
pb_set "$PB_HELP_WENT_BACK" "1"

# Decrement nav count so back button disables when at start
nav_count=$(pb_get "$PB_HELP_NAV_COUNT")
if [ -n "$nav_count" ]; then
    nav_count=$((nav_count - 1))
    if [ "$nav_count" -lt 1 ]; then
        nav_count=1
    fi
    pb_set "$PB_HELP_NAV_COUNT" "$nav_count"
fi

set_value "$HELP_WEBVIEW_ID" "#goBack"
