#!/bin/bash
# AppletBuilder.uifiles.new.init - Populate New UI File dialog with defaults

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
# Dialog has its own window UUID — read project path from parent dialog's pasteboard
if [ -z "$project_path" ] && [ -n "$OMC_PARENT_DIALOG_GUID" ]; then
    project_path=$("$pasteboard_tool" "ProjectPath_${OMC_PARENT_DIALOG_GUID}" get)
    "$pasteboard_tool" "ProjectPath_${OMC_PARENT_DIALOG_GUID}" set ""
    if [ -n "$project_path" ] && [ -d "$project_path" ]; then
        save_project_path "$project_path"
    fi
fi

set_value "$NEWUI_NAME_ID" "NewDialog"
set_value "$NEWUI_TYPE_ID" "actionui"
