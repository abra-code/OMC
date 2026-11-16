#!/bin/bash
# AppletBuilder.services.save - Auto-save service details on any field/picker change

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.plist.sh"

project_path=$(load_project_path)
plist="$project_path/Contents/Info.plist"

svc_index=$(pb_get "$PB_SVC_SELECTED")

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
edit_status=$?
if [ "$edit_status" -ne 0 ]; then
    set_value "$SVC_STATUS_ID" "Error saving service"
    exit 1
fi

# The picker shows the kind the service has now: "Other File Types" chosen for a service with no
# other types keeps it as it was (update_service changes nothing), and the picker goes back to it
saved_kind="$(info_plist_service_kind "$plist" "$svc_index")"
if [ -n "$saved_kind" ] && [ "$saved_kind" != "$input_type" ]; then
    set_value "$SVC_INPUT_PICKER_ID" "$saved_kind"
fi

if [ "$input_type" = "other" ] && [ "$saved_kind" != "other" ]; then
    set_value "$SVC_STATUS_ID" "Other File Types keeps types a service declares; this one has none to keep"
else
    set_value "$SVC_STATUS_ID" "Service saved"
fi
"$next_cmd" "${OMC_CURRENT_COMMAND_GUID}" "AppletBuilder.services.reload"
