#!/bin/bash
# Preview ActionUI JSON file with ActionUIViewer

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

state_dir=$(get_state_dir)
selected_path=$(cat "$state_dir/uifiles_selected_path" 2>/dev/null)

if [ -z "$selected_path" ] || [ ! -f "$selected_path" ]; then
    set_value "$UI_EDITED_LABEL_ID" "No file selected"
    exit 0
fi

# Check JSON syntax before previewing
json_error=$("$python3" -m json.tool "$selected_path" 2>&1 >/dev/null)
if [ "$?" -ne 0 ]; then
    set_value "$UI_EDITED_LABEL_ID" "Invalid JSON"
    show_errors "Cannot preview — JSON syntax error in $(/usr/bin/basename "$selected_path"):

$json_error"
    exit 0
fi

viewer="${OMC_APP_BUNDLE_PATH}/Contents/Helpers/ActionUIViewer"
if [ -x "$viewer" ]; then
    "$viewer" "$selected_path" &
else
    set_value "$UI_EDITED_LABEL_ID" "ActionUIViewer not found"
fi
