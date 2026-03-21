#!/bin/bash
# AppletBuilder.scripts.add - Open New Script dialog

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)

# Pass project path to the dialog via pasteboard keyed by window UUID
"$pasteboard_tool" "ProjectPath_${OMC_ACTIONUI_WINDOW_UUID}" set "$project_path"

"$next_cmd" "$cmd_guid" "AppletBuilder.scripts.new.dialog"
