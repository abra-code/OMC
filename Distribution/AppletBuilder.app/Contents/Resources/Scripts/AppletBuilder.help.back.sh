#!/bin/bash
# AppletBuilder.help.back - Navigate back in help viewer

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

# Mark that user went back so forward button can be enabled
state_dir=$(get_state_dir)
touch "$state_dir/help_went_back_${window_uuid}"

# Decrement nav count so back button disables when at start
nav_count_file="$state_dir/help_nav_count_${window_uuid}"
if [ -f "$nav_count_file" ]; then
    nav_count=$(cat "$nav_count_file")
    nav_count=$((nav_count - 1))
    if [ "$nav_count" -lt 1 ]; then
        nav_count=1
    fi
    echo "$nav_count" > "$nav_count_file"
fi

set_value "$HELP_WEBVIEW_ID" "goBack"
