#!/bin/bash
# AppletBuilder.scripts.selected - Show selected script content and enable buttons

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

# Get selected path from hidden column 2
selected_path="$OMC_ACTIONUI_TABLE_601_COLUMN_2_VALUE"

if [ -z "$selected_path" ]; then
    # No selection — disable buttons, clear detail
    set_enabled "$SCRIPTS_REMOVE_BTN_ID" false
    set_enabled "$SCRIPTS_REVEAL_BTN_ID" false
    set_enabled "$SCRIPTS_SAVE_BTN_ID" false
    set_enabled "$SCRIPTS_EXT_EDIT_BTN_ID" false
    set_value "$SCRIPTS_DETAIL_ID" ""
    set_value "$SCRIPTS_EDITED_LABEL_ID" ""
    exit 0
fi

# Enable action buttons
set_enabled "$SCRIPTS_REMOVE_BTN_ID" true
set_enabled "$SCRIPTS_REVEAL_BTN_ID" true
set_enabled "$SCRIPTS_EXT_EDIT_BTN_ID" true
# Save starts disabled until text is edited
set_enabled "$SCRIPTS_SAVE_BTN_ID" false
set_value "$SCRIPTS_EDITED_LABEL_ID" ""

# Store selected path for save handler
state_dir=$(get_state_dir)
echo "$selected_path" > "$state_dir/scripts_selected_path"

if [ -f "$selected_path" ]; then
    content=$(/bin/cat "$selected_path")
    set_value "$SCRIPTS_DETAIL_ID" "$content"
else
    set_value "$SCRIPTS_DETAIL_ID" "File not found: $selected_path"
fi
