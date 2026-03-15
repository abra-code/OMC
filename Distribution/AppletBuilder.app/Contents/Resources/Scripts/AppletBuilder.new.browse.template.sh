#!/bin/bash
# AppletBuilder.new.browse.template - Set clone source path from file picker result

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

if [ -n "$OMC_DLG_CHOOSE_OBJECT_PATH" ]; then
    set_value "$NEW_TEMPLATE_PATH_ID" "$OMC_DLG_CHOOSE_OBJECT_PATH"
    "$dialog_tool" "$window_uuid" "$NEW_CLONE_SOURCE_ROW_ID" omc_set_property "hidden" "false"
fi
