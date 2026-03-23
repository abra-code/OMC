#!/bin/bash
# AppletBuilder.help.url.changed - Update back/forward button state after navigation
# Note: omc_dialog_control cannot read WebView states (canGoBack/canGoForward),
# so we track navigation history ourselves using a counter file.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

state_dir=$(get_state_dir)
nav_count_file="$state_dir/help_nav_count_${window_uuid}"

# Read and increment navigation count
nav_count=0
if [ -f "$nav_count_file" ]; then
    nav_count=$(cat "$nav_count_file")
fi
nav_count=$((nav_count + 1))
echo "$nav_count" > "$nav_count_file"

# Enable back button after at least one navigation beyond initial page
if [ "$nav_count" -gt 1 ]; then
    set_enabled "$HELP_BACK_BTN_ID" true
fi

# Forward button: enable after user has gone back at least once
fwd_file="$state_dir/help_went_back_${window_uuid}"
if [ -f "$fwd_file" ]; then
    set_enabled "$HELP_FORWARD_BTN_ID" true
fi
