#!/bin/bash
# AppletBuilder.general.bundleid.changed - Save bundle ID on end editing

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

new_bundle_id="${OMC_ACTIONUI_VIEW_303_VALUE}"
project_path=$(load_project_path)
plist="$project_path/Contents/Info.plist"

if [ -z "$new_bundle_id" ] || [ ! -f "$plist" ]; then
    exit 0
fi

old_bundle_id=$(plist_read "$plist" CFBundleIdentifier)
if [ "$new_bundle_id" != "$old_bundle_id" ]; then
    plist_edit "$plist" set_keys CFBundleIdentifier "$new_bundle_id"
    set_value "$GEN_STATUS_ID" "Bundle ID saved"
fi
