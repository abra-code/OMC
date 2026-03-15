#!/bin/bash
# AppletBuilder.new.template.changed - React to template picker selection

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

selected="${OMC_ACTIONUI_VIEW_201_VALUE}"
templates_dir="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Templates"

if [ "$selected" = "__clone__" ]; then
    # Show clone source row, clear template path
    "$dialog_tool" "$window_uuid" "$NEW_CLONE_SOURCE_ROW_ID" omc_set_property "hidden" "false"
    set_value "$NEW_TEMPLATE_PATH_ID" ""

    # Trigger browse dialog via omc_next_command
    next_cmd="$OMC_OMC_SUPPORT_PATH/omc_next_command"
    "$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "AppletBuilder.new.browse.template"
else
    # Hide clone source row, set template path from Templates dir
    "$dialog_tool" "$window_uuid" "$NEW_CLONE_SOURCE_ROW_ID" omc_set_property "hidden" "true"
    set_value "$NEW_TEMPLATE_PATH_ID" "${templates_dir}/${selected}.applet"
fi
