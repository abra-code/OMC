#!/bin/bash
# AppletBuilder.general.minosversion.changed - Save LSMinimumSystemVersion on end editing

echo "AppletBuilder.general.minosversion.changed"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

env

new_version="${OMC_ACTIONUI_VIEW_306_VALUE}"
project_path=$(load_project_path)
plist="$project_path/Contents/Info.plist"

if [ -z "$new_version" ] || [ ! -f "$plist" ]; then
    exit 0
fi

old_version=$(plist_read "$plist" LSMinimumSystemVersion)
if [ "$new_version" != "$old_version" ]; then
    plist_edit "$plist" set_keys LSMinimumSystemVersion "$new_version"
    set_value "$GEN_STATUS_ID" "Min macOS version saved"
fi
