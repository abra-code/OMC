#!/bin/bash
# AppletBuilder.help.url.changed - Update back/forward button state after navigation
# Note: omc_dialog_control cannot read WebView states (canGoBack/canGoForward),
# so we track navigation history ourselves using a counter file.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

# Read and increment navigation count
nav_count=$(pb_get "$PB_HELP_NAV_COUNT")
if [ -z "$nav_count" ]; then
    nav_count=0
fi
nav_count=$((nav_count + 1))
pb_set "$PB_HELP_NAV_COUNT" "$nav_count"

# Enable back button after at least one navigation beyond initial page
if [ "$nav_count" -gt 1 ]; then
    set_enabled "$HELP_BACK_BTN_ID" true
fi

# Forward button: enable after user has gone back at least once
went_back=$(pb_get "$PB_HELP_WENT_BACK")
if [ -n "$went_back" ]; then
    set_enabled "$HELP_FORWARD_BTN_ID" true
fi
