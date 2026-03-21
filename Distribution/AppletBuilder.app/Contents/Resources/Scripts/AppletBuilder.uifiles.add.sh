#!/bin/bash
# AppletBuilder.uifiles.add - Open New UI File dialog

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)

# Pass project path to the dialog via pasteboard keyed by window UUID
"$pasteboard_tool" "ProjectPath_${OMC_ACTIONUI_WINDOW_UUID}" set "$project_path"

"$next_cmd" "$cmd_guid" "AppletBuilder.uifiles.new.dialog"
