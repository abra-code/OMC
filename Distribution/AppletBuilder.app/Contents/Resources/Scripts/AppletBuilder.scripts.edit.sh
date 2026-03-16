#!/bin/bash
# AppletBuilder.scripts.edit - Open selected script in external editor

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

# Get selected path from hidden column 2
selected_path="$OMC_ACTIONUI_TABLE_601_COLUMN_2_VALUE"

if [ -n "$selected_path" ] && [ -f "$selected_path" ]; then
    /usr/bin/open -e "$selected_path"
fi
