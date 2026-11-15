#!/bin/bash
# AppletBuilder.services.reload - Refresh just the services table, after an add, remove or save;
# on Linux also the file managers' Services list of an applet on the desktop (applet_services_update)

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.build.sh"

project_path=$(load_project_path)
plist="$project_path/Contents/Info.plist"

if [ ! -f "$plist" ]; then
    exit 0
fi

plister="$plister_tool"
svc_count=$("$plister" get count "$plist" /NSServices 2>/dev/null)

if [ -n "$svc_count" ] && [ "$svc_count" -gt 0 ]; then
    buffer=""
    i=0
    while [ "$i" -lt "$svc_count" ]; do
        menu_title=$("$plister_tool" get value "$plist" "/NSServices/${i}/NSMenuItem/default" 2>/dev/null)
        user_data=$("$plister_tool" get value "$plist" "/NSServices/${i}/NSUserData" 2>/dev/null)
        [ -z "$menu_title" ] && menu_title="$user_data"
        [ -z "$menu_title" ] && menu_title="Service $i"
        buffer="${buffer}${menu_title}	${i}
"
        i=$((i + 1))
    done
    printf "%s" "$buffer" | "$dialog_tool" "$window_uuid" "$SVC_TABLE_ID" omc_table_set_rows_from_stdin
else
    printf "" | "$dialog_tool" "$window_uuid" "$SVC_TABLE_ID" omc_table_set_rows_from_stdin
fi

services_output="$(applet_services_update "$project_path")"
services_status=$?
if [ "$services_status" -ne 0 ]; then
    set_value "$SVC_STATUS_ID" "Not listed for the file manager: $services_output"
fi
