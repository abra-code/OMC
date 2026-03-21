#!/bin/bash
# AppletBuilder.uifiles.edit - Open selected UI file in external editor

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

# Get selected path from hidden column 2
selected_path="$OMC_ACTIONUI_TABLE_701_COLUMN_2_VALUE"

if [ -z "$selected_path" ]; then
    exit 0
fi

if [ -d "$selected_path" ]; then
    # It's a .nib bundle — open with Xcode
    /usr/bin/open -a Xcode "$selected_path"
elif [ -f "$selected_path" ]; then
    editor=$(get_external_editor)
    /usr/bin/open -a "$editor" "$selected_path"
fi
