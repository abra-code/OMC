#!/bin/bash
# AppletBuilder.uifiles.selected - Show selected UI file content and enable buttons

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

# Get selected path from hidden column 2
selected_path="$OMC_ACTIONUI_TABLE_701_COLUMN_2_VALUE"

if [ -z "$selected_path" ]; then
    # No selection — disable all buttons, clear detail
    set_enabled "$UI_REMOVE_BTN_ID" false
    set_enabled "$UI_REVEAL_BTN_ID" false
    set_enabled "$UI_VALIDATE_BTN_ID" false
    set_enabled "$UI_PRETTIFY_BTN_ID" false
    set_enabled "$UI_PREVIEW_BTN_ID" false
    set_enabled "$UI_SAVE_BTN_ID" false
    set_enabled "$UI_EXT_EDIT_BTN_ID" false
    set_value "$UI_DETAIL_ID" ""
    set_value "$UI_EDITED_LABEL_ID" ""
    exit 0
fi

# Store selected path for save/validate/preview handlers
state_dir=$(get_state_dir)
echo "$selected_path" > "$state_dir/uifiles_selected_path"

# Enable common action buttons
set_enabled "$UI_REMOVE_BTN_ID" true
set_enabled "$UI_REVEAL_BTN_ID" true
set_enabled "$UI_EXT_EDIT_BTN_ID" true

if [ -d "$selected_path" ]; then
    # It's a .nib bundle — hide JSON-specific buttons, show placeholder in editor
    set_enabled "$UI_VALIDATE_BTN_ID" false
    set_enabled "$UI_PRETTIFY_BTN_ID" false
    set_enabled "$UI_PREVIEW_BTN_ID" false
    set_enabled "$UI_SAVE_BTN_ID" false
    set_value "$UI_DETAIL_ID" "Interface Builder Nib — use 'Edit' to open in Xcode"
    set_value "$UI_EDITED_LABEL_ID" ""
elif [ -f "$selected_path" ]; then
    # JSON or other text file — enable all toolbar buttons
    set_enabled "$UI_VALIDATE_BTN_ID" true
    set_enabled "$UI_PRETTIFY_BTN_ID" true
    set_enabled "$UI_PREVIEW_BTN_ID" true
    # Save starts disabled until text is edited
    set_enabled "$UI_SAVE_BTN_ID" false
    set_value "$UI_EDITED_LABEL_ID" ""

    content=$(/bin/cat "$selected_path")
    set_value "$UI_DETAIL_ID" "$content"
else
    set_value "$UI_DETAIL_ID" "File not found: $selected_path"
    set_value "$UI_EDITED_LABEL_ID" ""
fi
