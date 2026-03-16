#!/bin/bash
# AppletBuilder.uifiles.selected - Show selected UI file content and enable buttons

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

# Get selected path from hidden column 2
selected_path="$OMC_ACTIONUI_TABLE_701_COLUMN_2_VALUE"

if [ -z "$selected_path" ]; then
    # No selection — disable buttons, clear detail, hide nib pane
    set_enabled "$UI_REMOVE_BTN_ID" false
    set_enabled "$UI_EDIT_BTN_ID" false
    set_enabled "$UI_REVEAL_BTN_ID" false
    set_value "$UI_DETAIL_ID" ""
    set_visible "$UI_DETAIL_ID" true
    set_visible "$UI_NIB_PANE_ID" false
    exit 0
fi

# Enable action buttons
set_enabled "$UI_REMOVE_BTN_ID" true
set_enabled "$UI_EDIT_BTN_ID" true
set_enabled "$UI_REVEAL_BTN_ID" true

if [ -d "$selected_path" ]; then
    # It's a .nib bundle — hide TextEditor, show "Open in Xcode" pane
    set_visible "$UI_DETAIL_ID" false
    set_visible "$UI_NIB_PANE_ID" true
elif [ -f "$selected_path" ]; then
    # JSON or other text file — show TextEditor, hide nib pane
    set_visible "$UI_DETAIL_ID" true
    set_visible "$UI_NIB_PANE_ID" false
    content=$(/bin/cat "$selected_path")
    set_value "$UI_DETAIL_ID" "$content"
else
    set_visible "$UI_DETAIL_ID" true
    set_visible "$UI_NIB_PANE_ID" false
    set_value "$UI_DETAIL_ID" "File not found: $selected_path"
fi
