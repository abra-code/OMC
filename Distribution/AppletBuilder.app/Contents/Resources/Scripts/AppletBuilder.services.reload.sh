#!/bin/bash
# AppletBuilder.services.reload - Refresh just the services table

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
plist="$project_path/Contents/Info.plist"

if [ ! -f "$plist" ]; then
    exit 0
fi

plister="$OMC_OMC_SUPPORT_PATH/plister"
svc_count=$("$plister" get count "$plist" /NSServices 2>/dev/null)

if [ -n "$svc_count" ] && [ "$svc_count" -gt 0 ]; then
    buffer=""
    i=0
    while [ "$i" -lt "$svc_count" ]; do
        menu_title=$(/usr/bin/plutil -extract "NSServices.${i}.NSMenuItem.default" raw "$plist" 2>/dev/null)
        user_data=$(/usr/bin/plutil -extract "NSServices.${i}.NSUserData" raw "$plist" 2>/dev/null)
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
