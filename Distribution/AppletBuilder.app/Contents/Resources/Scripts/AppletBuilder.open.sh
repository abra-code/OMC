#!/bin/bash
# AppletBuilder.open - Open an applet selected via CHOOSE_OBJECT_DIALOG

echo "[$(/usr/bin/basename "$0")]"
env | sort

app_path="${OMC_DLG_CHOOSE_OBJECT_PATH}"

if [ -z "$app_path" ] || [[ "$app_path" != *.app ]] || [ ! -d "$app_path" ] || [ ! -f "$app_path/Contents/Info.plist" ]; then
    exit 1
fi

echo "$app_path" > "/tmp/appletbuilder_pending_project"

next_cmd="$OMC_OMC_SUPPORT_PATH/omc_next_command"
"$next_cmd" "$OMC_CURRENT_COMMAND_GUID" "AppletBuilder.project"
