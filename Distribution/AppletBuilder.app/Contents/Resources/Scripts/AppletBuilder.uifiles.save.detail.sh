#!/bin/bash
# Save edited UI file content back to file

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

state_dir=$(get_state_dir)
selected_path=$(cat "$state_dir/uifiles_selected_path" 2>/dev/null)

if [ -z "$selected_path" ]; then
    set_value "$UI_EDITED_LABEL_ID" "Error: no file selected"
    exit 1
fi

edited_content="${OMC_ACTIONUI_VIEW_702_VALUE}"

printf "%s" "$edited_content" > "$selected_path"
if [ "$?" -eq 0 ]; then
    set_enabled "$UI_SAVE_BTN_ID" false
    set_value "$UI_EDITED_LABEL_ID" "Saved"
else
    set_value "$UI_EDITED_LABEL_ID" "Error: failed to save"
fi
