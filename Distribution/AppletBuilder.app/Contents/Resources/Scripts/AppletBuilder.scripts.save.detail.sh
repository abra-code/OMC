#!/bin/bash
# Save edited script content back to file

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

state_dir=$(get_state_dir)
selected_path=$(cat "$state_dir/scripts_selected_path" 2>/dev/null)

if [ -z "$selected_path" ]; then
    set_value "$SCRIPTS_EDITED_LABEL_ID" "Error: no file selected"
    exit 1
fi

edited_content="${OMC_ACTIONUI_VIEW_602_VALUE}"

printf "%s" "$edited_content" > "$selected_path"
if [ "$?" -eq 0 ]; then
    set_enabled "$SCRIPTS_SAVE_BTN_ID" false
    set_value "$SCRIPTS_EDITED_LABEL_ID" "✅ Saved"
else
    set_value "$SCRIPTS_EDITED_LABEL_ID" "Error: failed to save"
fi
