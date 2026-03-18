#!/bin/bash
# AppletBuilder.services.save - Auto-save service details on any field/picker change

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
plist="$project_path/Contents/Info.plist"

state_dir=$(get_state_dir)
svc_index=$(cat "$state_dir/svc_selected_index" 2>/dev/null)

if [ -z "$svc_index" ] || [ ! -f "$plist" ]; then
    exit 0
fi

menu_title="${OMC_ACTIONUI_VIEW_331_VALUE}"
command_id="${OMC_ACTIONUI_VIEW_332_VALUE}"
input_type="${OMC_ACTIONUI_VIEW_333_VALUE}"

if [ -z "$menu_title" ] || [ -z "$command_id" ]; then
    exit 0
fi

plist_edit "$plist" update_service "$svc_index" "$menu_title" "$command_id" "$input_type"

set_value "$SVC_STATUS_ID" "Service saved"
"$next_cmd" "${OMC_CURRENT_COMMAND_GUID}" "AppletBuilder.services.reload"
