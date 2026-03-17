#!/bin/bash
# builder.project.init - Initialize the project window with the applet info

echo "[$(/usr/bin/basename "$0")]"
env | sort

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

# Read the pending project path stashed by the main dispatch script
# general.loaded may have already consumed the pending file (race), so
# check the window-keyed state dir as a fallback
pending="/tmp/appletbuilder_pending_project"
if [ -f "$pending" ]; then
    app_path=$(cat "$pending")
    /bin/rm -f "$pending"
else
    app_path=$(load_project_path)
fi

# Validate
if [ -z "$app_path" ] || [ ! -d "$app_path" ] || [ ! -f "$app_path/Contents/Info.plist" ]; then
    exit 1
fi

# Store project path (now keyed to this window's UUID)
save_project_path "$app_path"
