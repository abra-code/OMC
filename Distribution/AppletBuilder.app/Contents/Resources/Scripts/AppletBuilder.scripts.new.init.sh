#!/bin/bash
# AppletBuilder.scripts.new.init - Populate New Script dialog with defaults

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

# Suggest a script name based on app name
app_name=$(/usr/bin/basename "${project_path%.app}")
app_lower=$(echo "$app_name" | /usr/bin/tr '[:upper:]' '[:lower:]')
set_value "$NEWSCRIPT_NAME_ID" "${app_lower}.new.script"
set_value "$NEWSCRIPT_TYPE_ID" "sh"
