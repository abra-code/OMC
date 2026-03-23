#!/bin/bash
# AppletBuilder.help.forward - Navigate forward in help viewer

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

# Increment nav count when going forward
state_dir=$(get_state_dir)
nav_count_file="$state_dir/help_nav_count_${window_uuid}"
if [ -f "$nav_count_file" ]; then
    nav_count=$(cat "$nav_count_file")
    nav_count=$((nav_count + 1))
    echo "$nav_count" > "$nav_count_file"
fi

set_value "$HELP_WEBVIEW_ID" "goForward"
