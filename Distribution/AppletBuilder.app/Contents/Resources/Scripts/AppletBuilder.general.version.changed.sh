#!/bin/bash
# AppletBuilder.general.version.changed - Save version on end editing

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

new_version="${OMC_ACTIONUI_VIEW_305_VALUE}"
project_path=$(load_project_path)
plist="$project_path/Contents/Info.plist"

if [ -z "$new_version" ] || [ ! -f "$plist" ]; then
    exit 0
fi

old_version=$(plist_read "$plist" CFBundleVersion)
if [ "$new_version" != "$old_version" ]; then
    plist_edit "$plist" set_keys CFBundleVersion "$new_version"
    set_value "$GEN_STATUS_ID" "Version saved"
fi
