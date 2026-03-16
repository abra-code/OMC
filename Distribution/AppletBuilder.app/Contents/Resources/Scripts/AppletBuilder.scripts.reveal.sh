#!/bin/bash
# AppletBuilder.scripts.reveal - Reveal selected script in Finder

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

# Get selected path from hidden column 2
selected_path="$OMC_ACTIONUI_TABLE_601_COLUMN_2_VALUE"

if [ -n "$selected_path" ] && [ -e "$selected_path" ]; then
    /usr/bin/open -R "$selected_path"
fi
