#!/bin/bash
# AppletBuilder.new.icon.changed - React to icon picker selection

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

selected="${OMC_ACTIONUI_VIEW_209_VALUE}"
icons_dir="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Icons"

if [ "$selected" = "__custom__" ]; then
    # Show custom icon path row, trigger browse dialog
    "$dialog_tool" "$window_uuid" "$NEW_CUSTOM_ICON_ROW_ID" omc_set_property "hidden" "false"

    next_cmd="$OMC_OMC_SUPPORT_PATH/omc_next_command"
    "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "AppletBuilder.new.browse.icon"
else
    # Hide custom icon path row, clear custom path
    "$dialog_tool" "$window_uuid" "$NEW_CUSTOM_ICON_ROW_ID" omc_set_property "hidden" "true"
    set_value "$NEW_ICON_ID" ""

    # Update header icon from precompiled .icns
    icns_path="${icons_dir}/${selected}.icns"
    if [ -f "$icns_path" ]; then
        set_value "$NEW_HEADER_IMAGE_ID" "$icns_path"
    fi
fi
